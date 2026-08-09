-- ============================================================
-- SalesPlace — إصلاح: admin_upsert_allocation_mirror لا تكتب unit_code/model
-- ============================================================
-- السبب: هذه الدالة انكُتبت قبل إضافة عمودي unit_code وmodel لجدول
-- unit_allocation_mirror (أضيفا لاحقاً عبر unit_support_detail.sql وهذه الجلسة)،
-- فقائمة أعمدة الـ insert لم تكن تتضمنهما إطلاقاً — أي بيانات تُرسَل بهذين
-- الحقلين من العميل كانت تُتجاهَل بصمت، فتبقى NULL لكل الصفوف مهما كانت
-- صحيحة بملف JSON المُرسَل.
--
-- هذا الملف هو نفس نص الدالة الأصلية بالضبط (كما هو مؤكَّد من Supabase مباشرة)
-- مع إضافة عمودي unit_code وmodel فقط لقائمة الإدراج وقائمة الاختيار —
-- لا تغيير آخر على منطق التحقق من الصلاحية أو باقي الأعمدة أو ترتيبها.
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor.
-- ============================================================

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
     unit_code, model)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'status',
    nullif(r->>'booking_date','')::date, nullif(r->>'istisna_date','')::date, nullif(r->>'contract_date','')::date,
    (r->>'snapshot_date')::date,
    r->>'unit_code', r->>'model'
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$
