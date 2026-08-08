-- ============================================================
-- SalesPlace — إحصاءات النماذج الحيّة (project_model_stats) وشريحة المعروض
-- (project_segment_stats) — من ملف التخصيص اليومي، عمودا model وtarget_segments
-- جدولان جديدان بالكامل — لا يمسّان أي دالة أو جدول موجود حالياً
-- (admin_sync_unit_status، admin_upsert_allocation_mirror، إلخ تبقى كما هي بلا أي تغيير)
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- project_model_stats ----------
-- عدد الوحدات الحيّ لكل نموذج تصميم (model_1, model_2, ...) بكل مشروع، مُصنَّف
-- بحالة الحجز — يُستبدل بالكامل مع كل تحديث (upsert، لا تراكم). المواصفات
-- (النوع/الغرف/المساحة/السعر) تبقى من كتالوج التصميم الثابت المضمّن بالتطبيق —
-- هذا الجدول للأعداد المتحركة فقط (متاح/محجوز/متعاقَد)
create table if not exists project_model_stats (
  project_id integer not null,
  model text not null,
  avail_count integer not null default 0,
  reserved_count integer not null default 0,
  contracted_count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (project_id, model)
);

alter table project_model_stats enable row level security;

drop policy if exists project_model_stats_read on project_model_stats;
create policy project_model_stats_read on project_model_stats
  for select using (true);

create or replace function admin_sync_model_stats(p_admin text, p_pass text, p_rows jsonb)
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

  insert into project_model_stats (project_id, model, avail_count, reserved_count, contracted_count, updated_at)
  select
    (r->>'project_id')::integer, r->>'model',
    coalesce((r->>'avail_count')::integer,0), coalesce((r->>'reserved_count')::integer,0),
    coalesce((r->>'contracted_count')::integer,0), now()
  from jsonb_array_elements(p_rows) as r
  on conflict (project_id, model) do update set
    avail_count = excluded.avail_count,
    reserved_count = excluded.reserved_count,
    contracted_count = excluded.contracted_count,
    updated_at = now();

  return jsonb_build_object('ok', true, 'msg', 'تم تحديث إحصاءات النماذج');
end;
$$;

-- ---------- project_segment_stats ----------
-- نسبة المستفيدين/غير المستفيدين بالوحدات المعروضة لكل مشروع، من عمود
-- target_segments (أي قيمة غير {beneficiary} فقط — أي تتضمن non_bene أو company —
-- تُحتسب "غير مستفيدين"). صف واحد لكل مشروع، يُستبدل بالكامل مع كل تحديث.
create table if not exists project_segment_stats (
  project_id integer primary key,
  beneficiary_count integer not null default 0,
  non_beneficiary_count integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table project_segment_stats enable row level security;

drop policy if exists project_segment_stats_read on project_segment_stats;
create policy project_segment_stats_read on project_segment_stats
  for select using (true);

create or replace function admin_sync_segment_stats(p_admin text, p_pass text, p_rows jsonb)
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

  insert into project_segment_stats (project_id, beneficiary_count, non_beneficiary_count, updated_at)
  select
    (r->>'project_id')::integer,
    coalesce((r->>'beneficiary_count')::integer,0), coalesce((r->>'non_beneficiary_count')::integer,0), now()
  from jsonb_array_elements(p_rows) as r
  on conflict (project_id) do update set
    beneficiary_count = excluded.beneficiary_count,
    non_beneficiary_count = excluded.non_beneficiary_count,
    updated_at = now();

  return jsonb_build_object('ok', true, 'msg', 'تم تحديث شريحة المعروض');
end;
$$;
