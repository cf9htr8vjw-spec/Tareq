-- ============================================================
-- SalesPlace — داشبورد شاشة التلفزيون (المبيعات حسب المنطقة + أسعار السوق)
-- جدول جديد + دالتا قراءة جديدتان بالكامل — لا تمسّ أي جدول أو دالة موجودة حالياً
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

-- ---------- market_price_stats ----------
-- بيانات سوق مرجعية خارجية (منصة سهيل) لكل منطقة/نوع عقار — تُستبدل بالكامل عند كل
-- تحديث (مرة شهرياً عادة، حسب مصدر الملف "حسب إقفال كل شهر"). يُستخدم property_type
-- بنفس تهجئة unit_type في unit_allocation_mirror (شقة/فيلا) للمقارنة المباشرة لاحقاً.
create table if not exists market_price_stats (
  id bigint generated always as identity primary key,
  region text not null,          -- اسم المنطقة كما بملف المصدر (الرياض، مكة المكرمة، المدينة المنورة، تبوك، الشرقية)
  property_type text not null,   -- شقة / فيلا (مفرد، بنفس تهجئة unit_type)
  avg_price numeric,
  avg_price_sqm numeric,
  deals_ytd integer,             -- صفقات السنة حتى تاريخ الملف
  deals_last_period integer,     -- صفقات آخر شهر مُقفل بالملف
  period_label text,             -- مثال: "من بداية 2026 حتى 18/9/2026"
  source text default 'منصة سهيل',
  updated_at timestamptz not null default now(),
  unique(region, property_type)
);

alter table market_price_stats enable row level security;
drop policy if exists market_price_stats_read on market_price_stats;
create policy market_price_stats_read on market_price_stats for select using (true);

create or replace function admin_upsert_market_price_stats(p_admin text, p_pass text, p_rows jsonb)
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

  insert into market_price_stats
    (region, property_type, avg_price, avg_price_sqm, deals_ytd, deals_last_period, period_label, source, updated_at)
  select
    r->>'region', r->>'property_type',
    nullif(r->>'avg_price','')::numeric, nullif(r->>'avg_price_sqm','')::numeric,
    nullif(r->>'deals_ytd','')::integer, nullif(r->>'deals_last_period','')::integer,
    r->>'period_label', coalesce(r->>'source','منصة سهيل'), now()
  from jsonb_array_elements(p_rows) r
  on conflict (region, property_type) do update set
    avg_price=excluded.avg_price, avg_price_sqm=excluded.avg_price_sqm,
    deals_ytd=excluded.deals_ytd, deals_last_period=excluded.deals_last_period,
    period_label=excluded.period_label, source=excluded.source, updated_at=now();

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'تم تحديث '||v_count||' صفاً');
end;
$$;

-- بذرة أولى من ملف منصة سهيل (حتى 18/9/2026) — الرفعات القادمة من لوحة الإدارة تستبدلها تلقائياً
insert into market_price_stats (region, property_type, avg_price, avg_price_sqm, deals_ytd, deals_last_period, period_label) values
  ('الرياض','شقة',770000,6537,16476,1846,'من بداية 2026 حتى 18/9/2026'),
  ('الرياض','فيلا',1880000,4145,8053,531,'من بداية 2026 حتى 18/9/2026'),
  ('المدينة المنورة','شقة',740000,3591,1075,97,'من بداية 2026 حتى 18/9/2026'),
  ('المدينة المنورة','فيلا',750000,1538,1201,118,'من بداية 2026 حتى 18/9/2026'),
  ('مكة المكرمة','شقة',730000,4141,10013,1134,'من بداية 2026 حتى 18/9/2026'),
  ('مكة المكرمة','فيلا',2040000,3149,3480,343,'من بداية 2026 حتى 18/9/2026'),
  ('تبوك','شقة',540000,2404,323,39,'من بداية 2026 حتى 18/9/2026'),
  ('تبوك','فيلا',630000,1087,511,45,'من بداية 2026 حتى 18/9/2026'),
  ('الشرقية','شقة',680000,3730,4724,437,'من بداية 2026 حتى 18/9/2026'),
  ('الشرقية','فيلا',1070000,2543,4266,280,'من بداية 2026 حتى 18/9/2026')
on conflict (region, property_type) do update set
  avg_price=excluded.avg_price, avg_price_sqm=excluded.avg_price_sqm,
  deals_ytd=excluded.deals_ytd, deals_last_period=excluded.deals_last_period,
  period_label=excluded.period_label, updated_at=now();

-- القطاع بكل الدوال أدناه = قطاع ملف التخصيص نفسه (file_sector) لكل وحدة، بصرف النظر عن تسجيل
-- المشروع بالتطبيق؛ sector (بيانات التطبيق) احتياط فقط لصفوف رُفعت قبل إضافة file_sector.
alter table unit_allocation_mirror add column if not exists file_sector text;

