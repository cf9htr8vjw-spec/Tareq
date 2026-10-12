-- ============================================================
-- SalesPlace — شاشة البورصة الحيّة (لقطات داشبورد NHC الساعية)
-- جدول جديد + 3 دوال جديدة بالكامل — لا تمسّ أي جدول أو دالة موجودة حالياً
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

-- ---------- live_project_snapshots ----------
-- كل سحب من داشبورد NHC (ملف Export الساعي) يُحفظ كلقطة كاملة بوقتها ولا يُستبدل:
-- صف لكل مشروع لكل لقطة. الحركة (الفرق منذ آخر سحب ومنذ أول سحب اليوم) تُحسب من
-- مقارنة اللقطات، فهي صحيحة سواء كان عمود العقود بالملف يومياً أم تراكمياً.
create table if not exists live_project_snapshots (
  id bigint generated always as identity primary key,
  batch_id uuid not null,
  snapshot_at timestamptz not null,
  project_name text not null,
  developer_name text,
  city text,
  is_nhc boolean not null default false,
  inventory integer default 0,          -- المخزون
  supply integer default 0,             -- المعروض
  bookings integer default 0,           -- عدد الحجوزات
  available integer default 0,          -- عدد الوحدات المتوفرة
  contracts_nonbene integer default 0,  -- عقود غير المستفيدين
  contracts_cash integer default 0,     -- عقود الشراء النقدي
  contracts_selfbuild integer default 0,-- عقود البناء الذاتي
  contracts_financed integer default 0, -- العقود التمويلية
  contracts_total integer default 0,    -- عدد العقود
  open_units integer default 0,         -- عدد الوحدات المفتوحة
  dev_housing integer default 0         -- إسكان تنموي
);
create index if not exists live_snap_at_idx on live_project_snapshots(snapshot_at);
create index if not exists live_snap_batch_idx on live_project_snapshots(batch_id);
create index if not exists live_snap_proj_idx on live_project_snapshots(project_name, snapshot_at);

alter table live_project_snapshots enable row level security;
drop policy if exists live_project_snapshots_read on live_project_snapshots;
create policy live_project_snapshots_read on live_project_snapshots for select using (true);

