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
  rate_pct numeric,               -- نسبة الفائدة السنوية كنسبة مئوية، مثال: 5.25 — فارغ إن كانت النسبة نطاقاً وليست رقماً ثابتاً (راجع note)
  note text,
  created_at timestamptz not null default now()
);
create unique index if not exists bank_rates_combo_uk on bank_rates (bank_name, eligibility_tier, salary_transfer_tier);

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
    values (p_bank_name, p_eligibility_tier, p_salary_transfer_tier, p_rate_pct, p_note)
    on conflict (bank_name, eligibility_tier, salary_transfer_tier) do update
      set rate_pct = excluded.rate_pct, note = excluded.note;
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

-- ============================================================
-- تحميل أولي: ٤٠ صفاً من ملف "الجهات التمويلية" المرفق (بتاريخ هذه الجلسة)
-- on conflict يجعل إعادة تشغيل هذا الجزء آمنة (يحدّث بدل التكرار)
-- ============================================================
-- بيانات فعلية من ملف الجهات التمويلية (٤٠ صفاً) — أسعار وشروط بتاريخ رفع الملف
insert into bank_rates (bank_name, eligibility_tier, salary_transfer_tier, rate_pct, note) values
  ('الأهلي', 'مستحق', 'نعم', 4.68, 'عرض %2.99 لمدة 20 سنة 
( مدعوم - متطلب تحويل راتب) لمشاريع محددة'),
  ('الأهلي', 'مستحق', 'لا', 5.18, null),
  ('الأهلي', 'غير مستحق', 'نعم', 5.18, null),
  ('الأهلي', 'غير مستحق', 'لا', 5.68, null),
  ('الراجحي', 'مستحق', 'نعم', null, 'النسبة: 3.77 – 4.65% — **تبدأ من 2.89% لـ 5 سنوات و  2.99% لـ 10 سنوات( مدعوم – غير مدعوم بمتطلب تحويل الراتب) 
للمشاريع الموقعة مع البنك حتى 31 أغسطس 2026
**%2.99 على جميع الفترات   - مركز الاسناد والتصفية ( انفاذ) مدعوم - غير مدعوم حتى 31 ديسمبر 2026'),
  ('الراجحي', 'مستحق', 'لا', null, 'النسبة: 3.77 – 4.65%'),
  ('الراجحي', 'غير مستحق', 'نعم', null, 'النسبة: 3.83 – 4.65%'),
  ('الراجحي', 'غير مستحق', 'لا', null, 'النسبة: 3.83 – 4.65%'),
  ('الرياض', 'مستحق', 'نعم', 4.55, '2% لـ 15سنة (خاص بمنسوبي هيئة الضربية والزكاة والجمارك) 
للمشاريع الموقعة مع البنك حتى 31 أغسطس 2026'),
  ('الرياض', 'مستحق', 'لا', 4.6, null),
  ('الرياض', 'غير مستحق', 'نعم', 4.8, null),
  ('الرياض', 'غير مستحق', 'لا', 5.6, null),
  ('الاستثمار', 'مستحق', 'نعم', 4.16, null),
  ('الاستثمار', 'مستحق', 'لا', null, null),
  ('الاستثمار', 'غير مستحق', 'نعم', 4.16, null),
  ('الاستثمار', 'غير مستحق', 'لا', null, null),
  ('العربي', 'مستحق', 'نعم', 4.49, '(لرواتب الأعلى من 12 ألف) مدعوم - غير مدعوم حتى 30 أغسطس 2026 لمطورين فرعيين و مشاريع  إستراتيجية 
3.55% لـ 5 سنوات
3.75% لـ 10 سنوات
4.05% لـ 15 سنة
4.24% لـ 20 سنة
4.74% لـ 25 سنة
5.04% لـ 30سنة'),
  ('العربي', 'مستحق', 'لا', null, null),
  ('العربي', 'غير مستحق', 'نعم', 4.49, null),
  ('العربي', 'غير مستحق', 'لا', null, null),
  ('الانماء', 'مستحق', 'نعم', 4.57, 'تبدأ من 3% لـ 5 سنوات و 3.75 لـ 20 سنة -  خصم رسوم إدارية 50%
( خاص بمنسوبي وزارة الدفاع (اعتزاز))
حتى 31 ديسمبر 2026'),
  ('الانماء', 'مستحق', 'لا', 5.07, null),
  ('الانماء', 'غير مستحق', 'نعم', 4.57, null),
  ('الانماء', 'غير مستحق', 'لا', 5.07, null),
  ('الأول', 'مستحق', 'نعم', 3.45, null),
  ('الأول', 'مستحق', 'لا', null, null),
  ('الأول', 'غير مستحق', 'نعم', 3.45, null),
  ('الأول', 'غير مستحق', 'لا', null, null),
  ('الجزيرة', 'مستحق', 'نعم', 4.3, null),
  ('الجزيرة', 'مستحق', 'لا', 4.64, null),
  ('الجزيرة', 'غير مستحق', 'نعم', 4.3, null),
  ('الجزيرة', 'غير مستحق', 'لا', 4.64, null),
  ('الفرنسي', 'مستحق', 'نعم', 4.3, 'تبدأ من 3.10% لـ 5 سنوات و4.30% لـ 20 سنة  
خاص بمنسوبي الصحة القابضة
حتى 31 يوليو2026
 4.20% لراتب أعلى من 20 ألف ومحول الراتب'),
  ('الفرنسي', 'مستحق', 'لا', null, null),
  ('الفرنسي', 'غير مستحق', 'نعم', 4.3, null),
  ('الفرنسي', 'غير مستحق', 'لا', null, null),
  ('البلاد', 'مستحق', 'نعم', null, 'النسبة: 3.90 – 3.60%'),
  ('البلاد', 'مستحق', 'لا', null, 'النسبة: 4.69 – 4.39%'),
  ('البلاد', 'غير مستحق', 'نعم', null, 'النسبة: 3.90 – 3.60%'),
  ('البلاد', 'غير مستحق', 'لا', null, 'النسبة: 4.69 – 4.39%')
on conflict (bank_name, eligibility_tier, salary_transfer_tier) do update
  set rate_pct = excluded.rate_pct, note = excluded.note;
