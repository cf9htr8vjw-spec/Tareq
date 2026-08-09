-- ============================================================
-- SalesPlace — عمود النموذج (model) على unit_allocation_mirror الموجود
-- + دالة تحديث إضافية آمنة (لا تستبدل ولا تلمس admin_upsert_allocation_mirror
--   أو admin_reset_allocation_mirror الأصليتين إطلاقاً — دالة UPDATE منفصلة كلياً)
-- تُستخدم بمنتقي الوحدة البصري الجديد لعرض النموذج (model_1، model_2، ...) لكل وحدة
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

create extension if not exists pgcrypto;

alter table unit_allocation_mirror add column if not exists model text;
create index if not exists unit_allocation_mirror_model_idx on unit_allocation_mirror(project_id, model);

-- دالة UPDATE فقط، مفتاحها unit_code — تُستدعى بعد رفع مرآة التخصيص الرئيسية (بعد
-- admin_reset_allocation_mirror + admin_upsert_allocation_mirror) لتعبئة عمود model
-- للصفوف التي أُدرجت للتو. لا تُدرج ولا تمسح أي صف، فقط تُحدِّث عموداً إضافياً.
create or replace function admin_update_mirror_model(p_admin text, p_pass text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
  v_count integer;
begin
  select true into v_ok from app_users
  where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  with u as (
    select r->>'unit_code' as unit_code, r->>'model' as model
    from jsonb_array_elements(p_rows) as r
    where r->>'unit_code' is not null and r->>'model' is not null
  )
  update unit_allocation_mirror m set model = u.model
  from u where m.unit_code = u.unit_code;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', v_count || ' وحدة');
end;
$$;