-- رفع لقطة: كل الصفوف بنفس snapshot_at وbatch_id — يتطلّب صلاحية أدمن فعلية
create or replace function admin_insert_live_snapshot(p_admin text, p_pass text, p_snapshot_at timestamptz, p_batch_id uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  insert into live_project_snapshots
    (batch_id, snapshot_at, project_name, developer_name, city, is_nhc,
     inventory, supply, bookings, available,
     contracts_nonbene, contracts_cash, contracts_selfbuild, contracts_financed, contracts_total,
     open_units, dev_housing)
  select
    p_batch_id, p_snapshot_at,
    r->>'project_name', r->>'developer_name', r->>'city',
    coalesce((r->>'is_nhc')::boolean, false),
    coalesce((r->>'inventory')::int,0), coalesce((r->>'supply')::int,0),
    coalesce((r->>'bookings')::int,0), coalesce((r->>'available')::int,0),
    coalesce((r->>'contracts_nonbene')::int,0), coalesce((r->>'contracts_cash')::int,0),
    coalesce((r->>'contracts_selfbuild')::int,0), coalesce((r->>'contracts_financed')::int,0),
    coalesce((r->>'contracts_total')::int,0),
    coalesce((r->>'open_units')::int,0), coalesce((r->>'dev_housing')::int,0)
  from jsonb_array_elements(p_rows) r
  where coalesce(r->>'project_name','') <> '';

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- حذف سحب كامل بوقته (مثلاً ملف رُفع بفلتر تاريخ خاطئ بداشبورد NHC) — يتطلّب صلاحية أدمن فعلية
create or replace function admin_delete_live_snapshot(p_admin text, p_pass text, p_snapshot_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_count int;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  delete from live_project_snapshots where snapshot_at = p_snapshot_at;
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُذف '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- إجماليات لقطة معيّنة على ثلاثة نطاقات: الكل / NHC / المطورون
create or replace function live_totals_at(p_at timestamptz)
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_object_agg(scope, t), '{}'::jsonb)
  from (
    select scope, jsonb_build_object(
      'contracts', sum(contracts_total), 'bookings', sum(bookings), 'available', sum(available),
      'supply', sum(supply), 'inventory', sum(inventory),
      'financed', sum(contracts_financed), 'cash', sum(contracts_cash),
      'nonbene', sum(contracts_nonbene), 'selfbuild', sum(contracts_selfbuild),
      'projects_with_contracts', count(*) filter (where contracts_total > 0)
    ) as t
    from (
      select 'all' as scope, * from live_project_snapshots where snapshot_at = p_at
      union all
      select case when is_nhc then 'nhc' else 'dev' end as scope, * from live_project_snapshots where snapshot_at = p_at
    ) s
    group by scope
  ) g;
$$;

-- حزمة الشاشة كاملة في نداء واحد: الأوقات، الإجماليات (آخر لقطة / السابقة / أول لقطة اليوم)،
-- منحنى اليوم لقطةً لقطة، المشاريع التي باعت، وسجل الإشعارات (كل زيادة عقود بين سحبتين اليوم).
-- التجميع اليومي بتوقيت الرياض. "السابقة" محصورة باليوم نفسه — أول سحبة بالصباح لا تُقارَن بآخر
-- سحبة أمس (عمود العقود بالملف يومي، فالمقارنة عبر منتصف الليل تعطي هبوطاً وهمياً).
-- أعمدة قطاع/اسم المشروع من ملف التخصيص نفسه (تُعبّأ مع كل رفع للملف) — يُربط بها قطاع كل مشروع بالشاشة
alter table unit_allocation_mirror add column if not exists file_sector text;
alter table unit_allocation_mirror add column if not exists file_project_name text;
-- فهارس لقراءات الشاشة السريعة (ربط مشروع/مدينة بقطاعها، وعقود السنة) — بلا تغيير بأي بيانات
create index if not exists uam_file_project_idx on unit_allocation_mirror(file_project_name);
create index if not exists uam_city_idx on unit_allocation_mirror(city);
create index if not exists uam_contract_date_idx on unit_allocation_mirror(contract_date) where contract_date is not null;

-- ---------- القطاع الموحّد للشاشة ----------
-- قطاع ملف التخصيص بأي تهجئة (الأوسط/الاوسط/الوسطى/قطاع الأوسط/Central...) يُوحَّد لأحد القطاعات
-- الثلاثة؛ قيمة لا تُعرف بالملف (فارغة أو اسم آخر) → قطاع التطبيق لنفس الوحدة → وإلا "غير محدد".
create or replace function tv_norm_sector(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null then null
    when p like '%وسط%' or lower(p) like '%central%' then 'الأوسط'
    when p like '%غرب%' or lower(p) like '%west%' then 'الغربي'
    when p like '%شرق%' or lower(p) like '%east%' then 'الشرقي'
    else null end
$$;
create or replace function tv_region(p_file text, p_app text)
returns text
language sql
immutable
as $$
  select coalesce(tv_norm_sector(p_file), tv_norm_sector(p_app), 'غير محدد')
$$;

create or replace function get_live_board()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_latest timestamptz; v_prev timestamptz; v_first timestamptz; v_day date;
  v_timeline jsonb; v_movers jsonb; v_feed jsonb; v_psec jsonb;
begin
  select max(snapshot_at) into v_latest from live_project_snapshots;
  if v_latest is null then
    return jsonb_build_object('ok', true, 'empty', true);
  end if;
  v_day := (v_latest at time zone 'Asia/Riyadh')::date;
  select max(snapshot_at) into v_prev from live_project_snapshots
    where snapshot_at < v_latest and (snapshot_at at time zone 'Asia/Riyadh')::date = v_day;
  select min(snapshot_at) into v_first from live_project_snapshots
    where (snapshot_at at time zone 'Asia/Riyadh')::date = v_day;

  -- قطاع كل مشروع بسحوبات اليوم (ملف داشبورد NHC فيه المدينة لا القطاع): قطاع ملف التخصيص لنفس اسم
  -- المشروع، وإلا قطاع مدينته. بحث مفهرس لكل مشروع (~800) بدل تجميع جدول التخصيص كاملاً بكل نداء —
  -- النسخة السابقة كانت تتجاوز مهلة التنفيذ (statement timeout) على Supabase.
  select coalesce(jsonb_object_agg(pn, sec), '{}'::jsonb) into v_psec from (
    select p.pn, coalesce(
      (select tv_norm_sector(m.file_sector) from unit_allocation_mirror m
        where m.file_project_name = p.pn and tv_norm_sector(m.file_sector) is not null limit 1),
      (select tv_region(m.file_sector, m.sector) from unit_allocation_mirror m
        where m.city = p.city and tv_region(m.file_sector, m.sector) <> 'غير محدد' limit 1),
      'غير محدد') as sec
    from (
      select distinct on (btrim(project_name)) btrim(project_name) as pn, btrim(city) as city
      from live_project_snapshots
      where (snapshot_at at time zone 'Asia/Riyadh')::date = v_day
      order by btrim(project_name), snapshot_at desc
    ) p
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('at', snapshot_at, 'contracts', c, 'bookings', b, 'nhc', n) order by snapshot_at), '[]'::jsonb)
  into v_timeline
  from (
    select snapshot_at, sum(contracts_total) c, sum(bookings) b, coalesce(sum(contracts_total) filter (where is_nhc),0) n
    from live_project_snapshots
    where (snapshot_at at time zone 'Asia/Riyadh')::date = v_day
    group by snapshot_at
  ) t;

  -- المشاريع التي باعت في آخر لقطة (عقود > 0)، الأعلى عقوداً أولاً
  with latest as (
    select project_name, developer_name, city, is_nhc, contracts_total, bookings, available
    from live_project_snapshots where snapshot_at = v_latest and contracts_total > 0
  ),
  prev as (select project_name, contracts_total, bookings from live_project_snapshots where snapshot_at = v_prev),
  first as (select project_name, contracts_total, bookings from live_project_snapshots where snapshot_at = v_first)
  select coalesce(jsonb_agg(jsonb_build_object(
      'project', l.project_name, 'developer', l.developer_name, 'city', l.city, 'is_nhc', l.is_nhc,
      'sector', coalesce(v_psec->>btrim(l.project_name), 'غير محدد'),
      'contracts', l.contracts_total, 'bookings', l.bookings, 'available', l.available,
      'd_prev', case when v_prev is null then null else l.contracts_total - coalesce(p.contracts_total, 0) end,
      'd_first', l.contracts_total - coalesce(f.contracts_total, 0),
      'b_prev', case when v_prev is null then null else l.bookings - coalesce(p.bookings, l.bookings) end
    ) order by l.contracts_total desc, (l.contracts_total - coalesce(f.contracts_total, 0)) desc, l.project_name), '[]'::jsonb)
  into v_movers
  from latest l
  left join prev p on p.project_name = l.project_name
  left join first f on f.project_name = l.project_name;

  -- سجل الإشعارات: كل مشروع زادت عقوده بين سحبتين متتاليتين اليوم، الأحدث أولاً
  select coalesce(jsonb_agg(jsonb_build_object(
      'at', snapshot_at, 'project', project_name, 'developer', developer_name, 'city', city,
      'sector', coalesce(v_psec->>btrim(project_name), 'غير محدد'), 'is_nhc', is_nhc, 'dc', dc, 'db', db, 'contracts', contracts_total
    ) order by snapshot_at desc, dc desc), '[]'::jsonb)
  into v_feed
  from (
    select * from (
      select snapshot_at, project_name, developer_name, city, is_nhc, contracts_total,
        contracts_total - lag(contracts_total) over w as dc,
        bookings - lag(bookings) over w as db
      from live_project_snapshots
      where (snapshot_at at time zone 'Asia/Riyadh')::date = v_day
      window w as (partition by project_name order by snapshot_at)
    ) d
    where dc > 0
    order by snapshot_at desc, dc desc
    limit 60
  ) f;

  return jsonb_build_object(
    'ok', true, 'empty', false,
    'latest_at', v_latest, 'prev_at', v_prev, 'first_at', v_first, 'day', v_day,
    'snapshots_today', (select count(distinct snapshot_at) from live_project_snapshots where (snapshot_at at time zone 'Asia/Riyadh')::date = v_day),
    'latest', live_totals_at(v_latest),
    'prev', case when v_prev is null then '{}'::jsonb else live_totals_at(v_prev) end,
    'first', live_totals_at(v_first),
    'timeline', v_timeline,
    'movers', v_movers,
    'feed', v_feed,
    -- عقود آخر لقطة لكل قطاع (نفس ربط المشروع/المدينة بالقطاع أعلاه)
    'today_by_sector', (
      select coalesce(jsonb_object_agg(sector, c), '{}'::jsonb) from (
        select coalesce(v_psec->>btrim(project_name), 'غير محدد') as sector, sum(contracts_total) as c
        from live_project_snapshots
        where snapshot_at = v_latest
        group by 1
      ) x
    )
  );
end;
$$;
