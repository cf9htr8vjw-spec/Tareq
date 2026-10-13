-- ============================================================
-- SalesPlace — شاشة المبيعات: الإيرادات (المستهدف والمحقق) — منهجية جدول «المستهدف والمحقق حسب
-- مذكرات الاستثمار (الإيرادات والتحصيل)»
-- ============================================================
-- • الإيراد المستحق الآن (تراكمي، كل العقود منذ بداية المشروع):
--     عقود التمويل البنكي × 20% (الدفعة المقدمة في وافي)
--   + عقود الشراء النقدي × نسبة جدول دفعات المشروع
--   السعر: moh_price للمستفيدين و price لغير المستفيدين (ملف التخصيص).
-- • الدانيات داخل النطاق (عقوداً ومستهدفاً): مستهدفها من الملف الماستر يُضاف هنا لـ dashboard_targets،
--   وإيرادها المستحق = عقودها البنكية × 20% (لا دفعة مقدمة نقدية لها بجدول الإيرادات).
-- • نسبة جدول الدفعات لكل مشروع تُشتق من آخر جدول إيرادات مرفوع (ورقة «المناطق والمشاريع»):
--     المستحق النقدي ÷ (قيمة العقود − المستحق البنكي ÷ 20%)
--   مشروع غير موجود بالجدول يأخذ متوسط منطقته. المشاريع «المستبعدة» بالجدول (المباعة والدانيات) خارج النطاق.
-- • الإنجاز المالي = الإيراد المستحق التراكمي ÷ مستهدف المذكرة التراكمي ≤ السنة (dashboard_targets.revenue).
--
-- يتطلّب: tv_board_upload.sql مُشغَّلاً قبله. شغّل هذا الملف مرة واحدة، ثم من الشاشة («⬆ رفع ملف»):
-- ارفع جدول الإيرادات (الإكسل) مرة، ثم ملف التخصيص. آمن لإعادة التشغيل.
-- ============================================================

alter table tv_contract_daily add column if not exists fin_sum  numeric not null default 0;  -- قيمة العقود الممولة بنكياً
alter table tv_contract_daily add column if not exists fin_n    integer not null default 0;
alter table tv_contract_daily add column if not exists cash_sum numeric not null default 0;  -- قيمة عقود الشراء النقدي
alter table tv_contract_daily add column if not exists cash_n   integer not null default 0;

-- الدانيات ضمن نطاق الداشبورد (عقودها محسوبة بالمحقق، فمستهدفها بالمقام أيضاً) — من الملف الماستر للمذكرات،
-- ورقة «الخطة بالسنوات»: الوحدات المباعة وإيراد تطوير الوحدات السكنية لكل سنة
insert into dashboard_targets (scope, project_name, slide_name, project_code, sector, city, year, units, revenue, source) values
  ('nhc','دانية السدن','دانية السدن','01-02-0043','الغربي','جدة',2024,54,0,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية السدن','دانية السدن','01-02-0043','الغربي','جدة',2025,298,27712406,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية السدن','دانية السدن','01-02-0043','الغربي','جدة',2026,622,134051876,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية السدن','دانية السدن','01-02-0043','الغربي','جدة',2027,758,272814360,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية السدن','دانية السدن','01-02-0043','الغربي','جدة',2028,974,466450415,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية السدن','دانية السدن','01-02-0043','الغربي','جدة',2029,0,153978328,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الفرسان','دانية الفرسان',null,'الأوسط','الرياض',2025,484,15600220,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الفرسان','دانية الفرسان',null,'الأوسط','الرياض',2026,968,144833859,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الفرسان','دانية الفرسان',null,'الأوسط','الرياض',2027,484,311118021,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الفرسان','دانية الفرسان',null,'الأوسط','الرياض',2028,0,95728622,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الفرسان','دانية الفرسان',null,'الأوسط','الرياض',2029,0,179141281,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية المشرقية','دانية المشرقية','01-01-0058','الأوسط','الرياض',2024,95,0,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية المشرقية','دانية المشرقية','01-01-0058','الأوسط','الرياض',2025,362,57952466,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية المشرقية','دانية المشرقية','01-01-0058','الأوسط','الرياض',2026,610,159455418,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية المشرقية','دانية المشرقية','01-01-0058','الأوسط','الرياض',2027,839,330694275,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية المشرقية','دانية المشرقية','01-01-0058','الأوسط','الرياض',2028,0,177255700,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الأصالة','دانية الاصاله','01-01-0060','الأوسط','الرياض',2024,113,0,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الأصالة','دانية الاصاله','01-01-0060','الأوسط','الرياض',2025,454,85644128,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الأصالة','دانية الاصاله','01-01-0060','الأوسط','الرياض',2026,693,229282571,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الأصالة','دانية الاصاله','01-01-0060','الأوسط','الرياض',2027,0,178379534,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الحوية (دانية وديانا)','دانية وديانا','01-02-0037','الغربي','الطائف',2024,24,0,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الحوية (دانية وديانا)','دانية وديانا','01-02-0037','الغربي','الطائف',2025,285,51801382,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الحوية (دانية وديانا)','دانية وديانا','01-02-0037','الغربي','الطائف',2026,879,172766148,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الحوية (دانية وديانا)','دانية وديانا','01-02-0037','الغربي','الطائف',2027,0,274771029,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الغروب (دانية النقل)','دانية الغروب','01-03-0020','الغربي','المدينة المنورة',2024,32,0,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الغروب (دانية النقل)','دانية الغروب','01-03-0020','الغربي','المدينة المنورة',2025,257,39463588,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الغروب (دانية النقل)','دانية الغروب','01-03-0020','الغربي','المدينة المنورة',2026,337,110437797,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الغروب (دانية النقل)','دانية الغروب','01-03-0020','الغربي','المدينة المنورة',2027,980,233396443,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)'),
  ('nhc','دانية الغروب (دانية النقل)','دانية الغروب','01-03-0020','الغربي','المدينة المنورة',2028,0,250910095,'مذكرات الاستثمار — الخطة بالسنوات (الدانيات)')
