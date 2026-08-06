-- ============================================================
-- SalesPlace — جدول بنوك التمويل القابل للتعديل من الإدارة (bank_rates)
-- جدول جديد بالكامل — لا يمسّ أي دالة أو جدول موجود حالياً
-- عند تشغيله، يحل محل جدول البنوك الأربعين المضمّن داخل الملف كمصدر حي للتطبيق،
-- لكن الملف يبقى يعمل بالبيانات المضمّنة إن لم يُشغَّل هذا الملف
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

create table if not exists bank_rates (
  id bigint generated always as identity primary key,
  bank_name text not null,
  eligibility_tier text,          -- "مستحق" أو "غير مستحق"
  salary_transfer_tier text,      -- "نعم" أو "لا" (تحويل الراتب)
  rate_pct numeric,               -- نسبة الفائدة السنوية كنسبة مئوية، مثال: 5.25
  note text,
  created_at timestamptz not null default now()
);

alter table bank_rates enable row level security;

drop policy if exists bank_rates_read on bank_rates;
create policy bank_rates_read on bank_rates
  for select using (true);

-- إضافة/تعديل بنك — p_id فارغ = إضافة، غير فارغ = تعديل
create or replace function admin_upsert_bank(p_admin text, p_pass text, p_id bigint,
  p_bank_name text, p_eligibility_tier text, p_salary_transfer_tier text, p_rate_pct numeric, p_note text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
begin
  select true into v_ok from app_users
  where username = p_admin and password = p_pass and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  if p_id is null then
    insert into bank_rates (bank_name, eligibility_tier, salary_transfer_tier, rate_pct, note)
    values (p_bank_name, p_eligibility_tier, p_salary_transfer_tier, p_rate_pct, p_note);
  else
    update bank_rates set bank_name = p_bank_name, eligibility_tier = p_eligibility_tier,
      salary_transfer_tier = p_salary_transfer_tier, rate_pct = p_rate_pct, note = p_note
    where id = p_id;
  end if;

  return jsonb_build_object('ok', true, 'msg', 'تم الحفظ');
end;
$$;

-- حذف بنك
create or replace function admin_delete_bank(p_admin text, p_pass text, p_id bigint)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
begin
  select true into v_ok from app_users
  where username = p_admin and password = p_pass and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  delete from bank_rates where id = p_id;

  return jsonb_build_object('ok', true, 'msg', 'تم الحذف');
end;
$$;
