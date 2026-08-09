-- ============================================================
-- SalesPlace — إدارة المطورين: تقييم شهري (رفع يدوي) + سجل تحديات
-- جدولان جديدان بالكامل — لا يمسّان أي دالة أو جدول موجود حالياً
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- project_dev_eval ----------
-- لقطة شهرية لتقييم كل مشروع (وبالتالي مطوّره) — تُرفع يدوياً من ملف تقرير إدارة
-- المطورين الشهري (نفس صيغة التقييم المرجَّحة الموجودة فعلياً بالملف: 50% تحقيق
-- المستهدف السنوي + 30% مكافأة بيع كامل بالوقت + حتى 10% جداول دفعات + حتى 10%
-- نشاط قنوات البيع). تُستبدل بالكامل مع كل رفعة جديدة (upsert بمفتاح project_id
-- فقط — أحدث رفعة تمثّل الحالة الحالية، لا تراكم تاريخي بهذا الإصدار)
create table if not exists project_dev_eval (
  project_id integer primary key,
  project_code text,
  project_name text,
  developer_name text not null,
  eval_period_label text,          -- مثال: "أغسطس" — من عنوان عمود الهدف بالملف
  monthly_target numeric,
  monthly_achieved numeric,
  monthly_rate numeric,
  reservations_count integer,
  reason_category text,            -- من القائمة الثابتة (أسباب عدم تحقيق المستهدف)
  reason_notes text,                -- النص الحر الطويل بنفس عمود الأسباب بالملف
  last_update_date date,
  escrow_bank text,
  general_offers text,
  mod_offers text,
  sales_staff_count integer,
  broker_present text,             -- نعم / لا / -
  broker_type text,                -- أفراد / شركة / شركة و أفراد / -
  broker_company_names text,
  broker_individual_count integer,
  broker_agreement_status text,
  annual_target numeric,
  annual_achieved numeric,
  score_target_pct numeric,        -- حتى 0.50
  score_time_bonus_pct numeric,    -- 0 أو 0.30
  payment_schedule_count integer,
  score_payment_plans_pct numeric, -- حتى 0.10
  score_channels_pct numeric,      -- حتى 0.10
  score_final_pct numeric,         -- مجموع الأربعة أعلاه
  non_beneficiary_status text,
  updated_at timestamptz not null default now()
);
create index if not exists project_dev_eval_dev_idx on project_dev_eval(developer_name);

alter table project_dev_eval enable row level security;
drop policy if exists project_dev_eval_read on project_dev_eval;
create policy project_dev_eval_read on project_dev_eval for select using (true);

-- مسح كامل قبل كل رفعة جديدة — نفس نمط admin_reset_allocation_mirror الموجود أصلاً
create or replace function admin_reset_dev_eval(p_admin text, p_pass text)
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

  truncate table project_dev_eval;

  return jsonb_build_object('ok', true, 'msg', 'تم مسح تقييم المطورين القديم');
end;
$$;

