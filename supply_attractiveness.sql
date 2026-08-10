-- ============================================================
-- SalesPlace — مؤشر جاذبية بيع كل مبنى (0-100%)، من ثلاثة عوامل مرجَّحة كما حدَّدها
-- المستخدم صراحة:
--   1) عامل التصميم (35%): نسبة بيع نفس تركيبة (النوع + عدد الغرف) بكل مشاريع نفس
--      الوجهة — مدى إقبال السوق على هذه المواصفات تحديداً هناك.
--   2) عامل السعر (35%): تنافسية متوسط سعر متر المبنى مقارنة بمتوسط متر الوجهة.
--   3) عامل المبيعات (30%): نسبة بيع المشروع ككل (تُحسَب بالعميل من BOOK الحيّ، لا حاجة
--      لدالة قاعدة منفصلة لها).
-- إضافتان فقط: avg_beds على get_supply_buildings (بإعادة تعريف الدالة، بنفس قيد الإسقاط
-- المطلوب من Postgres عند تغيّر أعمدة RETURNS TABLE)، ودالة جديدة get_avg_sqm_price
-- لحساب متوسط سعر متر الوجهة (بتمرير قائمة project_id من العميل، بلا حاجة لعمود "وجهة"
-- بجداول المرآة أصلاً).
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor (بعد الملفات السابقة).
-- ============================================================

drop function if exists get_supply_buildings(integer, text);
create or replace function get_supply_buildings(p_project_id integer, p_unit_type text default null)
returns table(
  building_number text, avail_count bigint, avail_value numeric, avail_sqm_value numeric,
  blocked_count bigint, blocked_value numeric, blocked_sqm_value numeric, sold_count bigint,
  avg_beds numeric
)
language sql
stable
as $function$
  with avail_agg as (
    select building_number, count(*) avail_count, sum(price) avail_value,
           case when sum(unit_size) filter (where unit_size>0)>0
                then sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0)
                else null end as avail_sqm_value,
           round(avg(beds) filter (where beds is not null)) as avg_beds
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
                else null end as blocked_sqm_value,
           round(avg(beds) filter (where beds is not null)) as avg_beds
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
         coalesce(s.sold_count,0),
         coalesce(a.avg_beds, bl.avg_beds)
  from all_buildings ab
  left join avail_agg a on a.building_number is not distinct from ab.building_number
  left join sold_agg s on s.building_number is not distinct from ab.building_number
  left join blocked_agg bl on bl.building_number is not distinct from ab.building_number;
$function$;

-- متوسط سعر المتر المرجَّح (متاح فقط) عبر مجموعة مشاريع بعينها — يُستخدم لحساب متوسط
-- الوجهة الكاملة (كل مشاريعها) كمرجع مقارنة لعامل السعر، بتمرير project_ids من العميل
-- (كتالوج DATA يعرف أصلاً أي مشاريع تشترك بنفس الوجهة)
create or replace function get_avg_sqm_price(p_project_ids integer[], p_unit_type text default null)
returns numeric
language sql
stable
as $function$
  select case when sum(unit_size) filter (where unit_size>0)>0
    then sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0)
    else null end
  from unit_allocation_mirror
  where status='avail' and project_id = any(p_project_ids)
    and (p_unit_type is null or unit_type = p_unit_type);
$function$;
