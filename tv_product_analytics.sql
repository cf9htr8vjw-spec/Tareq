-- ============================================================
-- SalesPlace — شاشة المبيعات: تحليل المنتجات والنماذج + أداء الموظف الشهري
-- ============================================================
-- من ملف التخصيص (يُحمَّل مع كل رفع، من التطبيق أو من الشاشة): لكل مشروع × نموذج × نوع الوحدة × عدد الغرف:
--   الحالات (متاح منصة / متاح لدى المطور / حجز / عقد / غيرها)، عقود آخر 30 و90 يوماً وكل شهر من السنة،
--   حجوزات آخر 30 يوماً، متوسط السعر (المتاح والمباع) وسعر الوزارة، المساحة (متوسط/أدنى/أعلى) وسعر المتر.
-- الشاشة تحسب منه: نسبة السحب = المسحوب ÷ المطروح، الحركة الشهرية، أشهر تصريف المتاح، وتقارن النموذج بضاحيته.
--
-- يتطلّب: tv_file_counts.sql (tv_region) و tv_sales_force.sql (tv_employee_daily). آمن لإعادة التشغيل.
-- بعد تشغيله: ارفع ملف التخصيص مرة (من التطبيق أو من الشاشة) لتعبئة الجدول.
-- ============================================================

create table if not exists tv_product_stats (
  project_name text not null,
  project_code text not null default '',
  model text not null default '',          -- فارغ = الملف بلا عمود model لهذه الوحدات
  unit_type text not null default '',
  beds integer not null default -1,        -- -1 = غير مذكور
  developer text not null default '',
  kind text not null default 'other',      -- nhc / other
  sector text not null default '',
  city text not null default '',
  dest text not null default '',           -- الضاحية
  avail_p integer not null default 0,      -- متاحة على المنصة
  avail_d integer not null default 0,      -- متاحة لدى المطور
  reserved integer not null default 0,     -- حجز
  contracts integer not null default 0,    -- عقد (منذ بداية المشروع)
  other integer not null default 0,        -- حالات أخرى (محجوب/تنموي...) — خارج المطروح
  c30 integer not null default 0,          -- عقود آخر 30 يوماً
  c90 integer not null default 0,          -- عقود آخر 90 يوماً
  cy integer not null default 0,           -- عقود السنة الحالية
  b30 integer not null default 0,          -- حجوزات آخر 30 يوماً (بتاريخ الحجز)
  months integer[] not null default '{0,0,0,0,0,0,0,0,0,0,0,0}',  -- عقود كل شهر من السنة الحالية
  pa_sum numeric not null default 0, pa_n integer not null default 0,   -- سعر المتاح (price)
  ps_sum numeric not null default 0, ps_n integer not null default 0,   -- سعر المباع (سعر العقد وإلا السعر المطبَّق)
  moh_sum numeric not null default 0, moh_n integer not null default 0, -- سعر الوزارة للمتاح (moh_price)
  sz_sum numeric not null default 0, sz_n integer not null default 0, sz_min numeric, sz_max numeric,
  sqa_p numeric not null default 0, sqa_s numeric not null default 0,  -- للمتاح: مجموع السعر ومجموع المساحة (للوحدات ذات الاثنين)
  sqs_p numeric not null default 0, sqs_s numeric not null default 0,  -- للمباع
  updated_at timestamptz not null default now(),
  primary key (project_name, project_code, model, unit_type, beds)
);
alter table tv_product_stats enable row level security;
alter table tv_product_stats add column if not exists launch date;   -- «تاريخ بدء البيع للمشروع» من ملف التخصيص
-- خريطة الطلب والمعروض: المتاح لكل شريحة (target_segments) وعقود المستفيدين (نوع المستفيدين) — غير المستفيدين = الإجمالي − المستفيدين
alter table tv_product_stats add column if not exists avail_b integer not null default 0;   -- متاح معروض للمستفيدين
alter table tv_product_stats add column if not exists avail_n integer not null default 0;   -- متاح معروض لغير المستفيدين/الشركات
alter table tv_product_stats add column if not exists c30b integer not null default 0;      -- عقود المستفيدين آخر 30 يوماً
alter table tv_product_stats add column if not exists c90b integer not null default 0;      -- آخر 90 يوماً
alter table tv_product_stats add column if not exists cyb integer not null default 0;       -- السنة الحالية
drop policy if exists tv_product_stats_read on tv_product_stats;
create policy tv_product_stats_read on tv_product_stats for select using (true);

