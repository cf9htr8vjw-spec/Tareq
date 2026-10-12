-- ============================================================
-- SalesPlace — شاشة المبيعات: رفع ملف التخصيص من الشاشة نفسها + إصلاح get_live_board
-- ============================================================
-- • tv_project_app: يحفظ اسم كل مشروع بالتطبيق (يعرفه التطبيق الأساسي فقط) حتى لا يضيع عند رفع
--   ملف التخصيص من شاشة المبيعات — يُستخدم لربط مستهدفات المطورين بوجهاتها.
-- • admin_load_tv_alloc: نفس الدالة + الاحتفاظ بأسماء التطبيق.
-- • get_live_board: النسخة الكاملة الأحدث (إجماليات وحركة كل قطاع لتصفية الشاشة حسب المنطقة — لم
--   تكن مضمّنة فعلياً بـ tv_region_banks.sql)، وربط مشاريع داشبورد NHC بقطاعها من آخر ملف تخصيص مرفوع.
--
-- يتطلّب: tv_destinations.sql و tv_products.sql و tv_region_banks.sql مُشغَّلة قبله.
-- شغّل هذا الملف مرة واحدة. آمن لإعادة التشغيل.
-- ============================================================

-- أسماء مشاريع ملف التخصيص بالتطبيق (لمطابقة خطة المطورين) — تبقى بين رفعات الملف من شاشة المبيعات
create table if not exists tv_project_app (
  project_name text primary key,
  app_name text not null
);
alter table tv_project_app enable row level security;
drop policy if exists tv_project_app_read on tv_project_app;
create policy tv_project_app_read on tv_project_app for select using (true);

create index if not exists tv_unit_status_city_idx on tv_unit_status(city);

-- ---------- رفع الجدولين على دفعات (الأولى تمسح القديم) — يتطلّب صلاحية أدمن فعلية ----------
create or replace function admin_load_tv_alloc(p_admin text, p_pass text, p_table text, p_rows jsonb, p_reset boolean)
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

  if p_table = 'contracts' then
    if p_reset then delete from tv_contract_daily where true; end if;
    insert into tv_contract_daily (contract_date, project_name, sector, dest, kind, unit_type, cnt, price_sum, price_n)
    select (r->>'contract_date')::date, coalesce(btrim(r->>'project_name'), ''), coalesce(btrim(r->>'sector'), ''),
           coalesce(btrim(r->>'dest'), ''), coalesce(r->>'kind', 'other'), coalesce(btrim(r->>'unit_type'), ''),
           sum((r->>'cnt')::int), sum(coalesce(nullif(r->>'price_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'price_n', '')::int, 0))
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'contract_date', '') is not null
    group by 1, 2, 3, 4, 5, 6
    on conflict (contract_date, project_name, sector, dest, kind, unit_type) do update set
      cnt = tv_contract_daily.cnt + excluded.cnt, price_sum = tv_contract_daily.price_sum + excluded.price_sum,
      price_n = tv_contract_daily.price_n + excluded.price_n, updated_at = now();
  elsif p_table = 'status' then
    if p_reset then
      -- أسماء المشاريع بالتطبيق تُحفظ قبل المسح: الرفع من شاشة المبيعات لا يعرفها (لا كتالوج هناك)
      insert into tv_project_app (project_name, app_name)
      select distinct on (project_name) project_name, app_name from tv_unit_status where app_name is not null order by project_name
      on conflict (project_name) do update set app_name = excluded.app_name;
      delete from tv_unit_status where true;
    end if;
    insert into tv_unit_status (project_name, project_code, app_name, developer, city, dest, sector, kind, status, cnt)
    select btrim(r->>'project_name'), coalesce(btrim(r->>'project_code'), ''), max(nullif(btrim(r->>'app_name'), '')),
           max(nullif(btrim(r->>'developer'), '')), max(nullif(btrim(r->>'city'), '')),
           coalesce(btrim(r->>'dest'), ''), coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'),
           coalesce(btrim(r->>'status'), ''), sum((r->>'cnt')::int)
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'project_name'), '') is not null
    group by 1, 2, 6, 7, 8, 9
    on conflict (project_name, project_code, dest, sector, kind, status) do update set cnt = tv_unit_status.cnt + excluded.cnt, updated_at = now();
    get diagnostics v_count = row_count;
    -- اسم التطبيق: من الرفع إن وُجد (التطبيق الأساسي)، وإلا آخر اسم معروف للمشروع
    insert into tv_project_app (project_name, app_name)
    select distinct on (btrim(r->>'project_name')) btrim(r->>'project_name'), btrim(r->>'app_name')
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'project_name'), '') is not null and nullif(btrim(r->>'app_name'), '') is not null
    order by btrim(r->>'project_name')
    on conflict (project_name) do update set app_name = excluded.app_name;
    update tv_unit_status u set app_name = pa.app_name
    from tv_project_app pa where u.app_name is null and pa.project_name = u.project_name;
    return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
  else
    return jsonb_build_object('ok', false, 'msg', 'جدول غير معروف');
  end if;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;


-- حزمة الشاشة كاملة في نداء واحد
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
      -- أولاً آخر ملف تخصيص مرفوع (tv_unit_status — يُحدَّث من التطبيق أو من شاشة المبيعات)، ثم مرآة التخصيص
      (select tv_norm_sector(u.sector) from tv_unit_status u
        where u.project_name = p.pn and tv_norm_sector(u.sector) is not null limit 1),
      (select tv_norm_sector(m.file_sector) from unit_allocation_mirror m
        where m.file_project_name = p.pn and tv_norm_sector(m.file_sector) is not null limit 1),
      (select tv_norm_sector(u.sector) from tv_unit_status u
        where u.city = p.city and tv_norm_sector(u.sector) is not null limit 1),
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
