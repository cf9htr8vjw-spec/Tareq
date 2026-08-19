-- ============================================================
-- SalesPlace — "مراقبة الأداء": الطبقة ٢ من نظام إدارة الأداء (قمع التحويل الداخلي
-- حجز ← استصناع ← عقد موقّع). مبنية مباشرة فوق unit_allocation_mirror — بلا حاجة لأي
-- مصدر بيانات جديد (طبقة التمويل مستثناة بطلب صريح، لا مصدر راتب/نسبة ربح فعلي متاح).
--
-- منهج الحساب: أفواج (cohorts) بتاريخ الحجز — لكل شهر حجز، نتتبّع الوحدات المحجوزة فيه
-- عبر كامل تاريخها اللاحق (لا نقارن أحداث شهر بأحداث شهر آخر بلا رابط، فهذا مضلِّل: حجز
-- هذا الشهر قد يتحوّل لعقد الشهر القادم لا نفسه). نسبة استصناع←عقد = من ضمن من وصل
-- للاستصناع فقط (لا من إجمالي المحجوز)، لأنها المقياس الحقيقي لتسرّب ما بعد الاستصناع.
--
-- مدة التحوّل: متوسط ووسيط معاً دائماً (البيانات التاريخية موزّعة ثنائياً — متوسط وحده
-- مضلِّل)، + توزيع شرائحي (≤7 / 8-30 / 31-90 / >90 يوم) لكل الوحدات التي أُغلقت فعلاً.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor.
-- ============================================================

-- اتجاه شهري إجمالي (يغذّي بطاقات المؤشرات وتنبيه الانخفاض الشهرين المتتاليين)
create or replace function get_funnel_monthly(
  p_sector text default null, p_dev_kind text default null, p_unit_type text default null, p_months integer default 12
)
returns table(
  month date,
  booked_count bigint, istisna_count bigint, contract_count bigint,
  istisna_rate numeric, contract_rate numeric,
  mean_days numeric, median_days numeric,
  pct_le7 numeric, pct_8_30 numeric, pct_31_90 numeric, pct_gt90 numeric
)
language sql
stable
as $function$
  with cohort as (
    select date_trunc('month', booking_date)::date as month,
           istisna_date, contract_date,
           (contract_date - booking_date) as dur
    from unit_allocation_mirror
    where booking_date is not null
      and booking_date >= date_trunc('month', now()) - (p_months || ' months')::interval
      and (p_sector is null or sector = p_sector)
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
  )
  select
    month,
    count(*) as booked_count,
    count(*) filter (where istisna_date is not null) as istisna_count,
    count(*) filter (where contract_date is not null) as contract_count,
    round(100.0 * count(*) filter (where istisna_date is not null) / nullif(count(*),0), 1) as istisna_rate,
    round(100.0 * count(*) filter (where contract_date is not null) / nullif(count(*) filter (where istisna_date is not null),0), 1) as contract_rate,
    round(avg(dur) filter (where contract_date is not null), 1) as mean_days,
    round((percentile_cont(0.5) within group (order by dur) filter (where contract_date is not null))::numeric, 1) as median_days,
    round(100.0 * count(*) filter (where contract_date is not null and dur<=7) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_le7,
    round(100.0 * count(*) filter (where contract_date is not null and dur>7 and dur<=30) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_8_30,
    round(100.0 * count(*) filter (where contract_date is not null and dur>30 and dur<=90) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_31_90,
    round(100.0 * count(*) filter (where contract_date is not null and dur>90) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_gt90
  from cohort
  group by month
  order by month;
$function$;

-- نفس المقاييس، مجمَّعة حسب المشروع بدل الشهر — لعرض "الأضعف أولاً"
create or replace function get_funnel_by_project(
  p_sector text default null, p_dev_kind text default null, p_unit_type text default null, p_months integer default 12
)
returns table(
  project_name text,
  booked_count bigint, istisna_count bigint, contract_count bigint,
  istisna_rate numeric, contract_rate numeric,
  mean_days numeric, median_days numeric,
  pct_le7 numeric, pct_8_30 numeric, pct_31_90 numeric, pct_gt90 numeric
)
language sql
stable
as $function$
  with cohort as (
    select project_name, istisna_date, contract_date, (contract_date - booking_date) as dur
    from unit_allocation_mirror
    where booking_date is not null and project_name is not null
      and booking_date >= date_trunc('month', now()) - (p_months || ' months')::interval
      and (p_sector is null or sector = p_sector)
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
  )
  select
    project_name,
    count(*) as booked_count,
    count(*) filter (where istisna_date is not null) as istisna_count,
    count(*) filter (where contract_date is not null) as contract_count,
    round(100.0 * count(*) filter (where istisna_date is not null) / nullif(count(*),0), 1) as istisna_rate,
    round(100.0 * count(*) filter (where contract_date is not null) / nullif(count(*) filter (where istisna_date is not null),0), 1) as contract_rate,
    round(avg(dur) filter (where contract_date is not null), 1) as mean_days,
    round((percentile_cont(0.5) within group (order by dur) filter (where contract_date is not null))::numeric, 1) as median_days,
    round(100.0 * count(*) filter (where contract_date is not null and dur<=7) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_le7,
    round(100.0 * count(*) filter (where contract_date is not null and dur>7 and dur<=30) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_8_30,
    round(100.0 * count(*) filter (where contract_date is not null and dur>30 and dur<=90) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_31_90,
    round(100.0 * count(*) filter (where contract_date is not null and dur>90) / nullif(count(*) filter (where contract_date is not null),0), 1) as pct_gt90
  from cohort
  group by project_name
  having count(*) >= 3
  order by (100.0 * count(*) filter (where contract_date is not null) / nullif(count(*) filter (where istisna_date is not null),0)) asc nulls last;
$function$;

-- القسم البارز الأهم: وحدات محجوزة منذ أكثر من 90 يوماً بلا عقد نهائي بعد
create or replace function get_stuck_units(
  p_sector text default null, p_dev_kind text default null, p_unit_type text default null
)
returns table(
  project_name text, building_number text, zone_number text, unit_code text,
  booking_date date, days_stuck integer, price numeric
)
language sql
stable
as $function$
  select project_name, building_number, zone_number, unit_code, booking_date,
    (current_date - booking_date)::int as days_stuck, price
  from unit_allocation_mirror
  where status='reserved' and contract_date is null and booking_date is not null
    and booking_date <= current_date - interval '90 days'
    and (p_sector is null or sector = p_sector)
    and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
    and (p_unit_type is null or unit_type = p_unit_type)
  order by booking_date asc;
$function$;
