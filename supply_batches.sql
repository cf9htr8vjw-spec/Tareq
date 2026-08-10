-- ============================================================
-- SalesPlace — نظام Batches بشاشة "توزيع المعروض": تجميع مبانٍ مختارة (من مشروع أو أكثر)
-- تحت اسم وملاحظات، لتنظيم صفقات البيع للمستثمرين (مثال: batch "t95" لمبانٍ من مشاريع
-- ٥-٩٥ مخصَّصة لمستثمرين معيَّنين). جدولان جديدان بالكامل — لا يمسّان أي بيانات موجودة.
--
-- القيم (avail_count/avail_value/blocked_count/blocked_value) تُخزَّن كـ"لقطة" وقت الإضافة
-- للـbatch، لا حيّة عند كل عرض — القصد تجميد الأرقام المعروضة على المستثمر وقت اقتراح
-- الصفقة، بدل تغيّرها بصمت لاحقاً مع كل تحديث مخزون.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor.
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists supply_batches (
  id bigint generated always as identity primary key,
  name text not null,
  notes text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table supply_batches enable row level security;
drop policy if exists supply_batches_read on supply_batches;
create policy supply_batches_read on supply_batches for select using (true);

create table if not exists supply_batch_buildings (
  id bigint generated always as identity primary key,
  batch_id bigint not null references supply_batches(id) on delete cascade,
  project_id integer not null,
  project_name text,
  building_number text not null,
  avail_count integer not null default 0,
  avail_value numeric not null default 0,
  blocked_count integer not null default 0,
  blocked_value numeric not null default 0,
  added_by text,
  added_at timestamptz not null default now(),
  unique (batch_id, project_id, building_number)
);
create index if not exists supply_batch_buildings_batch_idx on supply_batch_buildings(batch_id);
alter table supply_batch_buildings enable row level security;
drop policy if exists supply_batch_buildings_read on supply_batch_buildings;
create policy supply_batch_buildings_read on supply_batch_buildings for select using (true);

-- إنشاء/تعديل batch — p_id فارغ = جديد، موجود = تحديث الاسم/الملاحظات
create or replace function supply_batch_upsert(p_admin text, p_pass text, p_id bigint, p_name text, p_notes text)
returns jsonb
language plpgsql
security definer
as $function$
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
  if p_name is null or trim(p_name) = '' then
    return jsonb_build_object('ok', false, 'msg', 'اسم الـBatch مطلوب');
  end if;

  if p_id is null then
    insert into supply_batches (name, notes, created_by) values (trim(p_name), p_notes, p_admin)
    returning id into v_id;
  else
    update supply_batches set name=trim(p_name), notes=p_notes, updated_at=now() where id=p_id
    returning id into v_id;
  end if;

  return jsonb_build_object('ok', true, 'msg', 'تم الحفظ', 'id', v_id);
end;
$function$;

-- إضافة/تحديث مبنى داخل batch — upsert بمفتاح (batch_id, project_id, building_number)،
-- يحفظ لقطة الأرقام وقت الإضافة، ويحدِّث updated_at للـbatch نفسه
create or replace function supply_batch_add_building(
  p_admin text, p_pass text, p_batch_id bigint, p_project_id integer, p_project_name text,
  p_building_number text, p_avail_count integer, p_avail_value numeric,
  p_blocked_count integer, p_blocked_value numeric
)
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

  insert into supply_batch_buildings
    (batch_id, project_id, project_name, building_number, avail_count, avail_value, blocked_count, blocked_value, added_by, added_at)
  values
    (p_batch_id, p_project_id, p_project_name, p_building_number,
     coalesce(p_avail_count,0), coalesce(p_avail_value,0), coalesce(p_blocked_count,0), coalesce(p_blocked_value,0),
     p_admin, now())
  on conflict (batch_id, project_id, building_number) do update set
    avail_count = excluded.avail_count, avail_value = excluded.avail_value,
    blocked_count = excluded.blocked_count, blocked_value = excluded.blocked_value,
    added_by = excluded.added_by, added_at = now();

  update supply_batches set updated_at = now() where id = p_batch_id;

  return jsonb_build_object('ok', true, 'msg', 'أُضيف المبنى للـBatch');
end;
$function$;

create or replace function supply_batch_remove_building(p_admin text, p_pass text, p_row_id bigint)
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

  delete from supply_batch_buildings where id = p_row_id;
  return jsonb_build_object('ok', true, 'msg', 'أُزيل المبنى من الـBatch');
end;
$function$;

create or replace function supply_batch_delete(p_admin text, p_pass text, p_batch_id bigint)
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

  delete from supply_batches where id = p_batch_id;
  return jsonb_build_object('ok', true, 'msg', 'تم حذف الـBatch');
end;
$function$;
