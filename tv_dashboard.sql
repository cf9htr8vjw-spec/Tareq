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
  select coalesce(jsonb_agg(t order by t->>'sector', t->>'unit_type'), '[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'sector', coalesce(u.sector,'غير محدد'),
      'unit_type', coalesce(u.unit_type,'غير محدد'),
      'total_cnt', count(*),
      'daily', (
        select coalesce(jsonb_agg(jsonb_build_object('day', extract(day from u2.contract_date)::int, 'cnt', dcnt) order by extract(day from u2.contract_date)), '[]'::jsonb)
        from (
          select contract_date, count(*) as dcnt
          from unit_allocation_mirror u2
          where u2.status='contracted' and u2.contract_date between v_from and v_to
            and coalesce(u2.sector,'غير محدد') = coalesce(u.sector,'غير محدد')
            and coalesce(u2.unit_type,'غير محدد') = coalesce(u.unit_type,'غير محدد')
          group by contract_date
        ) u2(contract_date, dcnt)
      )
    ) as t
    from unit_allocation_mirror u
    where u.status='contracted' and u.contract_date between v_from and v_to
    group by coalesce(u.sector,'غير محدد'), coalesce(u.unit_type,'غير محدد')
  ) t;

  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to, 'rows', v_result);
end;
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
    select coalesce(sector,'غير محدد') as sector,
           count(*) as avail_count,
           round(avg(price)) as avg_price,
           case when sum(unit_size) filter (where unit_size>0)>0
                then round(sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0))
                else null end as avg_price_sqm
    from unit_allocation_mirror
    where status='avail'
    group by coalesce(sector,'غير محدد')
  ) t;
$$;
