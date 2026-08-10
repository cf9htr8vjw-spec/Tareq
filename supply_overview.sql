-- ============================================================
-- SalesPlace — شاشة "توزيع المعروض لغير المستفيدين والمستثمرين"
-- إضافات بحتة: عمود building_number على الجدولين الحاليين (unit_allocation_mirror،
-- unit_blocked_mirror) + دالتا قراءة تجميعية جديدتان لا تمسّان أي بيانات موجودة.
--
-- تحذير مهم: هذا الملف يُعيد تعريف admin_upsert_allocation_mirror بإضافة عمود
-- building_number فقط لقائمة الإدراج/الاختيار — بقية الدالة هي بالضبط نفس النص
-- المؤكَّد من fix_unit_allocation_mirror_upsert.sql (نفس فحص is_admin، نفس بقية
-- الأعمدة وترتيبها، بلا أي تغيير آخر).
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor. يتطلّب تشغيل blocked_units.sql
-- مسبقاً (لوجود جدول unit_blocked_mirror) — إن لم يكن مُشغَّلاً بعد شغّله أولاً.
-- ============================================================

alter table unit_allocation_mirror add column if not exists building_number text;
alter table unit_blocked_mirror add column if not exists building_number text;
create index if not exists unit_allocation_mirror_building_idx on unit_allocation_mirror(project_id, building_number);
create index if not exists unit_blocked_mirror_building_idx on unit_blocked_mirror(project_id, building_number);

-- ---------- admin_upsert_allocation_mirror — إعادة تعريف بإضافة building_number فقط ----------
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
     unit_code, model, building_number)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'status',
    nullif(r->>'booking_date','')::date, nullif(r->>'istisna_date','')::date, nullif(r->>'contract_date','')::date,
    (r->>'snapshot_date')::date,
    r->>'unit_code', r->>'model', r->>'building_number'
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- admin_upsert_blocked_mirror — إعادة تعريف بإضافة building_number فقط ----------
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
     price, moh_price, unit_code, model, snapshot_date, building_number)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'unit_code', r->>'model',
    (r->>'snapshot_date')::date, r->>'building_number'
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- get_supply_overview ----------
-- عدد الوحدات المتاحة والمحجوبة لكل مشروع، بتصفية اختيارية بنوع الوحدة (منتج) فقط —
-- تصفية المدينة/الضاحية/جهة التطوير تُطبَّق بالعميل من كتالوج المشاريع المضمَّن (بيانات
-- مشروع، لا حاجة لتكرارها بكل صف خام). قراءة عامة (بلا فحص دخول) — نفس نمط
-- get_project_totals/get_target_summary الموجودتين أصلاً.
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
    where status='avail' and project_id is not null
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_id
  ) a
  full outer join (
    select project_id, count(*) blocked_count
    from unit_blocked_mirror
    where project_id is not null
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_id
  ) b on a.project_id = b.project_id;
$function$;

-- ---------- get_supply_buildings ----------
-- تفصيل مبانٍ مشروع واحد: عدد المتاح وقيمته (سعر غير المستفيدين price)، وعدد المحجوب،
-- من عمود building_number (ملف التخصيص + ملف الوحدات المحجوبة معاً) — بتصفية اختيارية بالنوع.
create or replace function get_supply_buildings(p_project_id integer, p_unit_type text default null)
returns table(building_number text, avail_count bigint, avail_value numeric, blocked_count bigint)
language sql
stable
as $function$
  select coalesce(a.building_number, b.building_number) as building_number,
         coalesce(a.avail_count,0) as avail_count,
         coalesce(a.avail_value,0) as avail_value,
         coalesce(b.blocked_count,0) as blocked_count
  from (
    select building_number, count(*) avail_count, sum(price) avail_value
    from unit_allocation_mirror
    where project_id = p_project_id and status='avail'
      and (p_unit_type is null or unit_type = p_unit_type)
    group by building_number
  ) a
  full outer join (
    select building_number, count(*) blocked_count
    from unit_blocked_mirror
    where project_id = p_project_id
      and (p_unit_type is null or unit_type = p_unit_type)
    group by building_number
  ) b on a.building_number = b.building_number;
$function$;
