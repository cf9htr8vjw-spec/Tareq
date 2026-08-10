-- ============================================================
-- SalesPlace — تفصيل إضافي لكل مبنى بشاشة "توزيع المعروض": هل بيع منها شيء، متوسط
-- سعر المتر، مصححاً أيضاً خطأً بمطابقة NULL بدالة get_supply_buildings السابقة
-- (unit_size عمود إضافي بحت — لا يمسّ أي بيانات موجودة)
-- ============================================================

alter table unit_allocation_mirror add column if not exists unit_size numeric;
alter table unit_blocked_mirror add column if not exists unit_size numeric;

-- ---------- admin_upsert_allocation_mirror — إعادة تعريف بإضافة unit_size فقط ----------
CREATE OR REPLACE FUNCTION public.admin_upsert_allocation_mirror(p_admin text, p_pass text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from public.app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  insert into public.unit_allocation_mirror
    (project_name, project_id, city, sector, dev_kind, unit_type, beds,
     price, moh_price, status, booking_date, istisna_date, contract_date, snapshot_date,
     unit_code, model, building_number, unit_size)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'status',
    nullif(r->>'booking_date','')::date, nullif(r->>'istisna_date','')::date, nullif(r->>'contract_date','')::date,
    (r->>'snapshot_date')::date,
    r->>'unit_code', r->>'model', r->>'building_number', nullif(r->>'unit_size','')::numeric
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- admin_upsert_blocked_mirror — إعادة تعريف بإضافة unit_size فقط ----------
create or replace function admin_upsert_blocked_mirror(p_admin text, p_pass text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from public.app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  insert into public.unit_blocked_mirror
    (project_name, project_id, city, sector, dev_kind, unit_type, beds,
     price, moh_price, unit_code, model, snapshot_date, building_number, unit_size)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'unit_code', r->>'model',
    (r->>'snapshot_date')::date, r->>'building_number', nullif(r->>'unit_size','')::numeric
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- get_supply_buildings — إعادة تعريف: يضيف sold_count (تم بيع شيء أم لا)
-- ومتوسط سعر المتر المرجَّح للمتاح (sum(price)/sum(unit_size))، ويصحح خطأً بالنسخة
-- السابقة: full outer join على building_number مباشرة لا يطابق صفين NULL ببعضهما
-- (NULL = NULL يُقيَّم NULL/غير صحيح بـSQL قياسياً) — فكانت وحدات بلا رقم مبنى من
-- المتاح والمحجوب قد تظهر كصفَّين منفصلين بدل صف واحد مُجمَّع. الحل: تجميع كل مصدر على
-- حدة بجدول CTE، ثم دمج بمطابقة IS NOT DISTINCT FROM (تعامل NULL كقيمة مطابقة لذاتها).
-- ملاحظة: PostgreSQL يرفض CREATE OR REPLACE إذا تغيّرت أعمدة RETURNS TABLE (هنا أُضيف
-- avail_sqm_value وsold_count) — لازم DROP صريح أولاً قبل إعادة الإنشاء. ----------
drop function if exists get_supply_buildings(integer, text);
create or replace function get_supply_buildings(p_project_id integer, p_unit_type text default null)
returns table(building_number text, avail_count bigint, avail_value numeric, avail_sqm_value numeric, blocked_count bigint, sold_count bigint)
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
    select building_number, count(*) blocked_count
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
         coalesce(bl.blocked_count,0), coalesce(s.sold_count,0)
  from all_buildings ab
  left join avail_agg a on a.building_number is not distinct from ab.building_number
  left join sold_agg s on s.building_number is not distinct from ab.building_number
  left join blocked_agg bl on bl.building_number is not distinct from ab.building_number;
$function$;
