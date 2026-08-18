-- ============================================================
-- SalesPlace — إضافات لشاشة "مبيعاتنا": فلتر نوع المنتج + متوسط المدة بين مراحل البيع.
--
-- get_sales_report و get_project_totals دالتان قديمتان سابقتان لهذا المستودع (لا يوجد
-- مصدرهما بأي ملف SQL هنا) — لتفادي خطر تعديلهما مباشرة بصمت (لا نعرف منطقهما الداخلي
-- بالضبط)، أضفنا دالتين جديدتين موازيتين (get_sales_report_by_type /
-- get_project_totals_by_type) تُستخدَمان فقط عندما يختار المستخدم نوع منتج محدد (فيلا/شقة/
-- تاون هاوس) من الشاشة؛ حالة "الكل" الافتراضية والأكثر استخداماً تبقى تستدعي الدالتين
-- الأصليتين بلا أي تغيير. الدالتان الجديدتان مبنيتان مباشرة فوق unit_allocation_mirror
-- (نفس مصدر التخصيص اليومي)، بنفس منطق تجميع الفترة (يوم/شهر/ربع) المستخدم أصلاً بالشاشة.
--
-- get_avg_durations: متوسط عدد الأيام بين توقيع الحجز وتوقيع عقد الاستصناع، وبين توقيع
-- الاستصناع والعقد النهائي — على 3 مستويات مطابقة لفلتر "المطوّر" الموجود أصلاً بالشاشة
-- (الكل / NHC / المطورون الآخرون).
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor.
-- ============================================================

create or replace function get_sales_report_by_type(
  p_granularity text, p_metric text, p_from date, p_to date,
  p_sector text default null, p_dev_kind text default null, p_unit_type text default null
)
returns table(period date, cnt bigint)
language sql
stable
as $function$
  with base as (
    select case p_metric
             when 'booking' then booking_date
             when 'istisna' then istisna_date
             when 'contract' then contract_date
           end as mdate
    from unit_allocation_mirror
    where (p_sector is null or sector = p_sector)
      and (p_dev_kind is null or
           (p_dev_kind = 'nhc' and dev_kind = 'nhc') or
           (p_dev_kind = 'other' and dev_kind <> 'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
  )
  select
    case p_granularity
      when 'day' then date_trunc('day', mdate)::date
      when 'month' then date_trunc('month', mdate)::date
      else date_trunc('quarter', mdate)::date
    end as period,
    count(*) as cnt
  from base
  where mdate is not null and mdate between p_from and p_to
  group by 1
  order by 1;
$function$;

create or replace function get_project_totals_by_type(
  p_metric text, p_from date, p_to date,
  p_sector text default null, p_dev_kind text default null, p_unit_type text default null
)
returns table(project_name text, cnt bigint)
language sql
stable
as $function$
  with base as (
    select project_name,
           case p_metric
             when 'booking' then booking_date
             when 'istisna' then istisna_date
             when 'contract' then contract_date
           end as mdate
    from unit_allocation_mirror
    where (p_sector is null or sector = p_sector)
      and (p_dev_kind is null or
           (p_dev_kind = 'nhc' and dev_kind = 'nhc') or
           (p_dev_kind = 'other' and dev_kind <> 'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
  )
  select project_name, count(*) as cnt
  from base
  where mdate is not null and mdate between p_from and p_to and project_name is not null
  group by project_name
  order by count(*) desc;
$function$;

create or replace function get_avg_durations(p_sector text default null, p_unit_type text default null)
returns jsonb
language plpgsql
stable
as $function$
declare
  v_all jsonb; v_nhc jsonb; v_other jsonb;
begin
  select jsonb_build_object(
    'avg_book_to_istisna', round(avg(istisna_date - booking_date) filter (where booking_date is not null and istisna_date is not null and istisna_date >= booking_date)),
    'n_book_to_istisna', count(*) filter (where booking_date is not null and istisna_date is not null and istisna_date >= booking_date),
    'avg_istisna_to_contract', round(avg(contract_date - istisna_date) filter (where istisna_date is not null and contract_date is not null and contract_date >= istisna_date)),
    'n_istisna_to_contract', count(*) filter (where istisna_date is not null and contract_date is not null and contract_date >= istisna_date)
  ) into v_all
  from unit_allocation_mirror
  where (p_sector is null or sector = p_sector) and (p_unit_type is null or unit_type = p_unit_type);

  select jsonb_build_object(
    'avg_book_to_istisna', round(avg(istisna_date - booking_date) filter (where booking_date is not null and istisna_date is not null and istisna_date >= booking_date)),
    'n_book_to_istisna', count(*) filter (where booking_date is not null and istisna_date is not null and istisna_date >= booking_date),
    'avg_istisna_to_contract', round(avg(contract_date - istisna_date) filter (where istisna_date is not null and contract_date is not null and contract_date >= istisna_date)),
    'n_istisna_to_contract', count(*) filter (where istisna_date is not null and contract_date is not null and contract_date >= istisna_date)
  ) into v_nhc
  from unit_allocation_mirror
  where dev_kind = 'nhc' and (p_sector is null or sector = p_sector) and (p_unit_type is null or unit_type = p_unit_type);

  select jsonb_build_object(
    'avg_book_to_istisna', round(avg(istisna_date - booking_date) filter (where booking_date is not null and istisna_date is not null and istisna_date >= booking_date)),
    'n_book_to_istisna', count(*) filter (where booking_date is not null and istisna_date is not null and istisna_date >= booking_date),
    'avg_istisna_to_contract', round(avg(contract_date - istisna_date) filter (where istisna_date is not null and contract_date is not null and contract_date >= istisna_date)),
    'n_istisna_to_contract', count(*) filter (where istisna_date is not null and contract_date is not null and contract_date >= istisna_date)
  ) into v_other
  from unit_allocation_mirror
  where dev_kind <> 'nhc' and (p_sector is null or sector = p_sector) and (p_unit_type is null or unit_type = p_unit_type);

  return jsonb_build_object('all', v_all, 'nhc', v_nhc, 'other', v_other);
end;
$function$;
