-- ============================================================
-- SalesPlace — إضافة رقم الزون (zone_number) لكل من مرآة التخصيص ومرآة المحجوب — أساس
-- الطبقة ١ من نظام "مراقبة الأداء" (تصنيف زون نشط/لم يُطرح بعد).
--
-- تعديل إضافي فقط — لا يمسّ أي عمود أو منطق موجود. عمودان جديدان قابلان لأن يكونا NULL
-- (لو الملف المصدر ما فيه عمود زون بعد، أو اسم العمود غير الأسماء اللي جرّبها المحلّل —
-- الشاشة تعرض تشخيصاً واضحاً بملخص الرفع بالحالتين).
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor (بعد كل الملفات السابقة).
-- ============================================================

alter table unit_allocation_mirror add column if not exists zone_number text;
alter table unit_blocked_mirror add column if not exists zone_number text;
create index if not exists unit_allocation_mirror_zone_idx on unit_allocation_mirror(project_id, zone_number);
create index if not exists unit_blocked_mirror_zone_idx on unit_blocked_mirror(project_id, zone_number);

-- ---------- admin_upsert_allocation_mirror — إعادة تعريف بإضافة zone_number فقط ----------
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
     unit_code, model, building_number, unit_size, for_non_beneficiary, zone_number)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'status',
    nullif(r->>'booking_date','')::date, nullif(r->>'istisna_date','')::date, nullif(r->>'contract_date','')::date,
    (r->>'snapshot_date')::date,
    r->>'unit_code', r->>'model', r->>'building_number', nullif(r->>'unit_size','')::numeric,
    (r->>'for_non_beneficiary')::boolean, r->>'zone_number'
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- admin_upsert_blocked_mirror — إعادة تعريف بإضافة zone_number فقط ----------
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
     price, moh_price, unit_code, model, snapshot_date, building_number, unit_size, for_non_beneficiary, zone_number)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'unit_code', r->>'model',
    (r->>'snapshot_date')::date, r->>'building_number', nullif(r->>'unit_size','')::numeric,
    (r->>'for_non_beneficiary')::boolean, r->>'zone_number'
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;