-- تاريخ آمن: نص غير صالح (30 فبراير، شهر 13...) ⇒ null بدل أن يُفشل دفعة الرفع كلها
create or replace function tv_safe_date(p text)
returns date
language plpgsql
immutable
as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  return p::date;
exception when others then
  return null;
end;
$$;

-- رفع على دفعات (الأولى تمسح القديم) — يتطلّب صلاحية أدمن فعلية
create or replace function admin_load_tv_products(p_admin text, p_pass text, p_rows jsonb, p_reset boolean)
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
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true)
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;
  if p_reset then delete from tv_product_stats where true; end if;
  insert into tv_product_stats (project_name, project_code, model, unit_type, beds, developer, kind, sector, city, dest,
    avail_p, avail_d, reserved, contracts, other, c30, c90, cy, b30, months,
    pa_sum, pa_n, ps_sum, ps_n, moh_sum, moh_n, sz_sum, sz_n, sz_min, sz_max, sqa_p, sqa_s, sqs_p, sqs_s, launch,
    avail_b, avail_n, c30b, c90b, cyb)
  select btrim(r->>'project_name'), coalesce(btrim(r->>'project_code'), ''), coalesce(btrim(r->>'model'), ''),
         coalesce(btrim(r->>'unit_type'), ''), coalesce(nullif(r->>'beds', '')::int, -1),
         coalesce(btrim(r->>'developer'), ''), coalesce(r->>'kind', 'other'), coalesce(btrim(r->>'sector'), ''),
         coalesce(btrim(r->>'city'), ''), coalesce(btrim(r->>'dest'), ''),
         coalesce((r->>'avail_p')::int, 0), coalesce((r->>'avail_d')::int, 0), coalesce((r->>'reserved')::int, 0),
         coalesce((r->>'contracts')::int, 0), coalesce((r->>'other')::int, 0),
         coalesce((r->>'c30')::int, 0), coalesce((r->>'c90')::int, 0), coalesce((r->>'cy')::int, 0), coalesce((r->>'b30')::int, 0),
         coalesce((select array_agg(coalesce(x::int, 0) order by o) from jsonb_array_elements_text(r->'months') with ordinality t(x, o)),
                  '{0,0,0,0,0,0,0,0,0,0,0,0}'),
         coalesce((r->>'pa_sum')::numeric, 0), coalesce((r->>'pa_n')::int, 0),
         coalesce((r->>'ps_sum')::numeric, 0), coalesce((r->>'ps_n')::int, 0),
         coalesce((r->>'moh_sum')::numeric, 0), coalesce((r->>'moh_n')::int, 0),
         coalesce((r->>'sz_sum')::numeric, 0), coalesce((r->>'sz_n')::int, 0),
         nullif(r->>'sz_min', '')::numeric, nullif(r->>'sz_max', '')::numeric,
         coalesce((r->>'sqa_p')::numeric, 0), coalesce((r->>'sqa_s')::numeric, 0),
         coalesce((r->>'sqs_p')::numeric, 0), coalesce((r->>'sqs_s')::numeric, 0),
         tv_safe_date(r->>'launch'),
         coalesce((r->>'avail_b')::int, 0), coalesce((r->>'avail_n')::int, 0),
         coalesce((r->>'c30b')::int, 0), coalesce((r->>'c90b')::int, 0), coalesce((r->>'cyb')::int, 0)
  from jsonb_array_elements(p_rows) r
  where nullif(btrim(r->>'project_name'), '') is not null
  on conflict (project_name, project_code, model, unit_type, beds) do update set
    developer = excluded.developer, kind = excluded.kind, sector = excluded.sector, city = excluded.city, dest = excluded.dest,
    avail_p = excluded.avail_p, avail_d = excluded.avail_d, reserved = excluded.reserved, contracts = excluded.contracts,
    other = excluded.other, c30 = excluded.c30, c90 = excluded.c90, cy = excluded.cy, b30 = excluded.b30, months = excluded.months,
    pa_sum = excluded.pa_sum, pa_n = excluded.pa_n, ps_sum = excluded.ps_sum, ps_n = excluded.ps_n,
    moh_sum = excluded.moh_sum, moh_n = excluded.moh_n, sz_sum = excluded.sz_sum, sz_n = excluded.sz_n,
    sz_min = excluded.sz_min, sz_max = excluded.sz_max, sqa_p = excluded.sqa_p, sqa_s = excluded.sqa_s,
    sqs_p = excluded.sqs_p, sqs_s = excluded.sqs_s, launch = excluded.launch,
    avail_b = excluded.avail_b, avail_n = excluded.avail_n, c30b = excluded.c30b, c90b = excluded.c90b, cyb = excluded.cyb, updated_at = now();
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- كل الصفوف بصيغة أعمدة مضغوطة (cols + rows كمصفوفات) — الشاشة تصفّي وتجمّع حسب المعايير
create or replace function get_tv_product_stats()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'ok', true,
    'as_of', (select max(updated_at) from tv_product_stats),
    'year', extract(year from now())::int,
    'cols', jsonb_build_array('project','code','model','type','beds','developer','kind','sector','city','dest',
      'avail_p','avail_d','reserved','contracts','c30','c90','cy','b30','months',
      'pa_sum','pa_n','ps_sum','ps_n','moh_sum','moh_n','sz_sum','sz_n','sz_min','sz_max','sqa_p','sqa_s','sqs_p','sqs_s','launch',
      'avail_b','avail_n','c30b','c90b','cyb'),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_array(project_name, project_code, model, unit_type, beds, developer, kind,
        coalesce(tv_region(nullif(sector, ''), null), sector), city, dest,
        avail_p, avail_d, reserved, contracts, c30, c90, cy, b30, to_jsonb(months),
        round(pa_sum), pa_n, round(ps_sum), ps_n, round(moh_sum), moh_n, round(sz_sum, 1), sz_n, sz_min, sz_max,
        round(sqa_p), round(sqa_s, 1), round(sqs_p), round(sqs_s, 1), launch,
        avail_b, avail_n, c30b, c90b, cyb))
      from tv_product_stats
      where avail_p + avail_d + reserved + contracts > 0
    ), '[]'::jsonb)
  );
