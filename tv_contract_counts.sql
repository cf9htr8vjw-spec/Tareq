-- ============================================================
-- SalesPlace — شاشة الداشبورد: عدّ العقود من ملف التخصيص كاملاً (حالة الحجز = عقد + السنة)
-- ============================================================
-- المشكلة: الشاشة كانت تعدّ من مرآة التخصيص، ورفع الملف يستبعد صفوفاً قبل حفظها (سعر أقل من
-- 10,000، حالات خارج الأربع المعتمدة) — فالعقود أقل قليلاً من فلترة الملف بالإكسل.
-- الحل (لشاشة الداشبورد فقط): جدول صغير بعدد العقود لكل يوم × قطاع × NHC/مطور، يُحسب من الملف
-- كاملاً عند كل رفع. بقية شاشات التطبيق لا تتغيّر.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor، ثم ارفع ملف التخصيص من جديد من التطبيق.
-- آمن لإعادة التشغيل.
-- ============================================================

-- ---------- القطاع الموحّد للشاشة ----------
-- قطاع ملف التخصيص بأي تهجئة (الأوسط/الاوسط/الوسطى/قطاع الأوسط/Central...) يُوحَّد لأحد القطاعات
-- الثلاثة؛ قيمة لا تُعرف بالملف (فارغة أو اسم آخر) → قطاع التطبيق لنفس الوحدة → وإلا "غير محدد".
create or replace function tv_norm_sector(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null then null
    when p like '%وسط%' or lower(p) like '%central%' then 'الأوسط'
    when p like '%غرب%' or lower(p) like '%west%' then 'الغربي'
    when p like '%شرق%' or lower(p) like '%east%' then 'الشرقي'
    else null end
$$;
create or replace function tv_region(p_file text, p_app text)
returns text
language sql
immutable
as $$
  select coalesce(tv_norm_sector(p_file), tv_norm_sector(p_app), 'غير محدد')
$$;

-- ---------- tv_contract_daily ----------
-- عدد العقود لكل يوم × قطاع الملف × (NHC/مطور) — يُحسب بالمتصفح من ملف التخصيص كاملاً عند كل رفع
-- (حالة الحجز = عقد، تاريخ توقيع العقد) ويُستبدل بالكامل. لشاشة الداشبورد فقط — بقية التطبيق كما هو.
create table if not exists tv_contract_daily (
  contract_date date not null,
  sector text not null default '',     -- عمود "القطاع" كما بالملف (يُوحَّد عند القراءة بـ tv_region)
  kind text not null,                  -- nhc / other (developer_name = NHC)
  cnt integer not null,
  updated_at timestamptz not null default now(),
  primary key (contract_date, sector, kind)
);
alter table tv_contract_daily enable row level security;
drop policy if exists tv_contract_daily_read on tv_contract_daily;
create policy tv_contract_daily_read on tv_contract_daily for select using (true);

-- استبدال كامل مع كل رفع لملف التخصيص — يتطلّب صلاحية أدمن فعلية
create or replace function admin_replace_tv_contract_daily(p_admin text, p_pass text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_count int;
  v_total bigint;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  delete from tv_contract_daily where true;
  insert into tv_contract_daily (contract_date, sector, kind, cnt)
  select (r->>'contract_date')::date, coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'), sum((r->>'cnt')::int)
  from jsonb_array_elements(p_rows) r
  where nullif(r->>'contract_date', '') is not null
  group by 1, 2, 3;

  get diagnostics v_count = row_count;
  select coalesce(sum(cnt), 0) into v_total from tv_contract_daily;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً ('||v_total||' عقداً)', 'count', v_count, 'total', v_total);
end;
$$;

-- ---------- get_tv_contracts ----------
-- العقود الموقّعة خلال السنة لكل شهر × قطاع × (NHC/مطور)، ولكل يوم من الشهر المطلوب — الشاشة تجمع
-- منها المملكة والمناطق والمنحنيات. المصدر: tv_contract_daily (عدّ ملف التخصيص كاملاً: حالة الحجز =
-- عقد، بتاريخ توقيع العقد وقطاع الملف ومطوّره، بلا أي استبعاد — يطابق فلترة الملف بالإكسل). إن كان
-- الجدول فارغاً (قبل أول رفع بعد تشغيل tv_contract_counts.sql): مرآة التخصيص كما سابقاً.
create or replace function get_tv_contracts(p_year int, p_month int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with has as (select exists(select 1 from tv_contract_daily) as f),
  m as (
    select tv_region(nullif(d.sector, ''), null) as sec, d.kind, d.contract_date, d.cnt,
           coalesce(nullif(d.sector, ''), '(فارغ)') as raw
    from tv_contract_daily d, has
    where has.f and d.contract_date >= make_date(p_year, 1, 1) and d.contract_date < make_date(p_year + 1, 1, 1)
    union all
    select tv_region(u.file_sector, u.sector), coalesce(u.file_dev_kind, u.dev_kind, 'other'), u.contract_date, 1,
           u.file_sector
    from unit_allocation_mirror u, has
    where not has.f and u.contract_date >= make_date(p_year, 1, 1) and u.contract_date < make_date(p_year + 1, 1, 1)
  )
  select jsonb_build_object(
    'ok', true,
    'source', case when (select f from has) then 'file' else 'mirror' end,
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('m', mo, 'sector', sec, 'kind', kind, 'cnt', c))
      from (select extract(month from contract_date)::int as mo, sec, kind, sum(cnt) as c from m group by 1, 2, 3) x
    ), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'sector', sec, 'kind', kind, 'cnt', c))
      from (select extract(day from contract_date)::int as d, sec, kind, sum(cnt) as c from m
            where extract(month from contract_date)::int = p_month group by 1, 2, 3) y
    ), '[]'::jsonb),
    'file_sector_rows', (select count(*) from unit_allocation_mirror where file_sector is not null),
    'rows', (select count(*) from unit_allocation_mirror),
    -- قيم عمود القطاع بالملف التي لم تُعرف (عقود السنة) — تظهر بأسفل الشاشة للتشخيص
    'unmapped', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'cnt', c) order by c desc)
      from (select raw as v, sum(cnt) as c from m
            where raw is not null and tv_norm_sector(nullif(raw, '(فارغ)')) is null
            group by 1 order by 2 desc limit 8) u
    ), '[]'::jsonb)
  );
$$;
