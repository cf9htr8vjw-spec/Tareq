-- ============================================================
-- SalesPlace — محرّك تقييم مطورين قابل للتخصيص (معايير + أوزان قابلة للتعديل)
-- + إدخال تقييم دوري (شهري/سنوي) لكل مطوّر ومشروع + سجل زمني (لا يُستبدل بالكامل)
-- جدولان جديدان بالكامل — لا يمسّان project_dev_eval ولا dev_challenges ولا أي
-- دالة/جدول آخر موجود حالياً (كلها تبقى تعمل كما هي — رفع الملف الشهري بالجملة
-- بقي كما هو كمصدر بيانات وصفي: بنوك الضمان، الوسطاء، الأسباب النصية...)
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor (بعد developer_management.sql)
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- dev_eval_criteria ----------
-- تعريف معايير التقييم وأوزانها — قابلة للتعديل الكامل من شاشة "المعايير" بالتطبيق.
-- scope: 'project' (يُدخَل لكل مشروع بعينه) أو 'developer' (يخصّ المطوّر عموماً، غير
-- مرتبط بمشروع). source: 'auto' يُحتسَب حياً من بيانات المبيعات الفعلية (مستهدف/محقق
-- من sales_targets + get_project_totals)، 'manual' يُدخله فريق إدارة المطورين يدوياً.
create table if not exists dev_eval_criteria (
  id bigint generated always as identity primary key,
  scope text not null check (scope in ('developer','project')),
  code text not null,
  label text not null,
  max_weight_pct numeric not null default 0,
  source text not null default 'manual' check (source in ('auto','manual')),
  active boolean not null default true,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (scope, code)
);
alter table dev_eval_criteria enable row level security;
drop policy if exists dev_eval_criteria_read on dev_eval_criteria;
create policy dev_eval_criteria_read on dev_eval_criteria for select using (true);

-- ---------- dev_eval_scores ----------
-- قيمة كل معيار لكل مشروع/مطوّر لكل فترة (شهر أو سنة) — سجل زمني تراكمي (لا يُستبدَل
-- بالكامل مع كل إدخال، بعكس project_dev_eval)، upsert فقط على نفس الفترة/المعيار.
-- القيمة المخزَّنة هي "المساهمة الموزونة" (0 إلى max_weight_pct لذلك المعيار) بنفس
-- منطق ملف التقييم الأصلي — التقييم النهائي لفترة معينة = مجموع كل معاييرها النشطة.
create table if not exists dev_eval_scores (
  id bigint generated always as identity primary key,
  scope text not null check (scope in ('developer','project')),
  project_id integer,
  developer_name text not null,
  period_type text not null check (period_type in ('month','year')),
  period_value text not null,          -- '2026-08' لشهري، '2026' لسنوي
  criterion_id bigint not null references dev_eval_criteria(id),
  score_pct numeric not null default 0,
  notes text,
  entered_by text,
  entered_at timestamptz not null default now()
);
-- UNIQUE (...) عادية لا تقبل تعبيراً كـ coalesce() كأحد أعمدتها — استخدام فهرس فريد
-- على التعبير بدل قيد UNIQUE هو الصيغة الصحيحة، وON CONFLICT بالدالة أدناه يطابقه تماماً
create unique index if not exists dev_eval_scores_uk on dev_eval_scores
  (scope, coalesce(project_id,-1), developer_name, period_type, period_value, criterion_id);
create index if not exists dev_eval_scores_lookup_idx on dev_eval_scores(scope, developer_name, period_type, period_value);
create index if not exists dev_eval_scores_project_idx on dev_eval_scores(project_id);

alter table dev_eval_scores enable row level security;
drop policy if exists dev_eval_scores_read on dev_eval_scores;
create policy dev_eval_scores_read on dev_eval_scores for select using (true);

