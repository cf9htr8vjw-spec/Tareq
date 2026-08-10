-- ============================================================
-- SalesPlace — الوحدات المحجوبة (غير المتاحة للبيع إطلاقاً)
-- جدولان جديدان بالكامل، إضافيان فقط — لا يمسّان unit_allocation_mirror ولا أي
-- جدول/دالة أخرى موجودة حالياً (admin_upsert_allocation_mirror، admin_sync_unit_status،
-- project_model_stats، project_istisna_stats... كلها تبقى تعمل كما هي بلا أي تغيير).
--
-- unit_blocked_mirror  : مرآة خام كاملة، صف واحد لكل وحدة محجوبة — نفس نمط
--                         unit_allocation_mirror، تُمسح وتُعاد تعبئتها بالكامل مع كل رفعة.
-- project_blocked_stats: تجميع خفيف (عدد فقط لكل مشروع) — تقرأه البطاقات/شاشة تفاصيل
--                         المشروع بدل مسح جدول عشرات الآلاف من الصفوف بكل عرض شاشة،
--                         نفس نمط project_istisna_stats/project_model_stats تماماً.
--
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor.
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- unit_blocked_mirror ----------
create table if not exists unit_blocked_mirror (
  id bigint generated always as identity primary key,
  project_name text,
  project_id integer,
  city text,
  sector text,
  dev_kind text,
  unit_type text,
  beds integer,
  price numeric,
  moh_price numeric,
  unit_code text,
  model text,
  snapshot_date date not null default current_date
);
create index if not exists unit_blocked_mirror_project_idx on unit_blocked_mirror(project_id);
create index if not exists unit_blocked_mirror_unit_code_idx on unit_blocked_mirror(unit_code);

alter table unit_blocked_mirror enable row level security;
drop policy if exists unit_blocked_mirror_read on unit_blocked_mirror;
create policy unit_blocked_mirror_read on unit_blocked_mirror for select using (true);

-- مسح كامل قبل كل رفعة جديدة — يتطلّب صلاحية is_admin فعلية (وليس فقط بيانات دخول
-- صحيحة)، بنفس نمط admin_reset_allocation_mirror/admin_upsert_allocation_mirror
-- الأصليتين تماماً، لأن هذه عملية استبدال كامل لجدول بيانات خام.
create or replace function admin_reset_blocked_mirror(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_is_admin boolean;
begin
  select is_admin into v_is_admin from public.app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  truncate table public.unit_blocked_mirror;
  return jsonb_build_object('ok', true, 'msg', 'تم المسح');
end;
$function$;

create or replace function admin_upsert_blocked_mirror(p_admin text, p_pass text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from public.app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  insert into public.unit_blocked_mirror
    (project_name, project_id, city, sector, dev_kind, unit_type, beds,
     price, moh_price, unit_code, model, snapshot_date)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'unit_code', r->>'model',
    (r->>'snapshot_date')::date
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- project_blocked_stats ----------
create table if not exists project_blocked_stats (
  project_id integer primary key,
  blocked_count integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table project_blocked_stats enable row level security;
drop policy if exists project_blocked_stats_read on project_blocked_stats;
create policy project_blocked_stats_read on project_blocked_stats for select using (true);

-- تجميع خفيف (عدد الوحدات المحجوبة لكل مشروع) — يُستدعى مرة واحدة بعد كل رفعة كاملة،
-- نفس نمط admin_sync_istisna_stats/admin_sync_model_stats (فحص بيانات دخول فقط، لا
-- يتطلّب is_admin تحديداً، لأنه مجرّد عدّاد عرض وليس استبدال بيانات خام)
create or replace function admin_sync_blocked_stats(p_admin text, p_pass text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
as $function$
declare
  v_ok boolean;
begin
  select true into v_ok from app_users
  where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active,true)
  limit 1;

  if v_ok is not true then
    return jsonb_build_object('ok', false, 'msg', 'بيانات دخول غير صحيحة');
  end if;

  insert into project_blocked_stats (project_id, blocked_count, updated_at)
  select (r->>'project_id')::integer, coalesce((r->>'blocked_count')::integer,0), now()
  from jsonb_array_elements(p_rows) as r
  on conflict (project_id) do update set
    blocked_count = excluded.blocked_count,
    updated_at = now();

  return jsonb_build_object('ok', true, 'msg', 'تم تحديث عدّادات الوحدات المحجوبة');
end;
$function$;
