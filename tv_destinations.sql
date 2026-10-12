-- ============================================================
-- SalesPlace — شاشة الداشبورد: الوجهات، المتاح (منصة/مطور)، وعقود المشاريع لأي فترة
-- ============================================================
-- كلها من ملف التخصيص كاملاً كما هو (بلا استبعاد)، تُحسب بالمتصفح عند كل رفع للملف:
--  • tv_contract_daily: عدد العقود (حالة الحجز = عقد) لكل يوم × مشروع × قطاع × وجهة (الضاحية) × NHC/مطور
--  • tv_unit_status:   عدد الوحدات لكل مشروع × حالة الحجز (متاحة على المنصة / متاحة لدى المطور / حجز / عقد...)
-- لشاشة الداشبورد فقط — بقية شاشات التطبيق لا تتغيّر.
--
-- يتطلّب: tv_contract_counts.sql (أو tv_file_counts_v2.sql) مُشغَّلاً قبله.
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor، ثم ارفع ملف التخصيص من جديد من التطبيق.
-- آمن لإعادة التشغيل.
-- ============================================================

-- ---------- توحيد أسماء المشاريع للمطابقة (نفس قاعدة normName بالتطبيق) ----------
create or replace function tv_norm_name(p text)
returns text
language sql
immutable
as $$
  select nullif(btrim(regexp_replace(translate(lower(coalesce(p, '')), 'أإآىةـ-ّ', 'ااايه  '), '\s+', ' ', 'g')), '')
$$;

-- ---------- tv_contract_daily: + المشروع والوجهة ----------
alter table tv_contract_daily add column if not exists project_name text not null default '';
alter table tv_contract_daily add column if not exists dest text not null default '';
-- نوع الوحدة وسعرها (لعقود حسب المنتج ومتوسط سعر المباع — tv_products.sql)
alter table tv_contract_daily add column if not exists unit_type text not null default '';
alter table tv_contract_daily add column if not exists price_sum numeric not null default 0;  -- مجموع سعر العقود ذات السعر الصحيح
alter table tv_contract_daily add column if not exists price_n integer not null default 0;    -- عددها
alter table tv_contract_daily drop constraint if exists tv_contract_daily_pkey;
alter table tv_contract_daily add constraint tv_contract_daily_pkey primary key (contract_date, project_name, sector, dest, kind, unit_type);

-- ---------- tv_unit_status ----------
create table if not exists tv_unit_status (
  project_name text not null,              -- كما بالملف
  project_code text not null default '',
  app_name text,                           -- اسم المشروع بالتطبيق إن كان مسجّلاً (لمطابقة خطة المطورين)
  developer text,
  city text,
  dest text not null default '',           -- الضاحية (الوجهة)
  sector text not null default '',         -- القطاع كما بالملف
  kind text not null,                      -- nhc / other
  status text not null,                    -- حالة الحجز كما بالملف
  cnt integer not null,
  updated_at timestamptz not null default now(),
  primary key (project_name, project_code, dest, sector, kind, status)
);
alter table tv_unit_status enable row level security;
drop policy if exists tv_unit_status_read on tv_unit_status;
create policy tv_unit_status_read on tv_unit_status for select using (true);

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
    insert into tv_contract_daily (contract_date, project_name, sector, dest, kind, unit_type, cnt, price_sum, price_n)
    select (r->>'contract_date')::date, coalesce(btrim(r->>'project_name'), ''), coalesce(btrim(r->>'sector'), ''),
           coalesce(btrim(r->>'dest'), ''), coalesce(r->>'kind', 'other'), coalesce(btrim(r->>'unit_type'), ''),
           sum((r->>'cnt')::int), sum(coalesce(nullif(r->>'price_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'price_n', '')::int, 0))
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'contract_date', '') is not null
    group by 1, 2, 3, 4, 5, 6
    on conflict (contract_date, project_name, sector, dest, kind, unit_type) do update set
      cnt = tv_contract_daily.cnt + excluded.cnt, price_sum = tv_contract_daily.price_sum + excluded.price_sum,
      price_n = tv_contract_daily.price_n + excluded.price_n, updated_at = now();
  elsif p_table = 'status' then
    if p_reset then delete from tv_unit_status where true; end if;
    insert into tv_unit_status (project_name, project_code, app_name, developer, city, dest, sector, kind, status, cnt)
    select btrim(r->>'project_name'), coalesce(btrim(r->>'project_code'), ''), max(nullif(btrim(r->>'app_name'), '')),
           max(nullif(btrim(r->>'developer'), '')), max(nullif(btrim(r->>'city'), '')),
           coalesce(btrim(r->>'dest'), ''), coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'),
           coalesce(btrim(r->>'status'), ''), sum((r->>'cnt')::int)
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'project_name'), '') is not null
    group by 1, 2, 6, 7, 8, 9
    on conflict (project_name, project_code, dest, sector, kind, status) do update set cnt = tv_unit_status.cnt + excluded.cnt, updated_at = now();
  else
    return jsonb_build_object('ok', false, 'msg', 'جدول غير معروف');
  end if;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- ---------- get_tv_period_projects ----------
