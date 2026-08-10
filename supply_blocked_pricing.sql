-- ============================================================
-- SalesPlace — قيمة وسعر متر تقديريان للوحدات المحجوبة أيضاً بتفصيل المبانٍ (توزيع
-- المعروض) — كانت تُحسب فقط للمتاح، فأي مبنى محجوب بالكامل (متاح=0) يظهر بلا أي سعر،
-- رغم أن الهدف من عرضه أصلاً هو تقييمه لصفقة إفراج وبيع لمستثمر. لا تغيير على أي بيانات
-- مخزَّنة — فقط توسيع دالة القراءة get_supply_buildings.
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor (بعد supply_building_details.sql).
-- ============================================================

drop function if exists get_supply_buildings(integer, text);
create or replace function get_supply_buildings(p_project_id integer, p_unit_type text default null)
returns table(
  building_number text, avail_count bigint, avail_value numeric, avail_sqm_value numeric,
  blocked_count bigint, blocked_value numeric, blocked_sqm_value numeric, sold_count bigint
)
language sql
stable
as $function$
  with avail_agg as (
    select building_number, count(*) avail_count, sum(price) avail_value,
           case when sum(unit_size) filter (where unit_size>0)>0
                then sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0)
                else null end as avail_sqm_value
    from unit_allocation_mirror
    where project_id = p_project_id and status='avail'
      and (p_unit_type is null or unit_type = p_unit_type)
    group by building_number
  ),
  sold_agg as (
    select building_number, count(*) sold_count
    from unit_allocation_mirror
    where project_id = p_project_id and status in ('reserved','contracted')
      and (p_unit_type is null or unit_type = p_unit_type)
    group by building_number
  ),
  blocked_agg as (
    select building_number, count(*) blocked_count, sum(price) blocked_value,
           case when sum(unit_size) filter (where unit_size>0)>0
                then sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0)
                else null end as blocked_sqm_value
    from unit_blocked_mirror
    where project_id = p_project_id
      and (p_unit_type is null or unit_type = p_unit_type)
    group by building_number
  ),
  all_buildings as (
    select building_number from avail_agg
    union select building_number from sold_agg
    union select building_number from blocked_agg
  )
  select ab.building_number,
         coalesce(a.avail_count,0), coalesce(a.avail_value,0), a.avail_sqm_value,
         coalesce(bl.blocked_count,0), coalesce(bl.blocked_value,0), bl.blocked_sqm_value,
         coalesce(s.sold_count,0)
  from all_buildings ab
  left join avail_agg a on a.building_number is not distinct from ab.building_number
  left join sold_agg s on s.building_number is not distinct from ab.building_number
  left join blocked_agg bl on bl.building_number is not distinct from ab.building_number;
$function$;
