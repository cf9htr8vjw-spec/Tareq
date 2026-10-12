-- ============================================================
-- SalesPlace — شاشة الداشبورد: العقود حسب المنتج (شقة/فيلا/تاون هاوس) ومتوسط سعر المباع، وسعر السوق
-- ============================================================
-- • من ملف التخصيص كاملاً (حالة الحجز = عقد): نوع الوحدة وسعرها لكل عقد يُجمَعان عند الرفع
--   بجدول tv_contract_daily (عمودا unit_type و price_sum/price_n). متوسط سعر المباع = مجموع
--   السعر ÷ عدد العقود ذات السعر الصحيح (10,000 ريال فأكثر).
-- • سعر السوق: وثيقة تحليل الأسعار (منصة سهيل)، ورقة «حسب إقفال كل شهر» — متوسط سعر الوحدة وسعر
--   المتر وعدد الصفقات لكل منطقة × نوع (شقق/فلل) لكل شهر يناير–سبتمبر 2026؛ الشاشة تعرض آخر شهر.
--   لا يوجد سعر سوق للتاون هاوس بالوثيقة.
--
-- يتطلّب: tv_destinations.sql مُشغَّلاً قبله. شغّل هذا الملف مرة واحدة ثم ارفع ملف التخصيص من
-- جديد من التطبيق. آمن لإعادة التشغيل.
-- ============================================================

alter table tv_contract_daily add column if not exists project_name text not null default '';
alter table tv_contract_daily add column if not exists dest text not null default '';
-- نوع الوحدة وسعرها (لعقود حسب المنتج ومتوسط سعر المباع — tv_products.sql)
alter table tv_contract_daily add column if not exists unit_type text not null default '';
alter table tv_contract_daily add column if not exists price_sum numeric not null default 0;  -- مجموع سعر العقود ذات السعر الصحيح
alter table tv_contract_daily add column if not exists price_n integer not null default 0;    -- عددها
alter table tv_contract_daily drop constraint if exists tv_contract_daily_pkey;
alter table tv_contract_daily add constraint tv_contract_daily_pkey primary key (contract_date, project_name, sector, dest, kind, unit_type);

-- أسماء مشاريع ملف التخصيص بالتطبيق (لمطابقة خطة المطورين) — تبقى بين رفعات الملف من شاشة المبيعات
create table if not exists tv_project_app (
  project_name text primary key,
  app_name text not null
);
alter table tv_project_app enable row level security;
drop policy if exists tv_project_app_read on tv_project_app;
create policy tv_project_app_read on tv_project_app for select using (true);

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
    -- اسم التطبيق: من الرفع إن وُجد (التطبيق الأساسي)، وإلا آخر اسم معروف للمشروع
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

-- ---------- market_price_monthly ----------
create table if not exists market_price_monthly (
  region text not null,            -- الرياض / مكة المكرمة / المدينة المنورة / تبوك / الشرقية
  property_type text not null,     -- شقة / فيلا (بنفس تهجئة نوع الوحدة بالتخصيص)
  month date not null,             -- أول يوم بالشهر
  avg_price numeric,               -- متوسط سعر الوحدة
  avg_price_sqm numeric,           -- متوسط سعر المتر
  deals integer,                   -- عدد صفقات الشهر
  source text not null default 'منصة سهيل — حسب إقفال كل شهر',
  primary key (region, property_type, month)
);
alter table market_price_monthly enable row level security;
drop policy if exists market_price_monthly_read on market_price_monthly;
create policy market_price_monthly_read on market_price_monthly for select using (true);