on conflict (scope, project_name, year) do update set slide_name = excluded.slide_name, project_code = excluded.project_code,
  sector = excluded.sector, city = excluded.city, units = excluded.units, revenue = excluded.revenue, source = excluded.source, updated_at = now();

-- القيمة التراكمية لعقود كل مشروع (كل العقود حتى آخر رفع لملف التخصيص) — ممول بنكياً / نقدي
create table if not exists tv_project_value (
  project_name text not null,
  project_code text not null default '',
  sector text not null default '',
  kind text not null default 'other',
  cnt integer not null default 0,
  fin_sum numeric not null default 0, fin_n integer not null default 0,
  cash_sum numeric not null default 0, cash_n integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (project_name, project_code, sector, kind)
);
alter table tv_project_value add column if not exists first_date date;  -- أول عقد بالمشروع (لتمييز المشروع الجديد)
alter table tv_project_value enable row level security;
drop policy if exists tv_project_value_read on tv_project_value;
create policy tv_project_value_read on tv_project_value for select using (true);

-- معاملات الإيراد من جدول الإيرادات المرفوع: نسبة الدفعة النقدية لكل مشروع، والمستبعد، ولقطة أرقام الجدول للتحقق
create table if not exists tv_rev_params (
  name text primary key,
  norm text not null,
  sector text,
  is_region boolean not null default false,
  excluded boolean not null default false,
  cash_pct numeric,
  cum_value numeric, cash_due numeric, bank_due numeric, target_cum numeric,
  as_of date,
  updated_at timestamptz not null default now()
);
create index if not exists tv_rev_params_norm_idx on tv_rev_params(norm);
alter table tv_rev_params enable row level security;
drop policy if exists tv_rev_params_read on tv_rev_params;
create policy tv_rev_params_read on tv_rev_params for select using (true);

-- مفتاح مطابقة أسماء المشاريع بين جدول الإيرادات وملف التخصيص: بلا مسافات وشرطات و«NHC»
create or replace function tv_rev_key(p text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(lower(coalesce(tv_norm_name(p), '')), '(nhc|[[:space:]\-–—·_.,()]+)', '', 'g'), '')
$$;

