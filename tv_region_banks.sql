-- ============================================================
-- SalesPlace — شاشة الداشبورد: تصفية حسب المنطقة، نطاق مذكرات الاستثمار، والبنوك المنفّذة
-- ============================================================
-- • get_tv_memo_scope: عقود NHC لمشاريع مذكرات الاستثمار فقط (نفس نطاق المستهدف — 32 مشروعاً لـ2026)
--   حسب قطاع المستهدف، حتى يطابق رقم العدّاد نطاق عرض «المستهدف والمحقق». ربط مشروع المستهدف بمشاريع
--   ملف التخصيص: رمز المشروع، وإلا الاسم (بالملف أو بالتطبيق أو بالعرض). غير المطابَق يُذكر بالاسم.
-- • get_live_board: + إجماليات وحركة كل قطاع (لتصفية الشاشة عند الضغط على عدّاد منطقة).
-- • get_tv_destinations: + المتاح لكل قطاع.
-- • tv_bank_daily: عقود كل يوم × قطاع × NHC/مطور × البنك المنفّذ (آخر عمود بملف التخصيص).
--
-- يتطلّب: tv_destinations.sql و tv_products.sql مُشغَّلين قبله. شغّل هذا الملف مرة واحدة ثم ارفع ملف
-- التخصيص من جديد (للبنوك). آمن لإعادة التشغيل.
-- ============================================================

-- ---------- get_tv_memo_scope ----------
create or replace function get_tv_memo_scope(p_year int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with t as (
    select project_name, slide_name, project_code, tv_region(sector, null) as sec
    from dashboard_targets
    where scope = 'nhc' and year = p_year and units > 0
  ),
  m as (
    select distinct t.project_name as target, t.sec, u.project_name as file_project
    from t
    join tv_unit_status u on (
      (coalesce(t.project_code, '') <> '' and u.project_code <> ''
         and u.project_code in (select btrim(c) from regexp_split_to_table(t.project_code, '\s*\+\s*') as c))
      or tv_norm_name(u.project_name) in (tv_norm_name(t.project_name), tv_norm_name(t.slide_name))
      or (u.app_name is not null and tv_norm_name(u.app_name) in (tv_norm_name(t.project_name), tv_norm_name(t.slide_name)))
    )
  ),
  fp as (select distinct on (file_project) file_project, sec from m order by file_project, sec)
  select jsonb_build_object(
    'ok', true,
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('m', mo, 'sector', sec, 'cnt', c))
      from (
        select extract(month from d.contract_date)::int as mo, fp.sec, sum(d.cnt) as c
        from tv_contract_daily d join fp on fp.file_project = d.project_name
        where d.contract_date >= make_date(p_year, 1, 1) and d.contract_date < make_date(p_year + 1, 1, 1)
        group by 1, 2
      ) x
    ), '[]'::jsonb),
    'targets', (select count(*) from t),
    'matched', (select count(distinct target) from m),
    'file_projects', (select count(*) from fp),
    'unmatched', coalesce((select jsonb_agg(project_name order by project_name) from t where project_name not in (select target from m)), '[]'::jsonb)
  );
$$;

-- ---------- tv_bank_daily ----------
create table if not exists tv_bank_daily (
  contract_date date not null,
  sector text not null default '',
  kind text not null,
  bank text not null default '',      -- فارغ = بلا بنك (نقدي / لم يُذكر)
  cnt integer not null,
  updated_at timestamptz not null default now(),
  primary key (contract_date, sector, kind, bank)
);
alter table tv_bank_daily enable row level security;
drop policy if exists tv_bank_daily_read on tv_bank_daily;
create policy tv_bank_daily_read on tv_bank_daily for select using (true);

