-- ============================================================
-- SalesPlace — عدد عقود الاستصناع المعلَّقة الحيّ (project_istisna_stats)
-- جدول جديد بالكامل — لا يمسّ أي دالة أو جدول موجود حالياً
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

create extension if not exists pgcrypto;

-- عدد الوحدات "محجوزة" (لم تتحوّل لعقد نهائي بعد) لكنها موقّعة على عقد استصناع —
-- من عمود "تاريخ عقد الاستصناع" بملف التخصيص: أي صف حالته "حجز" وله تاريخ عقد
-- استصناع غير فارغ. يُستبدل بالكامل مع كل تحديث (upsert، لا تراكم).
create table if not exists project_istisna_stats (
  project_id integer primary key,
  istisna_active_count integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table project_istisna_stats enable row level security;

drop policy if exists project_istisna_stats_read on project_istisna_stats;
create policy project_istisna_stats_read on project_istisna_stats
  for select using (true);

create or replace function admin_sync_istisna_stats(p_admin text, p_pass text, p_rows jsonb)
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

  insert into project_istisna_stats (project_id, istisna_active_count, updated_at)
  select (r->>'project_id')::integer, coalesce((r->>'istisna_active_count')::integer,0), now()
  from jsonb_array_elements(p_rows) as r
  on conflict (project_id) do update set
    istisna_active_count = excluded.istisna_active_count,
    updated_at = now();

  return jsonb_build_object('ok', true, 'msg', 'تم تحديث عقود الاستصناع المعلّقة');
end;
$$;