create or replace function admin_load_tv_rev(p_admin text, p_pass text, p_rows jsonb)
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
  delete from tv_rev_params where true;
  insert into tv_rev_params (name, norm, sector, is_region, excluded, cash_pct, cum_value, cash_due, bank_due, target_cum, as_of)
  select distinct on (btrim(r->>'name')) btrim(r->>'name'), coalesce(tv_norm_name(r->>'name'), btrim(r->>'name')),
         nullif(btrim(r->>'sector'), ''), coalesce((r->>'is_region')::boolean, false), coalesce((r->>'excluded')::boolean, false),
         nullif(r->>'cash_pct', '')::numeric, nullif(r->>'cum_value', '')::numeric, nullif(r->>'cash_due', '')::numeric,
         nullif(r->>'bank_due', '')::numeric, nullif(r->>'target_cum', '')::numeric, nullif(r->>'as_of', '')::date
  from jsonb_array_elements(p_rows) r
  where nullif(btrim(r->>'name'), '') is not null
  order by btrim(r->>'name');
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- ---------- رفع الجدولين على دفعات (الأولى تمسح القديم) — يتطلّب صلاحية أدمن فعلية ----------
create or replace function admin_load_tv_alloc(p_admin text, p_pass text, p_table text, p_rows jsonb, p_reset boolean)
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

  if p_table = 'contracts' then
    if p_reset then delete from tv_contract_daily where true; end if;
    insert into tv_contract_daily (contract_date, project_name, sector, dest, kind, unit_type, cnt, price_sum, price_n,
                                   fin_sum, fin_n, cash_sum, cash_n)
    select (r->>'contract_date')::date, coalesce(btrim(r->>'project_name'), ''), coalesce(btrim(r->>'sector'), ''),
           coalesce(btrim(r->>'dest'), ''), coalesce(r->>'kind', 'other'), coalesce(btrim(r->>'unit_type'), ''),
           sum((r->>'cnt')::int), sum(coalesce(nullif(r->>'price_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'price_n', '')::int, 0)),
           sum(coalesce(nullif(r->>'fin_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'fin_n', '')::int, 0)),
           sum(coalesce(nullif(r->>'cash_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'cash_n', '')::int, 0))
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'contract_date', '') is not null
    group by 1, 2, 3, 4, 5, 6
    on conflict (contract_date, project_name, sector, dest, kind, unit_type) do update set
      cnt = tv_contract_daily.cnt + excluded.cnt, price_sum = tv_contract_daily.price_sum + excluded.price_sum,
      price_n = tv_contract_daily.price_n + excluded.price_n,
      fin_sum = tv_contract_daily.fin_sum + excluded.fin_sum, fin_n = tv_contract_daily.fin_n + excluded.fin_n,
      cash_sum = tv_contract_daily.cash_sum + excluded.cash_sum, cash_n = tv_contract_daily.cash_n + excluded.cash_n,
      updated_at = now();
  elsif p_table = 'value' then
    if p_reset then delete from tv_project_value where true; end if;
    insert into tv_project_value (project_name, project_code, sector, kind, cnt, fin_sum, fin_n, cash_sum, cash_n, first_date)
    select btrim(r->>'project_name'), coalesce(btrim(r->>'project_code'), ''), coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'),
           sum((r->>'cnt')::int), sum(coalesce(nullif(r->>'fin_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'fin_n', '')::int, 0)),
           sum(coalesce(nullif(r->>'cash_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'cash_n', '')::int, 0)),
           min(nullif(r->>'first_date', '')::date)
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'project_name'), '') is not null
    group by 1, 2, 3, 4
    on conflict (project_name, project_code, sector, kind) do update set
      cnt = tv_project_value.cnt + excluded.cnt,
      fin_sum = tv_project_value.fin_sum + excluded.fin_sum, fin_n = tv_project_value.fin_n + excluded.fin_n,
      cash_sum = tv_project_value.cash_sum + excluded.cash_sum, cash_n = tv_project_value.cash_n + excluded.cash_n,
      first_date = least(tv_project_value.first_date, excluded.first_date),
      updated_at = now();
  elsif p_table = 'status' then
    if p_reset then
      -- أسماء المشاريع بالتطبيق تُحفظ قبل المسح: الرفع من شاشة المبيعات لا يعرفها (لا كتالوج هناك)
      insert into tv_project_app (project_name, app_name)
      select distinct on (project_name) project_name, app_name from tv_unit_status where app_name is not null order by project_name
      on conflict (project_name) do update set app_name = excluded.app_name;
      delete from tv_unit_status where true;
    end if;
    insert into tv_unit_status (project_name, project_code, app_name, developer, city, dest, sector, kind, status, cnt)
    select btrim(r->>'project_name'), coalesce(btrim(r->>'project_code'), ''), max(nullif(btrim(r->>'app_name'), '')),
           max(nullif(btrim(r->>'developer'), '')), max(nullif(btrim(r->>'city'), '')),
           coalesce(btrim(r->>'dest'), ''), coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'),
           coalesce(btrim(r->>'status'), ''), sum((r->>'cnt')::int)
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'project_name'), '') is not null
    group by 1, 2, 6, 7, 8, 9
    on conflict (project_name, project_code, dest, sector, kind, status) do update set cnt = tv_unit_status.cnt + excluded.cnt, updated_at = now();
    get diagnostics v_count = row_count;
    insert into tv_project_app (project_name, app_name)
    select distinct on (btrim(r->>'project_name')) btrim(r->>'project_name'), btrim(r->>'app_name')
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'project_name'), '') is not null and nullif(btrim(r->>'app_name'), '') is not null
    order by btrim(r->>'project_name')
    on conflict (project_name) do update set app_name = excluded.app_name;
    update tv_unit_status u set app_name = pa.app_name
    from tv_project_app pa where u.app_name is null and pa.project_name = u.project_name;
    return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
  else
    return jsonb_build_object('ok', false, 'msg', 'جدول غير معروف');
  end if;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- ---------- حزمة عقود الشاشة: نفس get_tv_contracts + قيمة العقود الممولة والنقدية لكل شهر ويوم ----------
create or replace function get_tv_contracts(p_year int, p_month int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with has as (select exists(select 1 from tv_contract_daily) as f),
  m as (
    select tv_region(nullif(d.sector, ''), null) as sec, d.kind, d.contract_date, d.cnt, d.fin_sum, d.cash_sum, d.fin_n, d.cash_n,
           coalesce(nullif(d.sector, ''), '(فارغ)') as raw
    from tv_contract_daily d, has
    where has.f and d.contract_date >= make_date(p_year, 1, 1) and d.contract_date < make_date(p_year + 1, 1, 1)
    union all
    select tv_region(u.file_sector, u.sector), coalesce(u.file_dev_kind, u.dev_kind, 'other'), u.contract_date, 1, 0, 0, 0, 0,
           u.file_sector
    from unit_allocation_mirror u, has
    where not has.f and u.contract_date >= make_date(p_year, 1, 1) and u.contract_date < make_date(p_year + 1, 1, 1)
  )
  select jsonb_build_object(
    'ok', true,
    'source', case when (select f from has) then 'file' else 'mirror' end,
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('m', mo, 'sector', sec, 'kind', kind, 'cnt', c, 'fin', fs, 'cash', cs))
      from (select extract(month from contract_date)::int as mo, sec, kind, sum(cnt) as c, sum(fin_sum) as fs, sum(cash_sum) as cs
            from m group by 1, 2, 3) x
    ), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'sector', sec, 'kind', kind, 'cnt', c, 'fin', fs, 'cash', cs))
      from (select extract(day from contract_date)::int as d, sec, kind, sum(cnt) as c, sum(fin_sum) as fs, sum(cash_sum) as cs from m
            where extract(month from contract_date)::int = p_month group by 1, 2, 3) y
    ), '[]'::jsonb),
    -- عقود السنة المصنّفة (ممول/نقدي): صفر = الملف المرفوع بلا عمود البنك أو قبل تشغيل هذا الملف
    'rev_classified', (select coalesce(sum(fin_n + cash_n), 0) from m),
    'file_sector_rows', (select count(*) from unit_allocation_mirror where file_sector is not null),
    'rows', (select count(*) from unit_allocation_mirror),
    'unmapped', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'cnt', c) order by c desc)
      from (select raw as v, sum(cnt) as c from m
            where raw is not null and tv_norm_sector(nullif(raw, '(فارغ)')) is null
            group by 1 order by 2 desc limit 8) u
    ), '[]'::jsonb)
  );