create or replace function admin_load_tv_banks(p_admin text, p_pass text, p_rows jsonb, p_reset boolean)
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
  if p_reset then delete from tv_bank_daily where true; end if;
  insert into tv_bank_daily (contract_date, sector, kind, bank, cnt)
  select (r->>'contract_date')::date, coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'),
         coalesce(btrim(r->>'bank'), ''), sum((r->>'cnt')::int)
  from jsonb_array_elements(p_rows) r
  where nullif(r->>'contract_date', '') is not null
  group by 1, 2, 3, 4
  on conflict (contract_date, sector, kind, bank) do update set cnt = tv_bank_daily.cnt + excluded.cnt, updated_at = now();
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- ---------- get_tv_banks ----------
create or replace function get_tv_banks(p_from date, p_to date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'ok', true, 'from', p_from, 'to', p_to,
    'has_banks', exists(select 1 from tv_bank_daily where bank <> ''),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object('sector', sec, 'kind', kind, 'bank', bank, 'cnt', c))
      from (
        select tv_region(nullif(sector, ''), null) as sec, kind, bank, sum(cnt) as c
        from tv_bank_daily
        where contract_date between p_from and p_to
        group by 1, 2, 3
      ) x
    ), '[]'::jsonb)
  );
$$;

-- ---------- get_tv_destinations ----------
-- لكل وجهة (الضاحية): عقود السنة حتى آخر رفع للتخصيص (NHC / المطورون) مقابل المستهدف السنوي بنفس منهجية
-- عدّادات القطاعات — NHC: مذكرات الاستثمار، المطورون: خطة المبيعات (dashboard_targets) — والمتاح على
-- المنصة / لدى المطور. ربط مشروع المستهدف بوجهته: رمز المشروع، وإلا الاسم (بالملف أو بالتطبيق أو بالعرض).
create or replace function get_tv_destinations(p_year int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with
  ach as (
    select dest, coalesce(sum(cnt) filter (where kind = 'nhc'), 0) as nhc, coalesce(sum(cnt) filter (where kind <> 'nhc'), 0) as dev
    from tv_contract_daily
    where dest <> '' and contract_date >= make_date(p_year, 1, 1) and contract_date < make_date(p_year + 1, 1, 1)
    group by 1
  ),
  av as (
    select dest,
           coalesce(sum(cnt) filter (where status = 'متاحة على المنصة'), 0) as plat,
           coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور'), 0) as devav,
           mode() within group (order by tv_region(nullif(sector, ''), null)) as sec
    from tv_unit_status where dest <> '' group by 1
  ),
  pmap as (
    select distinct on (key) key, dest from (
      select project_code as key, dest, sum(cnt) as n from tv_unit_status where project_code <> '' group by 1, 2
      union all
      select 'n:' || tv_norm_name(project_name), dest, sum(cnt) from tv_unit_status group by 1, 2
      union all
      select 'n:' || tv_norm_name(app_name), dest, sum(cnt) from tv_unit_status where app_name is not null group by 1, 2
    ) z
    where key is not null
    order by key, n desc
  ),
  tg as (
    select t.scope, t.units, coalesce(
      (select pm.dest from regexp_split_to_table(coalesce(t.project_code, ''), '\s*\+\s*') as code(c)
         join pmap pm on pm.key = btrim(code.c) where btrim(code.c) <> '' limit 1),
      (select pm.dest from pmap pm where pm.key = 'n:' || tv_norm_name(t.project_name)),
      (select pm.dest from pmap pm where pm.key = 'n:' || tv_norm_name(t.slide_name))
    ) as dest
    from dashboard_targets t
    where t.year = p_year
  ),
  tgd as (
    select dest, coalesce(sum(units) filter (where scope = 'nhc'), 0) as nhc_t, coalesce(sum(units) filter (where scope = 'dev'), 0) as dev_t
    from tg where coalesce(dest, '') <> '' group by 1
  ),
  alld as (select dest from ach union select dest from tgd union select dest from av)
  select jsonb_build_object(
    'ok', true,
    'as_of', (select max(updated_at) from tv_contract_daily),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dest', d.dest, 'sector', coalesce(av.sec, 'غير محدد'),
        'nhc', coalesce(ach.nhc, 0), 'dev', coalesce(ach.dev, 0),
        'nhc_target', coalesce(tgd.nhc_t, 0), 'dev_target', coalesce(tgd.dev_t, 0),
        'avail_platform', coalesce(av.plat, 0), 'avail_developer', coalesce(av.devav, 0)
      ) order by coalesce(tgd.nhc_t, 0) + coalesce(tgd.dev_t, 0) desc, coalesce(ach.nhc, 0) + coalesce(ach.dev, 0) desc)
      from alld d left join ach using (dest) left join tgd using (dest) left join av using (dest)
    ), '[]'::jsonb),
    -- مستهدف لم يُربط بأي وجهة (مشروع خارج الوجهات أو لم يُطابَق) — للتشخيص
    'targets_outside', (select jsonb_build_object(
        'nhc', coalesce(sum(units) filter (where scope = 'nhc' and coalesce(dest, '') = ''), 0),
        'dev', coalesce(sum(units) filter (where scope = 'dev' and coalesce(dest, '') = ''), 0)) from tg),
    -- تشخيص: هل وصلت بيانات رفع ملف التخصيص لهذين الجدولين؟ (تظهر رسالة واضحة بالشاشة إن لم تصل)
    'diag', jsonb_build_object(
      'status_rows', (select count(*) from tv_unit_status),
      'status_dest_rows', (select count(*) from tv_unit_status where dest <> ''),
      'status_updated', (select max(updated_at) from tv_unit_status),
      'contract_rows', (select count(*) from tv_contract_daily),
      'contract_project_rows', (select count(*) from tv_contract_daily where project_name <> '')),
    -- المتاح على مستوى المملكة و NHC / المطورين
    'avail', (select jsonb_build_object(
        'platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة'), 0),
        'developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور'), 0),
        'nhc_platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة' and kind = 'nhc'), 0),
        'nhc_developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور' and kind = 'nhc'), 0),
        'dev_platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة' and kind <> 'nhc'), 0),
        'dev_developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور' and kind <> 'nhc'), 0))
      from tv_unit_status),
    -- نفس المتاح لكل قطاع — لتصفية الشاشة حسب المنطقة
    'avail_by_sector', (select coalesce(jsonb_object_agg(sec, a), '{}'::jsonb) from (
      select tv_region(nullif(sector, ''), null) as sec, jsonb_build_object(
        'platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة'), 0),
        'developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور'), 0),
        'nhc_platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة' and kind = 'nhc'), 0),
        'nhc_developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور' and kind = 'nhc'), 0),
        'dev_platform', coalesce(sum(cnt) filter (where status = 'متاحة على المنصة' and kind <> 'nhc'), 0),
        'dev_developer', coalesce(sum(cnt) filter (where status = 'متاحة لدى المطور' and kind <> 'nhc'), 0)) as a
      from tv_unit_status group by 1) z)
  );
