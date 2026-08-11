-- ============================================================
-- SalesPlace — قصر شاشة "توزيع المعروض" فعلياً على الوحدات المتاحة لغير المستفيدين/
-- المستثمرين فقط، من عمود target_segments بملفي التخصيص والمحجوب — كانت الشاشة تعرض
-- كل الوحدات بصرف النظر عن شريحتها (السعر فقط كان "غير مستفيدين"، لا عدّاد الوحدات).
--
-- for_non_beneficiary تُحسَب بالعميل (نفس قاعدة parseSegmentTag المستخدمة أصلاً لإحصاء
-- المشروع): true فقط لو target_segments يتضمّن غير مستفيدين/شركة (أي قيمة غير
-- {beneficiary} حصراً)؛ false لكل ما عداها (يشمل {beneficiary} حصراً، والفارغ/غير
-- المعروف — استبعاد احتياطي بدل افتراض الأهلية خطأً).
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor (بعد كل الملفات السابقة)، ثم أعد رفع
-- ملف التخصيص وملف المحجوب من جديد — البيانات القديمة ما فيها هذا العمود أصلاً.
-- ============================================================

alter table unit_allocation_mirror add column if not exists for_non_beneficiary boolean;
alter table unit_blocked_mirror add column if not exists for_non_beneficiary boolean;
create index if not exists unit_allocation_mirror_nonbenef_idx on unit_allocation_mirror(for_non_beneficiary);
create index if not exists unit_blocked_mirror_nonbenef_idx on unit_blocked_mirror(for_non_beneficiary);

-- ---------- admin_upsert_allocation_mirror — إعادة تعريف بإضافة for_non_beneficiary فقط ----------
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
     unit_code, model, building_number, unit_size, for_non_beneficiary)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'status',
    nullif(r->>'booking_date','')::date, nullif(r->>'istisna_date','')::date, nullif(r->>'contract_date','')::date,
    (r->>'snapshot_date')::date,
    r->>'unit_code', r->>'model', r->>'building_number', nullif(r->>'unit_size','')::numeric,
    (r->>'for_non_beneficiary')::boolean
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- admin_upsert_blocked_mirror — إعادة تعريف بإضافة for_non_beneficiary فقط ----------
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
     price, moh_price, unit_code, model, snapshot_date, building_number, unit_size, for_non_beneficiary)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'unit_code', r->>'model',
    (r->>'snapshot_date')::date, r->>'building_number', nullif(r->>'unit_size','')::numeric,
    (r->>'for_non_beneficiary')::boolean
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- get_supply_overview — إضافة تصفية for_non_beneficiary=true فقط (لا تغيّر أعمدة الإخراج) ----------
create or replace function get_supply_overview(p_unit_type text default null)
returns table(project_id integer, avail_count bigint, blocked_count bigint)
language sql
stable
as $function$
  select coalesce(a.project_id, b.project_id) as project_id,
         coalesce(a.avail_count,0) as avail_count,
         coalesce(b.blocked_count,0) as blocked_count
  from (
    select project_id, count(*) avail_count
    from unit_allocation_mirror
    where status='avail' and project_id is not null and for_non_beneficiary is true
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_id
  ) a
  full outer join (
    select project_id, count(*) blocked_count
    from unit_blocked_mirror
    where project_id is not null and for_non_beneficiary is true
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_id
  ) b on a.project_id = b.project_id;
$function$;

-- ---------- get_supply_buildings — إضافة نفس التصفية (لا تغيّر أعمدة الإخراج) ----------
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
    where project_id = p_project_id and status='avail' and for_non_beneficiary is true
      and (p_unit_type is null or unit_type = p_unit_type)
    group by building_number
  ),
  sold_agg as (
    select building_number, count(*) sold_count
    from unit_allocation_mirror
    where project_id = p_project_id and status in ('reserved','contracted') and for_non_beneficiary is true
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
    where project_id = p_project_id and for_non_beneficiary is true
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

-- ---------- get_avg_sqm_price — إضافة نفس التصفية (لا تغيّر أعمدة الإخراج) ----------
create or replace function get_avg_sqm_price(p_project_ids integer[], p_unit_type text default null)
returns numeric
language sql
stable
as $function$
  select case when sum(unit_size) filter (where unit_size>0)>0
    then sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0)
    else null end
  from unit_allocation_mirror
  where status='avail' and project_id = any(p_project_ids) and for_non_beneficiary is true
    and (p_unit_type is null or unit_type = p_unit_type);
$function$;
