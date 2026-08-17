-- ============================================================
-- SalesPlace — تسجيل وقت الخروج (إلى جانب وقت الدخول الموجود أصلاً)، وإضافة تنظيف دوري
-- لسجل الدخول/الخروج (حذف كل ما هو أقدم من N يوم، افتراضياً 3 أيام، عبر زر بشاشة سجل الدخول).
--
-- تسجيل الخروج مصدر منفصل بالكامل (جدول جديد + دالة جديدة) — لا يمسّ ولا يعيد تعريف
-- admin_login_log الأصلية (دالة قديمة سابقة لهذا المستودع، غير موجودة بأي ملف SQL هنا، لذا
-- تعديلها مباشرة كان يحمل خطر فقدان منطق موجود لا نراه). العميل يدمج الآن سجلّي الدخول
-- والخروج بعرض واحد بنفسه.
--
-- ⚠ admin_clear_login_log تحذف من جدول اسمه login_log — هذا اسم متوقَّع بناءً على تسمية
-- الدالة admin_login_log، وليس مؤكَّداً (الجدول الأصلي غير موجود بأي ملف هنا). لو رجع خطأ
-- "relation login_log does not exist" عند تشغيل هذا الملف، ابعث لي رسالة الخطأ ومعها الاسم
-- الصحيح للجدول (تقدر تشوفه من Database → Tables بلوحة Supabase) وأصححها فوراً — بالضبط
-- نفس ما صار مع admin_set_active قبل قليل.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor.
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists login_log_logout (
  id bigint generated always as identity primary key,
  username text not null,
  at timestamptz not null default now()
);
create index if not exists login_log_logout_at_idx on login_log_logout(at);
alter table login_log_logout enable row level security;
drop policy if exists login_log_logout_read on login_log_logout;
create policy login_log_logout_read on login_log_logout for select using (true);

-- يستدعيها العميل عند الضغط على زر "تسجيل الخروج" أو عند الخروج التلقائي بسبب الخمول
create or replace function record_logout(p_user text, p_pass text)
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

  insert into login_log_logout(username, at) values (p_user, now());
  return jsonb_build_object('ok', true);
end;
$$;

-- زر "مسح الأقدم من 3 أيام" بشاشة سجل الدخول — يحذف نهائياً من الجدولين معاً
create or replace function admin_clear_login_log(p_admin text, p_pass text, p_days integer default 3)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_admin boolean;
  v_deleted_login int;
  v_deleted_logout int;
begin
  select coalesce(is_admin,false) into v_admin from app_users
  where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;
  if v_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير');
  end if;

  delete from login_log where at < now() - (p_days || ' days')::interval;
  get diagnostics v_deleted_login = row_count;

  delete from login_log_logout where at < now() - (p_days || ' days')::interval;
  get diagnostics v_deleted_logout = row_count;

  return jsonb_build_object(
    'ok', true,
    'msg', 'حُذف '||v_deleted_login||' سجل دخول و'||v_deleted_logout||' سجل خروج أقدم من '||p_days||' أيام',
    'deleted_login', v_deleted_login, 'deleted_logout', v_deleted_logout
  );
end;
$$;
