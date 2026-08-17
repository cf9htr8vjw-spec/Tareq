-- ============================================================
-- SalesPlace — تفعيل الدالة وراء زر "إيقاف/تفعيل" بشاشة إدارة المستخدمين.
-- الواجهة (زر الإيقاف، شارة "موقوف/مفعّل") موجودة أصلاً بالتطبيق. تبيّن أن admin_set_active
-- موجودة فعلاً على القاعدة لكن بنوع إرجاع مختلف عن jsonb (خطأ 42P13 عند محاولة استبدالها
-- مباشرة عبر CREATE OR REPLACE) — لهذا لازم DROP FUNCTION أولاً بنفس التوقيع بالضبط، تماماً
-- كما حصل سابقاً مع get_supply_buildings في ملفات هذه الجلسة.
-- لا تمسّ أي جدول موجود (عمود is_active على app_users موجود أصلاً ويُستخدم في كل دوال
-- الإدارة الأخرى عبر coalesce(is_active,true)).
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor.
-- ============================================================

create extension if not exists pgcrypto;

drop function if exists admin_set_active(text, text, text, boolean);
create or replace function admin_set_active(p_admin text, p_pass text, p_target text, p_active boolean)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
  v_admin boolean;
  v_target_is_admin boolean;
  v_found boolean;
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

  if p_target = p_admin then
    return jsonb_build_object('ok', false, 'msg', 'لا يمكنك إيقاف حسابك أنت نفسه');
  end if;

  select true, coalesce(is_admin,false) into v_found, v_target_is_admin
  from app_users where username = p_target;

  if v_found is not true then
    return jsonb_build_object('ok', false, 'msg', 'المستخدم غير موجود');
  end if;
  if v_target_is_admin and p_active is false then
    return jsonb_build_object('ok', false, 'msg', 'لا يمكن إيقاف حساب مدير آخر من هذه الشاشة');
  end if;

  update app_users set is_active = p_active where username = p_target;

  return jsonb_build_object('ok', true, 'msg', case when p_active then 'تم تفعيل الحساب' else 'تم إيقاف الحساب' end);
end;
$$;