-- إدارة المعايير (إضافة/تعديل) — id فارغ = إضافة جديدة، id موجود = تحديث
create or replace function admin_upsert_dev_eval_criterion(
  p_admin text, p_pass text, p_id bigint, p_scope text, p_code text, p_label text,
  p_max_weight_pct numeric, p_source text, p_active boolean, p_sort_order integer
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok boolean;
  v_id bigint;
begin
  select true into v_ok from app_users
  where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;
  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  if p_id is null then
    insert into dev_eval_criteria (scope, code, label, max_weight_pct, source, active, sort_order, updated_at)
    values (p_scope, p_code, p_label, p_max_weight_pct, p_source, coalesce(p_active,true), coalesce(p_sort_order,0), now())
    returning id into v_id;
  else
    update dev_eval_criteria set
      scope=p_scope, code=p_code, label=p_label, max_weight_pct=p_max_weight_pct,
      source=p_source, active=coalesce(p_active,true), sort_order=coalesce(p_sort_order,0), updated_at=now()
    where id = p_id
    returning id into v_id;
  end if;

  return jsonb_build_object('ok', true, 'msg', 'تم الحفظ', 'id', v_id);
end;
$$;

-- تسجيل قيمة معيار واحد لفترة معيّنة — يُستدعى مرة لكل معيار عند حفظ نموذج التقييم
create or replace function dev_eval_score_upsert(
  p_admin text, p_pass text, p_scope text, p_project_id integer, p_developer_name text,
  p_period_type text, p_period_value text, p_criterion_id bigint, p_score_pct numeric, p_notes text
)
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

  insert into dev_eval_scores (scope, project_id, developer_name, period_type, period_value, criterion_id, score_pct, notes, entered_by, entered_at)
  values (p_scope, p_project_id, p_developer_name, p_period_type, p_period_value, p_criterion_id, coalesce(p_score_pct,0), p_notes, p_admin, now())
  on conflict (scope, coalesce(project_id,-1), developer_name, period_type, period_value, criterion_id)
  do update set score_pct = excluded.score_pct, notes = excluded.notes, entered_by = excluded.entered_by, entered_at = now();

  return jsonb_build_object('ok', true, 'msg', 'تم حفظ التقييم');
end;
$$;

-- ============================================================
-- تعبئة أولية للمعايير — نقطة بداية قابلة للتعديل الكامل من شاشة "المعايير" بالتطبيق.
-- معايير المشروع الأربعة مطابقة لملف التقرير الشهري الأصلي (تحقيق المستهدف الآن auto
-- من بيانات المبيعات الفعلية بدل الإدخال اليدوي، الباقي يبقى يدوياً). معايير المطوّر
-- العام قائمة مبدئية فقط (التزام تعاقدي/تواصل/دعم تسويقي) — عدِّلها لتطابق معاييركم
-- الفعلية بنفس الشاشة، الأوزان والأسماء كلها قابلة للتغيير لاحقاً.
-- ============================================================
insert into dev_eval_criteria (scope, code, label, max_weight_pct, source, sort_order) values
  ('project', 'target_achievement', 'تحقيق المستهدف', 0.50, 'auto', 1),
  ('project', 'time_bonus', 'مكافأة البيع الكامل ضمن الوقت المتوقَّع', 0.30, 'manual', 2),
  ('project', 'payment_plans', 'تنوّع جداول الدفعات', 0.10, 'manual', 3),
  ('project', 'channels', 'نشاط قنوات البيع', 0.10, 'manual', 4),
  ('developer', 'dev_target_achievement', 'تحقيق المستهدف الإجمالي (كل المشاريع)', 0.50, 'auto', 1),
  ('developer', 'dev_commitment', 'الالتزام التعاقدي والتسليم', 0.20, 'manual', 2),
  ('developer', 'dev_communication', 'جودة التواصل والاستجابة', 0.15, 'manual', 3),
  ('developer', 'dev_marketing', 'دعم التسويق والحملات', 0.15, 'manual', 4)
on conflict (scope, code) do nothing;