create or replace function admin_upsert_dev_eval(p_admin text, p_pass text, p_rows jsonb)
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

  insert into project_dev_eval (
    project_id, project_code, project_name, developer_name, eval_period_label,
    monthly_target, monthly_achieved, monthly_rate, reservations_count,
    reason_category, reason_notes, last_update_date, escrow_bank, general_offers,
    mod_offers, sales_staff_count, broker_present, broker_type, broker_company_names,
    broker_individual_count, broker_agreement_status, annual_target, annual_achieved,
    score_target_pct, score_time_bonus_pct, payment_schedule_count, score_payment_plans_pct,
    score_channels_pct, score_final_pct, non_beneficiary_status, updated_at
  )
  select
    (r->>'project_id')::integer, r->>'project_code', r->>'project_name', r->>'developer_name', r->>'eval_period_label',
    (r->>'monthly_target')::numeric, (r->>'monthly_achieved')::numeric, (r->>'monthly_rate')::numeric,
    (r->>'reservations_count')::integer,
    r->>'reason_category', r->>'reason_notes', (r->>'last_update_date')::date, r->>'escrow_bank', r->>'general_offers',
    r->>'mod_offers', (r->>'sales_staff_count')::integer, r->>'broker_present', r->>'broker_type', r->>'broker_company_names',
    (r->>'broker_individual_count')::integer, r->>'broker_agreement_status',
    (r->>'annual_target')::numeric, (r->>'annual_achieved')::numeric,
    (r->>'score_target_pct')::numeric, (r->>'score_time_bonus_pct')::numeric,
    (r->>'payment_schedule_count')::integer, (r->>'score_payment_plans_pct')::numeric,
    (r->>'score_channels_pct')::numeric, (r->>'score_final_pct')::numeric,
    r->>'non_beneficiary_status', now()
  from jsonb_array_elements(p_rows) as r
  where r->>'project_id' is not null
  on conflict (project_id) do update set
    project_code=excluded.project_code, project_name=excluded.project_name, developer_name=excluded.developer_name,
    eval_period_label=excluded.eval_period_label, monthly_target=excluded.monthly_target,
    monthly_achieved=excluded.monthly_achieved, monthly_rate=excluded.monthly_rate,
    reservations_count=excluded.reservations_count, reason_category=excluded.reason_category,
    reason_notes=excluded.reason_notes, last_update_date=excluded.last_update_date,
    escrow_bank=excluded.escrow_bank, general_offers=excluded.general_offers, mod_offers=excluded.mod_offers,
    sales_staff_count=excluded.sales_staff_count, broker_present=excluded.broker_present,
    broker_type=excluded.broker_type, broker_company_names=excluded.broker_company_names,
    broker_individual_count=excluded.broker_individual_count, broker_agreement_status=excluded.broker_agreement_status,
    annual_target=excluded.annual_target, annual_achieved=excluded.annual_achieved,
    score_target_pct=excluded.score_target_pct, score_time_bonus_pct=excluded.score_time_bonus_pct,
    payment_schedule_count=excluded.payment_schedule_count, score_payment_plans_pct=excluded.score_payment_plans_pct,
    score_channels_pct=excluded.score_channels_pct, score_final_pct=excluded.score_final_pct,
    non_beneficiary_status=excluded.non_beneficiary_status, updated_at=now();

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', v_count || ' مشروع');
end;
$$;

-- ---------- dev_challenges ----------
-- سجل تحديات المطورين — يُنشئه ويحدّثه فريق إدارة المطورين مباشرة من التطبيق
-- (وليس رفعاً من ملف)، بأولوية وحالة، مع ملاحظات حرة إضافية وتوثيق الحل عند إغلاقه
create table if not exists dev_challenges (
  id bigint generated always as identity primary key,
  project_id integer,
  project_name text,
  developer_name text not null,
  title text not null,
  description text,
  priority text not null default 'medium',   -- high / medium / low
  status text not null default 'open',       -- open / in_progress / resolved / deferred
  reason_category text,                      -- نفس القائمة الثابتة (اختياري)
  notes text,                                -- ملاحظات إضافية حرة، تُحدَّث مع الوقت
  created_by text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution_notes text,
  updated_at timestamptz not null default now()
);
create index if not exists dev_challenges_dev_idx on dev_challenges(developer_name);
create index if not exists dev_challenges_status_idx on dev_challenges(status);

alter table dev_challenges enable row level security;
drop policy if exists dev_challenges_read on dev_challenges;
create policy dev_challenges_read on dev_challenges for select using (true);

create or replace function dev_challenge_create(
  p_admin text, p_pass text, p_project_id integer, p_project_name text, p_developer_name text,
  p_title text, p_description text, p_priority text, p_reason_category text, p_notes text
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
  if coalesce(trim(p_title),'') = '' or coalesce(trim(p_developer_name),'') = '' then
    return jsonb_build_object('ok', false, 'msg', 'العنوان واسم المطوّر مطلوبان');
  end if;

  insert into dev_challenges (project_id, project_name, developer_name, title, description, priority, reason_category, notes, created_by)
  values (p_project_id, p_project_name, p_developer_name, p_title, p_description,
          coalesce(nullif(p_priority,''),'medium'), p_reason_category, p_notes, p_admin)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'msg', 'تم تسجيل التحدي', 'id', v_id);
end;
$$;

create or replace function dev_challenge_update(
  p_admin text, p_pass text, p_id bigint, p_status text, p_priority text,
  p_notes text, p_resolution_notes text
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

  update dev_challenges set
    status = coalesce(nullif(p_status,''), status),
    priority = coalesce(nullif(p_priority,''), priority),
    notes = coalesce(p_notes, notes),
    resolution_notes = coalesce(p_resolution_notes, resolution_notes),
    resolved_at = case when p_status = 'resolved' and resolved_at is null then now()
                       when p_status is not null and p_status <> 'resolved' then null
                       else resolved_at end,
    updated_at = now()
  where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'msg', 'لم يُعثر على التحدي');
  end if;

  return jsonb_build_object('ok', true, 'msg', 'تم تحديث التحدي');
end;
$$;
