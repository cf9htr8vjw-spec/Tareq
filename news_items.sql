-- ============================================================
-- SalesPlace — شريط أخبار اليوم على الشاشة الرئيسية (news_items)
-- جدول جديد بالكامل — لا يمسّ أي دالة أو جدول موجود حالياً
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

create table if not exists news_items (
  id bigint generated always as identity primary key,
  title text not null,
  category text,                    -- نص حر: اطلاق مشروع / حملة بيعية / اتفاقية / إلخ
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by text
);
create index if not exists news_items_active_idx on news_items (active, created_at desc);

alter table news_items enable row level security;

drop policy if exists news_items_read on news_items;
create policy news_items_read on news_items
  for select using (true);

-- إضافة/تعديل خبر — نفس نمط admin_upsert_project_offers: p_id فارغ = إضافة، غير فارغ = تعديل
create or replace function admin_upsert_news(p_admin text, p_pass text, p_id bigint, p_title text, p_category text, p_active boolean)
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
    insert into news_items (title, category, active, created_by)
    values (p_title, p_category, coalesce(p_active,true), p_admin);
  else
    update news_items set title = p_title, category = p_category, active = coalesce(p_active,true)
    where id = p_id;
  end if;

  return jsonb_build_object('ok', true, 'msg', 'تم الحفظ');
end;
$$;

-- حذف خبر
create or replace function admin_delete_news(p_admin text, p_pass text, p_id bigint)
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

  delete from news_items where id = p_id;

  return jsonb_build_object('ok', true, 'msg', 'تم الحذف');
end;
$$;