-- ---------- get_sector_type_sales ----------
-- مبيعات (عقود موقّعة) لكل قطاع × نوع وحدة خلال شهر معيّن: الإجمالي + تفصيل يومي —
-- من unit_allocation_mirror.contract_date الحقيقي، نفس مصدر get_sales_report الأصلية،
-- بلا أي جدول تراكمي جديد.
create or replace function get_sector_type_sales(p_year int, p_month int)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_from date := make_date(p_year, p_month, 1);
  v_to date := (make_date(p_year, p_month, 1) + interval '1 month' - interval '1 day')::date;
  v_result jsonb;
begin
  /* نسخة مُعاد هيكلتها — النسخة الأولى كانت subquery مرتبط (correlated) بداخله GROUP BY
     خاص به يرجع لعمود من الاستعلام الخارجي، فيرفضها Postgres بخطأ "subquery uses
     ungrouped column ... from outer query". الحل: تجميع واحد فقط (base) بمفتاح
     القطاع+النوع+اليوم، ثم تجميع ثانٍ (grouped) فوقه — بلا أي ارتباط متداخل إطلاقاً. */
  with base as (
    select
      coalesce(file_sector,sector,'غير محدد') as sector,
      coalesce(unit_type,'غير محدد') as unit_type,
      contract_date,
      count(*) as dcnt
    from unit_allocation_mirror
    where status='contracted' and contract_date between v_from and v_to
    group by coalesce(file_sector,sector,'غير محدد'), coalesce(unit_type,'غير محدد'), contract_date
  ),
  grouped as (
    select
      sector, unit_type,
      sum(dcnt) as total_cnt,
      jsonb_agg(jsonb_build_object('day', extract(day from contract_date)::int, 'cnt', dcnt) order by contract_date) as daily
    from base
    group by sector, unit_type
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'sector', sector, 'unit_type', unit_type, 'total_cnt', total_cnt, 'daily', daily
  ) order by sector, unit_type), '[]'::jsonb)
  into v_result
  from grouped;

  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to, 'rows', v_result);
end;
$$;

-- ---------- get_today_activity ----------
-- نشاط اليوم: حجوزات/استصناع/عقود — على مستوى المملكة وتفصيل لكل قطاع.
-- حجوزات = booking_date اليوم (بصرف النظر عن الحالة الحالية — تاريخ حدث، لا لقطة حالة).
-- استصناع = نفس تعريف project_istisna_stats الأصلية: حالة "حجز" ولها istisna_date فعلي،
-- بهذا التاريخ تحديداً اليوم. عقود = status='contracted' وcontract_date اليوم.
create or replace function get_today_activity()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'date', current_date,
    'kingdom', jsonb_build_object(
      'bookings', (select count(*) from unit_allocation_mirror where booking_date = current_date),
      'istisna', (select count(*) from unit_allocation_mirror where status='reserved' and istisna_date = current_date),
      'contracts', (select count(*) from unit_allocation_mirror where status='contracted' and contract_date = current_date)
    ),
    'by_sector', coalesce((
      select jsonb_agg(jsonb_build_object('sector', sector, 'bookings', bookings, 'istisna', istisna, 'contracts', contracts) order by sector)
      from (
        select coalesce(file_sector,sector,'غير محدد') as sector,
          count(*) filter (where booking_date = current_date) as bookings,
          count(*) filter (where status='reserved' and istisna_date = current_date) as istisna,
          count(*) filter (where status='contracted' and contract_date = current_date) as contracts
        from unit_allocation_mirror
        where booking_date = current_date
           or (status='reserved' and istisna_date = current_date)
           or (status='contracted' and contract_date = current_date)
        group by coalesce(file_sector,sector,'غير محدد')
      ) s
    ), '[]'::jsonb),
    'ok', true
  );
$$;

-- ---------- get_sector_avail_pricing ----------
-- متوسط سعر الوحدات المتاحة الآن وسعر المتر (sum(price)/sum(unit_size)) لكل قطاع —
-- نفس أسلوب get_supply_buildings تماماً، على مستوى القطاع بدل المبنى.
create or replace function get_sector_avail_pricing()
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'sector', sector, 'avail_count', avail_count, 'avg_price', avg_price, 'avg_price_sqm', avg_price_sqm
  ) order by sector), '[]'::jsonb)
  from (
    select coalesce(file_sector,sector,'غير محدد') as sector,
           count(*) as avail_count,
           round(avg(price)) as avg_price,
           case when sum(unit_size) filter (where unit_size>0)>0
                then round(sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0))
                else null end as avg_price_sqm
    from unit_allocation_mirror
    where status='avail'
    group by coalesce(file_sector,sector,'غير محدد')
  ) t;
$$;
