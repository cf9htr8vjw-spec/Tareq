-- ============================================================
-- SalesPlace — شاشة المبيعات الحيّة: حذف سحب خاطئ
-- دالة جديدة فقط (نفس تعريفها بـ live_board.sql) — لا تمسّ أي بيانات عند تشغيلها.
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor، ثم من الشاشة: زر «رفع سحب جديد»
-- ← «↶ حذف آخر سحب».
-- ============================================================

-- حذف سحب كامل بوقته (مثلاً ملف رُفع بفلتر تاريخ خاطئ بداشبورد NHC) — يتطلّب صلاحية أدمن فعلية
create or replace function admin_delete_live_snapshot(p_admin text, p_pass text, p_snapshot_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  delete from live_project_snapshots where snapshot_at = p_snapshot_at;
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُذف '||v_count||' صفاً', 'count', v_count);
end;
$$;