insert into market_price_monthly (region, property_type, month, avg_price, avg_price_sqm, deals) values
('الرياض','شقة',date '2026-01-01',840000,7007,1744),
  ('مكة المكرمة','شقة',date '2026-01-01',660000,4057,1388),
  ('المدينة المنورة','شقة',date '2026-01-01',610000,3560,161),
  ('تبوك','شقة',date '2026-01-01',480000,2525,32),
  ('الشرقية','شقة',date '2026-01-01',660000,3539,501),
  ('الرياض','فيلا',date '2026-01-01',1960000,4158,1207),
  ('مكة المكرمة','فيلا',date '2026-01-01',2090000,3307,449),
  ('المدينة المنورة','فيلا',date '2026-01-01',870000,1847,173),
  ('تبوك','فيلا',date '2026-01-01',620000,1060,87),
  ('الشرقية','فيلا',date '2026-01-01',1030000,2416,675),
  ('الرياض','شقة',date '2026-02-01',920000,6374,1350),
  ('مكة المكرمة','شقة',date '2026-02-01',800000,4918,1104),
  ('المدينة المنورة','شقة',date '2026-02-01',800000,3811,121),
  ('تبوك','شقة',date '2026-02-01',530000,2093,29),
  ('الشرقية','شقة',date '2026-02-01',660000000,3477,520),
  ('الرياض','فيلا',date '2026-02-01',1860000,4357,1045),
  ('مكة المكرمة','فيلا',date '2026-02-01',1740000,3101,410),
  ('المدينة المنورة','فيلا',date '2026-02-01',820000,1529,118),
  ('تبوك','فيلا',date '2026-02-01',730000,1368,63),
  ('الشرقية','فيلا',date '2026-02-01',1270000,2932,532),
  ('الرياض','شقة',date '2026-03-01',870000,6615,1202),
  ('مكة المكرمة','شقة',date '2026-03-01',740000,4387,653),
  ('المدينة المنورة','شقة',date '2026-03-01',700000,3772,68),
  ('تبوك','شقة',date '2026-03-01',510000,2396,24),
  ('الشرقية','شقة',date '2026-03-01',620000,3184,448),
  ('الرياض','فيلا',date '2026-03-01',1900000,4640,780),
  ('مكة المكرمة','فيلا',date '2026-03-01',2030000,3327,283),
  ('المدينة المنورة','فيلا',date '2026-03-01',630000,1424,81),
  ('تبوك','فيلا',date '2026-03-01',550000,882.5,36),
  ('الشرقية','فيلا',date '2026-03-01',1400000,3000,377),
  ('الرياض','شقة',date '2026-04-01',900000,6578,1763),
  ('مكة المكرمة','شقة',date '2026-04-01',800000,4075,1235),
  ('المدينة المنورة','شقة',date '2026-04-01',710000,3404,123),
  ('تبوك','شقة',date '2026-04-01',490000,2315,52),
  ('الشرقية','شقة',date '2026-04-01',659000,3691,612),
  ('الرياض','فيلا',date '2026-04-01',1960000,4263,1286),
  ('مكة المكرمة','فيلا',date '2026-04-01',2100000,3589,452),
  ('المدينة المنورة','فيلا',date '2026-04-01',880000,1705,189),
  ('تبوك','فيلا',date '2026-04-01',820000,1388,66),
  ('الشرقية','فيلا',date '2026-04-01',1060000,2676,661),
  ('الرياض','شقة',date '2026-05-01',840000,6976,1362),
  ('مكة المكرمة','شقة',date '2026-05-01',790000,4326,883),
  ('المدينة المنورة','شقة',date '2026-05-01',790000,3859,132),
  ('تبوك','شقة',date '2026-05-01',530000,2367,14),
  ('الشرقية','شقة',date '2026-05-01',880000,5265,521),
  ('الرياض','فيلا',date '2026-05-01',1750000,4381,1037),
  ('مكة المكرمة','فيلا',date '2026-05-01',1920000,3307,354),
  ('المدينة المنورة','فيلا',date '2026-05-01',900000,1911,113),
  ('تبوك','فيلا',date '2026-05-01',510000,891.1,52),
  ('الشرقية','فيلا',date '2026-05-01',1200000,2930,569),
  ('الرياض','شقة',date '2026-06-01',670000,6509,2208),
  ('مكة المكرمة','شقة',date '2026-06-01',670000,3921,1267),
  ('المدينة المنورة','شقة',date '2026-06-01',680000,2930,147),
  ('تبوك','شقة',date '2026-06-01',520000,2309,44),
  ('الشرقية','شقة',date '2026-06-01',670000,3455,608),
  ('الرياض','فيلا',date '2026-06-01',1740000,4010,919),
  ('مكة المكرمة','فيلا',date '2026-06-01',1870000,3237,464),
  ('المدينة المنورة','فيلا',date '2026-06-01',560000,1149,160),
  ('تبوك','فيلا',date '2026-06-01',730000,1243,73),
  ('الشرقية','فيلا',date '2026-06-01',960000,2441,539),
  ('الرياض','شقة',date '2026-07-01',680000,6522,2743),
  ('مكة المكرمة','شقة',date '2026-07-01',780000,3969,1202),
  ('المدينة المنورة','شقة',date '2026-07-01',780000,4091,131),
  ('تبوك','شقة',date '2026-07-01',470000,2493,36),
  ('الشرقية','شقة',date '2026-07-01',650000,3913,586),
  ('الرياض','فيلا',date '2026-07-01',1860000,3766,797),
  ('مكة المكرمة','فيلا',date '2026-07-01',1570000,2675,348),
  ('المدينة المنورة','فيلا',date '2026-07-01',490000,1070,158),
  ('تبوك','فيلا',date '2026-07-01',480000,913,62),
  ('الشرقية','فيلا',date '2026-07-01',790000,1816,366),
  ('الرياض','شقة',date '2026-08-01',770000,6641,2331),
  ('مكة المكرمة','شقة',date '2026-08-01',700000,4010,1162),
  ('المدينة المنورة','شقة',date '2026-08-01',730000,3293,94),
  ('تبوك','شقة',date '2026-08-01',600000,2626,52),
  ('الشرقية','شقة',date '2026-08-01',680000,3501,504),
  ('الرياض','فيلا',date '2026-08-01',1860000,3635,771),
  ('مكة المكرمة','فيلا',date '2026-08-01',1380000,2700,394),
  ('المدينة المنورة','فيلا',date '2026-08-01',630000,1273,157),
  ('تبوك','فيلا',date '2026-08-01',480000,827,52),
  ('الشرقية','فيلا',date '2026-08-01',950000,2025,331),
  ('الرياض','شقة',date '2026-09-01',630000,5884,2443),
  ('مكة المكرمة','شقة',date '2026-09-01',610000,3832,1168),
  ('المدينة المنورة','شقة',date '2026-09-01',800000,3780,96),
  ('تبوك','شقة',date '2026-09-01',730000,2600,37),
  ('الشرقية','شقة',date '2026-09-01',640000,3566,525),
  ('الرياض','فيلا',date '2026-09-01',1870000,3919,690),
  ('مكة المكرمة','فيلا',date '2026-09-01',4120000,3257,337),
  ('المدينة المنورة','فيلا',date '2026-09-01',690000,1116,121),
  ('تبوك','فيلا',date '2026-09-01',520000,824.4,51),
  ('الشرقية','فيلا',date '2026-09-01',880000,1907,310)