$$;

-- حزمة الشاشة كاملة في نداء واحد (+ إجماليات وحركة كل قطاع لتصفية الشاشة حسب المنطقة)
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
    -- إجماليات كل قطاع × NHC/مطور بآخر سحب والسابق وأول سحب اليوم، وحركة اليوم لكل قطاع — لتصفية الشاشة حسب المنطقة
    'sector_totals', (
      select coalesce(jsonb_agg(jsonb_build_object('at', snapshot_at, 'sector', sec, 'nhc', is_nhc,
        'contracts', c, 'bookings', b, 'available', a, 'financed', f, 'cash', ca, 'nonbene', nb, 'selfbuild', sb,
        'projects_with_contracts', pw)), '[]'::jsonb)
      from (
        select snapshot_at, coalesce(v_psec->>btrim(project_name), 'غير محدد') as sec, is_nhc,
               sum(contracts_total) as c, sum(bookings) as b, sum(available) as a, sum(contracts_financed) as f,
               sum(contracts_cash) as ca, sum(contracts_nonbene) as nb, sum(contracts_selfbuild) as sb,
               count(*) filter (where contracts_total > 0) as pw
        from live_project_snapshots
        where snapshot_at in (v_latest, v_prev, v_first)
        group by 1, 2, 3
      ) st
    ),
    'timeline_sector', (
      select coalesce(jsonb_agg(jsonb_build_object('at', snapshot_at, 'sector', sec, 'contracts', c, 'nhc', n) order by snapshot_at), '[]'::jsonb)
      from (
        select snapshot_at, coalesce(v_psec->>btrim(project_name), 'غير محدد') as sec,
               sum(contracts_total) as c, coalesce(sum(contracts_total) filter (where is_nhc), 0) as n
        from live_project_snapshots
        where (snapshot_at at time zone 'Asia/Riyadh')::date = v_day
        group by 1, 2
      ) ts
    ),
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

