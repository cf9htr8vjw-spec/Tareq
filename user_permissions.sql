-- ============================================================
-- SalesPlace — نطاق الصلاحيات لكل مستخدم (permissions on app_users)
-- تعديل إضافي فقط — لا يمسّ أي دالة أو جدول موجود حالياً
-- (login الأصلية، admin_list_users الأصلية، إلخ تبقى كما هي بلا أي تغيير)
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- تصحيح: كلمات المرور بجدول app_users مشفّرة bcrypt بعمود pass_hash (لا يوجد عمود password
-- نصي) — التحقق يتم عبر crypt() من امتداد pgcrypto بدل المقارنة المباشرة
-- ============================================================

create extension if not exists pgcrypto;

-- عمود جديد على app_users — القيمة الافتراضية "الكل مسموح" حتى لا يُحجب أي
-- مستخدم حالي عن أي بند فجأة؛ الأدمن يضيّق الصلاحيات لاحقاً من لوحة الإدارة
alter table app_users
  add column if not exists permissions jsonb not null default
  '{"dest":true,"search":true,"deal":true,"cmp":true,"calc":true,"sales":true}'::jsonb;

-- يسجّل أول مرة أنهى فيها المستخدم الجولة التعريفية — تُقرأ من أي جهاز يدخل منه
-- لاحقاً حتى لا تظهر المسجّات الإرشادية مجدداً لمستخدم سبق له الدخول
alter table app_users
  add column if not exists onboarded_at timestamptz;

-- دالة إدارية جديدة: عرض المستخدمين مع صلاحياتهم
-- (بديل عرض إضافي — لا تمسّ admin_list_users الأصلية ولا تحذفها)
create or replace function admin_list_users_v2(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
  v_admin boolean;
  v_rows jsonb;
begin
  select true, coalesce(is_admin,false) into v_ok, v_admin
  from app_users
  where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;
  if v_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'username', username, 'full_name', full_name, 'is_admin', is_admin,
    'is_active', is_active, 'last_login', last_login,
    'permissions', coalesce(permissions, '{"dest":true,"search":true,"deal":true,"cmp":true,"calc":true,"sales":true}'::jsonb)
  ) order by username), '[]'::jsonb)
  into v_rows
  from app_users;

  return jsonb_build_object('ok', true, 'users', v_rows);
end;
$$;

-- دالة إدارية جديدة: تعديل صلاحيات مستخدم معيّن (checkbox لكل بند بالقائمة)
create or replace function admin_set_permissions(p_admin text, p_pass text, p_target text, p_permissions jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
  v_admin boolean;
begin
  select true, coalesce(is_admin,false) into v_ok, v_admin
  from app_users
  where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;
  if v_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير');
  end if;

  update app_users set permissions = p_permissions where username = p_target;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'المستخدم غير موجود');
  end if;

  return jsonb_build_object('ok', true, 'msg', 'تم تحديث الصلاحيات');
end;
$$;

-- دالة جديدة يستدعيها المستخدم نفسه بعد تسجيل الدخول لجلب صلاحياته فقط
-- (لا تكشف بيانات أي مستخدم آخر — نفس بيانات الدخول التي تحقق منها login أصلاً)
create or replace function get_my_permissions(p_user text, p_pass text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_perm jsonb;
  v_admin boolean;
  v_found boolean;
  v_onboarded boolean;
begin
  select coalesce(permissions, '{"dest":true,"search":true,"deal":true,"cmp":true,"calc":true,"sales":true}'::jsonb),
         coalesce(is_admin,false), true, (onboarded_at is not null)
  into v_perm, v_admin, v_found, v_onboarded
  from app_users
  where username = p_user and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;

  if v_found is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  -- المدير يرى كل بنود القائمة دائماً بغض النظر عن العمود
  if v_admin then
    v_perm := '{"dest":true,"search":true,"deal":true,"cmp":true,"calc":true,"sales":true}'::jsonb;
  end if;

  return jsonb_build_object('ok', true, 'permissions', v_perm, 'onboarded', coalesce(v_onboarded,false));
end;
$$;

-- دالة جديدة يستدعيها العميل بعد إغلاق الجولة التعريفية لأول مرة (تخطٍّ أو إنهاء)
create or replace function mark_onboarded(p_user text, p_pass text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
begin
  select true into v_ok from app_users
  where username = p_user and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  update app_users set onboarded_at = coalesce(onboarded_at, now())
  where username = p_user and pass_hash = crypt(p_pass, pass_hash);

  return jsonb_build_object('ok', true);
end;
$$;