on conflict (region, property_type, month) do update set
  avg_price = excluded.avg_price, avg_price_sqm = excluded.avg_price_sqm, deals = excluded.deals;

-- ---------- get_tv_products ----------
-- العقود ومجموع السعر لكل قطاع × NHC/مطور × نوع وحدة بين تاريخين، وسعر السوق لآخر شهر متوفر.
create or replace function get_tv_products(p_from date, p_to date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'ok', true, 'from', p_from, 'to', p_to,
    'as_of', (select max(updated_at) from tv_contract_daily),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object('sector', sec, 'kind', kind, 'type', unit_type, 'cnt', c, 'psum', ps, 'pn', pn))
      from (
        select tv_region(nullif(sector, ''), null) as sec, kind, unit_type, sum(cnt) as c, sum(price_sum) as ps, sum(price_n) as pn
        from tv_contract_daily
        where contract_date between p_from and p_to
        group by 1, 2, 3
      ) x
    ), '[]'::jsonb),
    'market_month', (select max(month) from market_price_monthly),
    'market', coalesce((
      select jsonb_agg(jsonb_build_object('region', region, 'type', property_type, 'avg_price', avg_price,
                                          'avg_price_sqm', avg_price_sqm, 'deals', deals))
      from market_price_monthly where month = (select max(month) from market_price_monthly)
    ), '[]'::jsonb)
  );
$$;
