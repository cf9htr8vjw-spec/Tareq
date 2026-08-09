-- ============================================================
-- SalesPlace — بيانات الدعم الدقيقة على مستوى الوحدة (unit_support_detail)
-- + عمود unit_code الجديد على unit_allocation_mirror الموجود
-- إضافات بالكامل — لا يمسّان أي دالة أو جدول موجود حالياً
-- (admin_sync_unit_status، admin_upsert_allocation_mirror، إلخ تبقى كما هي بلا أي تغيير)
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

create extension if not exists pgcrypto;

-- عمود إضافي على الجدول الموجود unit_allocation_mirror — المعرّف الفريد للوحدة (unit_code)
-- كما يرد بملف التخصيص اليومي؛ يُمكِّن ربط الوحدة الحيّة المختارة من المنتقي بسجل دعمها
-- الدقيق أدناه، بدل الاكتفاء بمتوسط الدعم على مستوى النوع
alter table unit_allocation_mirror add column if not exists unit_code text;
create index if not exists unit_allocation_mirror_unit_code_idx on unit_allocation_mirror(unit_code);

-- ---------- unit_support_detail ----------
-- دعم كل وحدة تحديداً (دعم عيني، خصم بنية تحتية بسيطة، خصم قسط ميسّر، خصم مراحل) من ملف
-- بيانات الدعومات التفصيلي — كل هذه القيم مضمَّنة أصلاً بسعر الوزارة (moh_price) المعروض،
-- تماماً كمنطق SUPP الحالي على مستوى المشروع/النوع (متوسط)، لكن هنا دقيقة لكل وحدة بعينها
create table if not exists unit_support_detail (
  unit_code text primary key,
  project_id integer,              -- يطابق id المشروع بكتالوج التطبيق؛ فارغ لو تعذّرت المطابقة بالاسم
  project_code text,
  project_name text,
  unit_type text,
  unit_size numeric,
  living_area numeric,
  in_kind numeric not null default 0,              -- قيمة الدعم العيني
  infra_simple numeric not null default 0,          -- قيمة خصم البنية التحتية البسيطة
  installment_discount numeric not null default 0,  -- قيمة خصم القسط الميسّر
  phase_discount numeric not null default 0,        -- قيمة خصم المراحل (حالياً الفرسان فقط)
  moh_price numeric,
  full_price numeric,
  total_support numeric not null default 0,
  updated_at timestamptz not null default now()
);
create index if not exists unit_support_detail_project_idx on unit_support_detail(project_id);
create index if not exists unit_support_detail_project_code_idx on unit_support_detail(project_code);

alter table unit_support_detail enable row level security;

drop policy if exists unit_support_detail_read on unit_support_detail;
create policy unit_support_detail_read on unit_support_detail
  for select using (true);

-- مسح كامل قبل كل رفعة جديدة — نفس نمط admin_reset_allocation_mirror الموجود أصلاً، لمنع
-- بقاء وحدات قديمة (بيعت/أُزيلت من الملف) بسجلات دعم يتيمة لا تُحدَّث أبداً
create or replace function admin_reset_unit_support_detail(p_admin text, p_pass text)
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

  truncate table unit_support_detail;

  return jsonb_build_object('ok', true, 'msg', 'تم مسح بيانات دعم الوحدات القديمة');
end;
$$;

create or replace function admin_upsert_unit_support_detail(p_admin text, p_pass text, p_rows jsonb)
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

  insert into unit_support_detail (
    unit_code, project_id, project_code, project_name, unit_type, unit_size, living_area,
    in_kind, infra_simple, installment_discount, phase_discount, moh_price, full_price, total_support, updated_at
  )
  select
    r->>'unit_code', (r->>'project_id')::integer, r->>'project_code', r->>'project_name',
    r->>'unit_type', (r->>'unit_size')::numeric, (r->>'living_area')::numeric,
    coalesce((r->>'in_kind')::numeric,0), coalesce((r->>'infra_simple')::numeric,0),
    coalesce((r->>'installment_discount')::numeric,0), coalesce((r->>'phase_discount')::numeric,0),
    (r->>'moh_price')::numeric, (r->>'full_price')::numeric, coalesce((r->>'total_support')::numeric,0), now()
  from jsonb_array_elements(p_rows) as r
  where r->>'unit_code' is not null
  on conflict (unit_code) do update set
    project_id = excluded.project_id, project_code = excluded.project_code, project_name = excluded.project_name,
    unit_type = excluded.unit_type, unit_size = excluded.unit_size, living_area = excluded.living_area,
    in_kind = excluded.in_kind, infra_simple = excluded.infra_simple,
    installment_discount = excluded.installment_discount, phase_discount = excluded.phase_discount,
    moh_price = excluded.moh_price, full_price = excluded.full_price, total_support = excluded.total_support,
    updated_at = now();

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', v_count || ' وحدة');
end;
$$;