$$;

-- ---------- المشاريع التي باعت خلال فترة: + قيمة العقود الممولة والنقدية ----------
create or replace function get_tv_period_projects(p_from date, p_to date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with c as (
    select project_name, kind, sum(cnt) as cnt, sum(fin_sum) as fin, sum(cash_sum) as cash,
           mode() within group (order by tv_region(nullif(sector, ''), null)) as sec,
           mode() within group (order by dest) as dest
    from tv_contract_daily
    where contract_date between p_from and p_to and project_name <> ''
    group by 1, 2
  ),
  info as (
    select project_name, max(developer) as developer, max(city) as city
    from tv_unit_status group by 1
  )
  select jsonb_build_object(
    'ok', true,
    'from', p_from, 'to', p_to,
    'as_of', (select max(updated_at) from tv_contract_daily),
    'last_date', (select max(contract_date) from tv_contract_daily),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'project', c.project_name, 'is_nhc', c.kind = 'nhc', 'developer', i.developer, 'city', i.city,
        'sector', c.sec, 'dest', nullif(c.dest, ''), 'cnt', c.cnt, 'fin', c.fin, 'cash', c.cash
      ) order by c.cnt desc, c.project_name)
      from c left join info i using (project_name)
    ), '[]'::jsonb)
  );
$$;