$$;

-- أداء موظف شهرياً لسنة: عقوده كل شهر، ومتوسط الفريق لنفس الشهر (عقود ÷ موظفين باعوا ذلك الشهر)،
-- وترتيبه بالسنة، ومواقع العمل والمناطق — من tv_employee_daily (أعمدة ملف التخصيص)
create or replace function get_tv_employee_months(p_employee text, p_year int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with yr as (
    select * from tv_employee_daily
    where contract_date >= make_date(p_year, 1, 1) and contract_date < make_date(p_year + 1, 1, 1)
  ), tot as (
    select employee, sum(cnt) as c from yr group by employee
  )
  select jsonb_build_object(
    'ok', true, 'employee', p_employee, 'year', p_year,
    'first_date', (select min(contract_date) from tv_employee_daily),
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('m', m, 'cnt', c, 'team_avg', ta, 'team_max', tm) order by m)
      from (
        select g.m,
               coalesce((select sum(cnt) from yr where employee = p_employee and extract(month from contract_date)::int = g.m), 0) as c,
               (select round(sum(cnt)::numeric / nullif(count(distinct employee), 0), 1) from yr where extract(month from contract_date)::int = g.m) as ta,
               (select max(s) from (select sum(cnt) s from yr where extract(month from contract_date)::int = g.m group by employee) z) as tm
        from generate_series(1, 12) g(m)
      ) x
    ), '[]'::jsonb),
    'total', coalesce((select c from tot where employee = p_employee), 0),
    'rank', (select count(*) + 1 from tot where c > coalesce((select c from tot where employee = p_employee), 0)),
    'employees', (select count(*) from tot),
    'work', coalesce((select jsonb_agg(jsonb_build_object('work', work_location, 'cnt', c) order by c desc)
                      from (select work_location, sum(cnt) c from yr where employee = p_employee group by 1) w), '[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('sector', s, 'kind', kind, 'cnt', c) order by c desc)
                      from (select tv_region(nullif(sector, ''), null) s, kind, sum(cnt) c from yr where employee = p_employee group by 1, 2) w), '[]'::jsonb)
  );
$$;
