-- ============================================================
-- SalesPlace — شاشة المبيعات: قنوات البيع وأداء الموظفين (من أعمدة ملف التخصيص الجديدة)
-- ============================================================
-- أعمدة الملف: «القنوات» (مركز بيع / مبيعات الرقمية / مبيعات الهاتف / البيع المباشر …)،
-- «موقع العمل»، «Employee Name». تُجمَّع لعقود الملف (حالة الحجز = عقد) لكل يوم توقيع × قطاع المشروع
-- × NHC/مطور — فتتبع فترة جدول المشاريع بالشاشة (اليوم / أمس / الأسبوع / الشهر / السنة) وتصفية المنطقة.
--
-- يتطلّب: tv_file_counts.sql (tv_region). شغّل هذا الملف مرة واحدة ثم ارفع ملف التخصيص. آمن لإعادة التشغيل.
-- ============================================================

create table if not exists tv_channel_daily (
  contract_date date not null,
  sector text not null default '',
  kind text not null default 'other',
  channel text not null default '',          -- فارغ = غير مذكور
  cnt integer not null,
  updated_at timestamptz not null default now(),
  primary key (contract_date, sector, kind, channel)
);
alter table tv_channel_daily enable row level security;
drop policy if exists tv_channel_daily_read on tv_channel_daily;
create policy tv_channel_daily_read on tv_channel_daily for select using (true);

create table if not exists tv_employee_daily (
  contract_date date not null,
  sector text not null default '',
  kind text not null default 'other',
  employee text not null,
  work_location text not null default '',
  cnt integer not null,
  updated_at timestamptz not null default now(),
  primary key (contract_date, sector, kind, employee, work_location)
);
alter table tv_employee_daily enable row level security;
drop policy if exists tv_employee_daily_read on tv_employee_daily;
create policy tv_employee_daily_read on tv_employee_daily for select using (true);

-- رفع على دفعات (الأولى تمسح القديم) — يتطلّب صلاحية أدمن فعلية
create or replace function admin_load_tv_force(p_admin text, p_pass text, p_table text, p_rows jsonb, p_reset boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  if p_table = 'channels' then
    if p_reset then delete from tv_channel_daily where true; end if;
    insert into tv_channel_daily (contract_date, sector, kind, channel, cnt)
    select (r->>'contract_date')::date, coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'),
           coalesce(btrim(r->>'channel'), ''), sum((r->>'cnt')::int)
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'contract_date', '') is not null
    group by 1, 2, 3, 4
    on conflict (contract_date, sector, kind, channel) do update set cnt = tv_channel_daily.cnt + excluded.cnt, updated_at = now();
  elsif p_table = 'employees' then
    if p_reset then delete from tv_employee_daily where true; end if;
    insert into tv_employee_daily (contract_date, sector, kind, employee, work_location, cnt)
    select (r->>'contract_date')::date, coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'),
           btrim(r->>'employee'), coalesce(btrim(r->>'work'), ''), sum((r->>'cnt')::int)
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'contract_date', '') is not null and nullif(btrim(r->>'employee'), '') is not null
    group by 1, 2, 3, 4, 5
    on conflict (contract_date, sector, kind, employee, work_location) do update set cnt = tv_employee_daily.cnt + excluded.cnt, updated_at = now();
  else
    return jsonb_build_object('ok', false, 'msg', 'جدول غير معروف');
  end if;
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- القنوات والموظفون لفترة — بقطاع المشروع المطبَّع (للتصفية حسب المنطقة) و NHC/مطور
create or replace function get_tv_force(p_from date, p_to date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'ok', true, 'from', p_from, 'to', p_to,
    'has_channels', exists(select 1 from tv_channel_daily where channel <> ''),
    'has_employees', exists(select 1 from tv_employee_daily),
    'channels', coalesce((
      select jsonb_agg(jsonb_build_object('sector', sec, 'kind', kind, 'channel', channel, 'cnt', c))
      from (select tv_region(nullif(sector, ''), null) as sec, kind, channel, sum(cnt) as c
            from tv_channel_daily where contract_date between p_from and p_to group by 1, 2, 3) x
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object('sector', sec, 'kind', kind, 'employee', employee, 'work', work_location, 'cnt', c))
      from (select tv_region(nullif(sector, ''), null) as sec, kind, employee, work_location, sum(cnt) as c
            from tv_employee_daily where contract_date between p_from and p_to group by 1, 2, 3, 4) y
    ), '[]'::jsonb)
  );
$$;

-- ============================================================
-- منحنى قيمة العقود المنفّذة (شموع: أدنى/أعلى/الربيعيات) — لكل يوم توقيع × قطاع × NHC/مطور × نوع الوحدة
-- من ملف التخصيص: سعر العقد (وإلا سعر الوزارة للمستفيد والسعر المعلن لغيره). يُحمَّل مع رفع ملف التخصيص.
-- ============================================================
create table if not exists tv_price_daily (
  contract_date date not null,
  sector text not null default '',
  kind text not null default 'other',
  unit_type text not null default '',
  n integer not null,
  psum numeric not null,
  pmin numeric not null,
  pmax numeric not null,
  p25 numeric, p50 numeric, p75 numeric,
  updated_at timestamptz not null default now(),
  primary key (contract_date, sector, kind, unit_type)
);
alter table tv_price_daily enable row level security;
drop policy if exists tv_price_daily_read on tv_price_daily;
create policy tv_price_daily_read on tv_price_daily for select using (true);

create or replace function admin_load_tv_prices(p_admin text, p_pass text, p_rows jsonb, p_reset boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;
  if p_reset then delete from tv_price_daily where true; end if;
  insert into tv_price_daily (contract_date, sector, kind, unit_type, n, psum, pmin, pmax, p25, p50, p75)
  select (r->>'contract_date')::date, coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'), coalesce(btrim(r->>'unit_type'), ''),
         (r->>'n')::int, (r->>'psum')::numeric, (r->>'pmin')::numeric, (r->>'pmax')::numeric,
         nullif(r->>'p25', '')::numeric, nullif(r->>'p50', '')::numeric, nullif(r->>'p75', '')::numeric
  from jsonb_array_elements(p_rows) r
  where nullif(r->>'contract_date', '') is not null
  on conflict (contract_date, sector, kind, unit_type) do update set
    n = excluded.n, psum = excluded.psum, pmin = excluded.pmin, pmax = excluded.pmax,
    p25 = excluded.p25, p50 = excluded.p50, p75 = excluded.p75, updated_at = now();
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

create or replace function get_tv_prices(p_from date, p_to date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'ok', true, 'from', p_from, 'to', p_to,
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object('d', contract_date, 'sector', tv_region(nullif(sector, ''), null), 'kind', kind, 'type', unit_type,
        'n', n, 'psum', psum, 'min', pmin, 'max', pmax, 'p25', p25, 'p50', p50, 'p75', p75) order by contract_date)
      from tv_price_daily where contract_date between p_from and p_to
    ), '[]'::jsonb)
  );
$$;
