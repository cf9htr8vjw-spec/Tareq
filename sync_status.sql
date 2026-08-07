-- ============================================================
-- SalesPlace — تتبّع آخر تحديث فعلي لبيانات المخزون (sync_status)
-- تعديل إضافي بالكامل — لا يمسّ أي دالة أو جدول موجود حالياً
-- (admin_sync_unit_status، admin_upsert_allocation_mirror، إلخ تبقى كما هي بلا أي تغيير)
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- تصحيح: كلمات المرور بجدول app_users مشفّرة bcrypt بعمود pass_hash (لا يوجد عمود password
-- نصي) — التحقق يتم عبر crypt() من امتداد pgcrypto بدل المقارنة المباشرة
-- ============================================================

create extension if not exists pgcrypto;

-- صف واحد فقط دائماً — آخر مرة اكتمل فيها رفع ملف التخصيص اليومي بنجاح
create table if not exists sync_status (
  id smallint primary key default 1 check (id = 1),
  last_synced_at timestamptz,
  updated_by text
);
insert into sync_status (id, last_synced_at, updated_by)
  values (1, null, null)
  on conflict (id) do nothing;

alter table sync_status enable row level security;

-- قراءة عامة — كل مستخدم يرى متى آخر تحديث فعلي للبيانات، بصرف النظر عمّن رفعها
drop policy if exists sync_status_read on sync_status;
create policy sync_status_read on sync_status
  for select using (true);

-- الكتابة فقط عبر دالة إدارية (نفس نمط admin_sync_unit_status الموجودة أصلاً) —
-- تُستدعى من التطبيق بعد نجاح رفع ملف التخصيص اليومي بالكامل
create or replace function admin_mark_synced(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
begin
  select true into v_ok from app_users
  where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  update sync_status set last_synced_at = now(), updated_by = p_admin where id = 1;

  return jsonb_build_object('ok', true, 'last_synced_at', now());
end;
$$;