-- ---------- المستهدفات: نفس get_dashboard_targets + مستهدف الإيراد لكل نطاق وقطاع ----------
create or replace function get_dashboard_targets(p_year int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with s as (
    select scope, coalesce(sector,'غير محدد') as sector, sum(units) as u, sum(revenue) as rv, max(source) as src
    from dashboard_targets where year = p_year
    group by scope, coalesce(sector,'غير محدد')
  ),
  sc as (
    select scope, sum(u) as total, max(src) as source, jsonb_object_agg(sector, u) as by_sector,
           sum(rv) as rev_total, jsonb_object_agg(sector, rv) filter (where rv is not null) as rev_by_sector
    from s group by scope
  ),
  pc as (
    select scope, count(distinct project_name) as projects,
           -- مشاريع لها مستهدف وحدات بلا مستهدف إيراد (لا تدخل مستهدف الإيراد)
           coalesce(sum(units) filter (where revenue is null), 0) as rev_missing_units,
           count(distinct project_name) filter (where revenue is null and units > 0) as rev_missing_projects
    from dashboard_targets where year = p_year group by scope
  )
  select jsonb_build_object(
    'ok', true, 'year', p_year,
    'scopes', coalesce((
      select jsonb_object_agg(sc.scope, jsonb_build_object(
        'total', sc.total, 'projects', pc.projects, 'source', sc.source, 'by_sector', sc.by_sector,
        'rev_total', sc.rev_total, 'rev_by_sector', coalesce(sc.rev_by_sector, '{}'::jsonb),
        'rev_missing_units', pc.rev_missing_units, 'rev_missing_projects', pc.rev_missing_projects))
      from sc join pc using (scope)
    ), '{}'::jsonb)
  );
$$;

-- ---------- الإيراد المستحق والإنجاز المالي (منهجية الجدول) ----------
create or replace function get_tv_revenue(p_year int, p_month int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with params as (select * from tv_rev_params where not is_region),
  apps as (
    select project_name, max(app_name) as app from (
      select project_name, app_name from tv_project_app
      union all select project_name, app_name from tv_unit_status where app_name is not null
    ) x group by 1
  ),
  names0 as (
    select v.project_name, min(v.first_date) as first_date, sum(v.fin_sum + v.cash_sum) as value
    from tv_project_value v where v.kind = 'nhc' group by 1
    union all
    select distinct d.project_name, null::date, 0 from tv_contract_daily d
    where d.kind = 'nhc' and d.project_name <> '' and not exists (select 1 from tv_project_value v where v.project_name = d.project_name)
  ),
  names as (
    select n.project_name, a.app, n.first_date, n.value, tv_rev_key(n.project_name) as k1, tv_rev_key(a.app) as k2
    from names0 n left join apps a using (project_name)
  ),
  pk as (select p.*, tv_rev_key(p.name) as k from params p),
  -- لكل مشروع بملف التخصيص: صفّه بجدول الإيرادات — الاسم أو اسم التطبيق: مطابق، ثم بلا مسافات/شرطات/NHC،
  -- ثم أحدهما يحوي الآخر (الأطول أولاً)
  cand as (
    select n.project_name, p.name, p.excluded, p.cash_pct,
           case when p.norm in (tv_norm_name(n.project_name), tv_norm_name(n.app)) then 0
                when p.k in (n.k1, n.k2) then 1 else 2 end as rk, length(p.k) as kl
    from names n join pk p on p.k is not null and (
      p.norm in (tv_norm_name(n.project_name), tv_norm_name(n.app)) or p.k in (n.k1, n.k2)
      or (length(p.k) >= 4 and ((n.k1 is not null and length(n.k1) >= 4 and (strpos(n.k1, p.k) > 0 or strpos(p.k, n.k1) > 0))
                             or (n.k2 is not null and length(n.k2) >= 4 and (strpos(n.k2, p.k) > 0 or strpos(p.k, n.k2) > 0)))))
  ),
  best as (
    select distinct on (project_name) project_name, name, excluded, cash_pct from cand
    order by project_name, rk, kl desc, excluded desc
  ),
  pas as (select max(as_of) as d from tv_rev_params),
  -- المستبعد: مستبعد بالجدول، أو دانية، أو غير مطابق للجدول وله عقود قبل تاريخه (مشروع قديم اسمه مختلف —
  -- الجدول يشمل كل المشاريع العاملة حتى تاريخه). غير المطابق الجديد (أول عقد بعد تاريخ الجدول) يُحسب بمتوسط قطاعه
  -- الدانيات داخل النطاق دائماً (حتى لو «مستبعدة» بجدول الإيرادات)؛ نسبتها النقدية صفر — لا دفعة مقدمة نقدية
  -- لها بجدول الإيرادات (إيرادها من التمويل البنكي فقط)
  pm0 as (
    select n.*, b.name as pname, b.excluded as b_excl, b.cash_pct as b_pct,
           (tv_norm_name(n.project_name) like '%دانيه%' or coalesce(tv_norm_name(n.app), '') like '%دانيه%'
            or coalesce(tv_norm_name(b.name), '') like '%دانيه%') as danyat
    from names n left join best b using (project_name)
  ),
  pm as (
    select project_name, app, value, pname, danyat,
           coalesce(b_pct, case when danyat then 0 end) as cash_pct,
           ((coalesce(b_excl, false) and not danyat)
            or (pname is null and not danyat and (select d from pas) is not null and first_date is not null and first_date <= (select d from pas))) as excl,
           (pname is null) as unmatched
    from pm0
  ),
  -- متوسط نسبة الدفعة النقدية لكل قطاع (بالأوزان) للمشاريع غير الموجودة بالجدول
  secdef as (
    select sector, sum(cash_due) / nullif(sum(cum_value - coalesce(bank_due, 0) / 0.2), 0) as pct
    from params where not excluded and cash_pct is not null group by sector
  ),
  alldef as (
    select sum(cash_due) / nullif(sum(cum_value - coalesce(bank_due, 0) / 0.2), 0) as pct
    from params where not excluded and cash_pct is not null
  ),
  v as (
    select tv_region(nullif(v.sector, ''), null) as sec, v.project_name, v.cnt, v.fin_sum, v.cash_sum,
           coalesce(pm.cash_pct, sd.pct, (select pct from alldef), 0.10) as cpct, pm.pname
    from tv_project_value v join pm using (project_name)
    left join secdef sd on sd.sector = tv_region(nullif(v.sector, ''), null)
    where v.kind = 'nhc' and not pm.excl
  ),
  ach as (
    select coalesce(sec, 'غير محدد') as sec, sum(cnt) as cnt, sum(fin_sum + cash_sum) as value,
           sum(cash_sum * cpct) as cash_due, sum(fin_sum * 0.2) as bank_due
    from v group by 1
  ),
  -- المستهدف التراكمي: من آخر جدول إيرادات مرفوع (صفوف المناطق) إن وُجد، وإلا من dashboard_targets
  tgt_tbl as (
    select sector as sec, sum(target_cum) as target_cum from tv_rev_params
    where is_region and target_cum is not null group by 1
  ),
  tgt_db as (
    select coalesce(tv_region(sector, null), 'غير محدد') as sec,
           sum(revenue) filter (where year <= p_year) as target_cum, sum(revenue) filter (where year = p_year) as target_year
    from dashboard_targets where scope = 'nhc' group by 1
  ),
  -- مستهدف الدانيات (الجدول يستبعدها من مستهدفه) — يُضاف لمستهدف الجدول
  tgt_dan as (
    select coalesce(tv_region(sector, null), 'غير محدد') as sec, sum(revenue) filter (where year <= p_year) as target_cum
    from dashboard_targets where scope = 'nhc' and tv_norm_name(project_name) like '%دانيه%' group by 1
  ),
  tg as (
    select coalesce(b.sec, t.sec) as sec,
           case when exists(select 1 from tgt_tbl) then coalesce(t.target_cum, 0) + coalesce(dn.target_cum, 0) else b.target_cum end as target_cum,
           b.target_year
    from tgt_db b full join tgt_tbl t using (sec) left join tgt_dan dn on dn.sec = coalesce(b.sec, t.sec)
  ),
  secs as (select sec from ach union select sec from tg),
  d as (
    select tv_region(nullif(d.sector, ''), null) as sec, d.contract_date,
           d.fin_sum * 0.2 + d.cash_sum * coalesce(pm.cash_pct, sd.pct, (select pct from alldef), 0.10) as due
    from tv_contract_daily d join pm using (project_name)
    left join secdef sd on sd.sector = tv_region(nullif(d.sector, ''), null)
    where d.kind = 'nhc' and not pm.excl
      and d.contract_date >= make_date(p_year, 1, 1) and d.contract_date < make_date(p_year + 1, 1, 1)
  )
  select jsonb_build_object(
    'ok', true,
    'has_params', exists(select 1 from params),
    'has_value', exists(select 1 from tv_project_value),
    'target_src', case when exists(select 1 from tv_rev_params where is_region and target_cum is not null) then 'table' else 'targets' end,
    'params_as_of', (select max(as_of) from tv_rev_params),
    'value_as_of', (select max(updated_at) from tv_project_value),
    'sectors', coalesce((
      select jsonb_object_agg(s.sec, jsonb_build_object(
        'cnt', coalesce(a.cnt, 0), 'value', coalesce(a.value, 0), 'cash_due', coalesce(a.cash_due, 0), 'bank_due', coalesce(a.bank_due, 0),
        'due', coalesce(a.cash_due, 0) + coalesce(a.bank_due, 0), 'target_cum', t.target_cum, 'target_year', t.target_year))
      from secs s left join ach a using (sec) left join tg t using (sec)
    ), '{}'::jsonb),
    -- لقطة أرقام الجدول المرفوع (صفوف المناطق) للتحقق
    'table', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'sector', sector, 'cum_value', cum_value,
        'cash_due', cash_due, 'bank_due', bank_due, 'target_cum', target_cum)) from tv_rev_params where is_region), '[]'::jsonb),
    -- نسبة الدفعة النقدية المطبّقة لكل مشروع NHC (لعمود الإيراد بجدول المشاريع) — null = مستبعد
    'pct', coalesce((
      select jsonb_object_agg(pm.project_name, case when pm.excl then null
             else coalesce(pm.cash_pct, (select pct from alldef), 0.10) end) from pm
    ), '{}'::jsonb),
    'sec_pct', coalesce((select jsonb_object_agg(sector, pct) from secdef where sector is not null), '{}'::jsonb),
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('m', mo, 'sector', sec, 'due', due))
      from (select extract(month from contract_date)::int as mo, sec, sum(due) as due from d group by 1, 2) x
    ), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('d', dd, 'sector', sec, 'due', due))
      from (select extract(day from contract_date)::int as dd, sec, sum(due) as due from d
            where extract(month from contract_date)::int = p_month group by 1, 2) y
    ), '[]'::jsonb),
    'unmatched', coalesce((
      select jsonb_agg(p.name order by p.name) from params p
      where not p.excluded and not exists (select 1 from pm where pm.pname = p.name)
    ), '[]'::jsonb),
    -- مشاريع NHC بملف التخصيص لم تُطابق الجدول: القديمة خارج الحساب، والجديدة بمتوسط قطاعها
    'dropped', coalesce((select jsonb_agg(jsonb_build_object('project', project_name, 'value', value) order by value desc)
      from pm where unmatched and excl and value > 0), '[]'::jsonb),
    'new_projects', coalesce((select jsonb_agg(project_name order by project_name) from pm where unmatched and not excl), '[]'::jsonb)
  );
$$;