-- عقود كل مشروع بين تاريخين (أمس / الأسبوع / الشهر) من ملف التخصيص، الأعلى أولاً.
create or replace function get_tv_period_projects(p_from date, p_to date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with c as (
    select project_name, kind, sum(cnt) as cnt,
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
        'sector', c.sec, 'dest', nullif(c.dest, ''), 'cnt', c.cnt
      ) order by c.cnt desc, c.project_name)
      from c left join info i using (project_name)
    ), '[]'::jsonb)
  );
$$;

-- ---------- get_tv_destinations ----------
-- لكل وجهة (الضاحية): عقود السنة حتى آخر رفع للتخصيص (NHC / المطورون) مقابل المستهدف السنوي بنفس منهجية
-- عدّادات القطاعات — NHC: مذكرات الاستثمار، المطورون: خطة المبيعات (dashboard_targets) — والمتاح على
-- المنصة / لدى المطور. ربط مشروع المستهدف بوجهته: رمز المشروع، وإلا الاسم (بالملف أو بالتطبيق أو بالعرض).
create or replace function get_tv_destinations(p_year int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with
  ach as (
    select dest, coalesce(sum(cnt) filter (where kind = 'nhc'), 0) as nhc, coalesce(sum(cnt) filter (where kind <> 'nhc'), 0) as dev
    from tv_contract_daily
    where dest <> '' and contract_date >= make_date(p_year, 1, 1) and contract_date < make_date(p_year + 1, 1, 1)
    group by 1
  ),
  av as (
    select dest,
           coalesce(sum(cnt) filter (where status = 'متاحة على المنصة'), 0) as plat,
           coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور'), 0) as devav,
           mode() within group (order by tv_region(nullif(sector, ''), null)) as sec
    from tv_unit_status where dest <> '' group by 1
  ),
  pmap as (
    select distinct on (key) key, dest from (
      select project_code as key, dest, sum(cnt) as n from tv_unit_status where project_code <> '' group by 1, 2
      union all
      select 'n:' || tv_norm_name(project_name), dest, sum(cnt) from tv_unit_status group by 1, 2
      union all
      select 'n:' || tv_norm_name(app_name), dest, sum(cnt) from tv_unit_status where app_name is not null group by 1, 2
    ) z
    where key is not null
    order by key, n desc
  ),
  tg as (
    select t.scope, t.units, coalesce(
      (select pm.dest from regexp_split_to_table(coalesce(t.project_code, ''), '\s*\+\s*') as code(c)
         join pmap pm on pm.key = btrim(code.c) where btrim(code.c) <> '' limit 1),
      (select pm.dest from pmap pm where pm.key = 'n:' || tv_norm_name(t.project_name)),
      (select pm.dest from pmap pm where pm.key = 'n:' || tv_norm_name(t.slide_name))
    ) as dest
    from dashboard_targets t
    where t.year = p_year
  ),
  tgd as (
    select dest, coalesce(sum(units) filter (where scope = 'nhc'), 0) as nhc_t, coalesce(sum(units) filter (where scope = 'dev'), 0) as dev_t
    from tg where coalesce(dest, '') <> '' group by 1
  ),
  alld as (select dest from ach union select dest from tgd union select dest from av)
  select jsonb_build_object(
    'ok', true,
    'as_of', (select max(updated_at) from tv_contract_daily),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dest', d.dest, 'sector', coalesce(av.sec, 'غير محدد'),
        'nhc', coalesce(ach.nhc, 0), 'dev', coalesce(ach.dev, 0),
        'nhc_target', coalesce(tgd.nhc_t, 0), 'dev_target', coalesce(tgd.dev_t, 0),
        'avail_platform', coalesce(av.plat, 0), 'avail_developer', coalesce(av.devav, 0)
      ) order by coalesce(tgd.nhc_t, 0) + coalesce(tgd.dev_t, 0) desc, coalesce(ach.nhc, 0) + coalesce(ach.dev, 0) desc)
      from alld d left join ach using (dest) left join tgd using (dest) left join av using (dest)
    ), '[]'::jsonb),
    -- مستهدف لم يُربط بأي وجهة (مشروع خارج الوجهات أو لم يُطابَق) — للتشخيص
    'targets_outside', (select jsonb_build_object(
        'nhc', coalesce(sum(units) filter (where scope = 'nhc' and coalesce(dest, '') = ''), 0),
        'dev', coalesce(sum(units) filter (where scope = 'dev' and coalesce(dest, '') = ''), 0)) from tg),
    -- تشخيص: هل وصلت بيانات رفع ملف التخصيص لهذين الجدولين؟ (تظهر رسالة واضحة بالشاشة إن لم تصل)
    'diag', jsonb_build_object(
      'status_rows', (select count(*) from tv_unit_status),
      'status_dest_rows', (select count(*) from tv_unit_status where dest <> ''),
      'status_updated', (select max(updated_at) from tv_unit_status),
      'contract_rows', (select count(*) from tv_contract_daily),
      'contract_project_rows', (select count(*) from tv_contract_daily where project_name <> '')),
    -- المتاح على مستوى المملكة و NHC / المطورين
    'avail', (select jsonb_build_object(
        'platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة'), 0),
        'developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور'), 0),
        'nhc_platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة' and kind = 'nhc'), 0),
        'nhc_developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور' and kind = 'nhc'), 0),
        'dev_platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة' and kind <> 'nhc'), 0),
        'dev_developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور' and kind <> 'nhc'), 0))
      from tv_unit_status)
  );
$$;
