-- ============================================================
-- SalesPlace — شاشة المبيعات الحيّة: عدّ العقود من ملف التخصيص بقطاعه ومطوّره هو
-- ============================================================
-- المشكلة: عند رفع ملف التخصيص، المشروع المسجّل بالتطبيق كان يأخذ قطاعه وتصنيفه
-- (NHC/مطور) من بيانات التطبيق لا من الملف — فأرقام العدّادات بالمناطق تختلف عن الملف.
-- الحل: كل وحدة تُحفظ أيضاً بقطاع الملف ومطوّره واسم المشروع كما بالملف (أعمدة جديدة
-- إضافية بحتة — لا تمسّ أي عمود أو شاشة أخرى)، والشاشة تعدّ منها.
--
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor، ثم ارفع ملف التخصيص من جديد
-- (حتى تتعبأ الأعمدة الجديدة). قبل إعادة الرفع: الشاشة تستخدم القطاع القديم احتياطاً.
-- آمن لإعادة التشغيل (كل الأوامر if not exists / create or replace).
-- الإصدار 2: توحيد تهجئة القطاع (tv_region)، وفهارس، وget_live_board بلا تجاوز مهلة التنفيذ.
-- ============================================================

alter table unit_allocation_mirror add column if not exists file_sector text;
alter table unit_allocation_mirror add column if not exists file_dev_kind text;
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

-- ---------- admin_upsert_allocation_mirror — نفس تعريف supply_building_details.sql + أعمدة الملف الثلاثة فقط ----------
CREATE OR REPLACE FUNCTION public.admin_upsert_allocation_mirror(p_admin text, p_pass text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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

  insert into public.unit_allocation_mirror
    (project_name, project_id, city, sector, dev_kind, unit_type, beds,
     price, moh_price, status, booking_date, istisna_date, contract_date, snapshot_date,
     unit_code, model, building_number, unit_size,
     file_sector, file_dev_kind, file_project_name)
  select
    r->>'project_name', nullif(r->>'project_id','')::int, r->>'city', r->>'sector', r->>'dev_kind',
    r->>'unit_type', nullif(r->>'beds','')::int,
    nullif(r->>'price','')::numeric, nullif(r->>'moh_price','')::numeric,
    r->>'status',
    nullif(r->>'booking_date','')::date, nullif(r->>'istisna_date','')::date, nullif(r->>'contract_date','')::date,
    (r->>'snapshot_date')::date,
    r->>'unit_code', r->>'model', r->>'building_number', nullif(r->>'unit_size','')::numeric,
    nullif(btrim(r->>'file_sector'),''), nullif(r->>'file_dev_kind',''), nullif(btrim(r->>'file_project_name'),'')
  from jsonb_array_elements(p_rows) r;

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'أُدرج '||v_count||' صفاً بنجاح');
end;
$function$;

-- ---------- tv_contract_daily ----------
-- عدد العقود لكل يوم × قطاع الملف × (NHC/مطور) — يُحسب بالمتصفح من ملف التخصيص كاملاً عند كل رفع
-- (حالة الحجز = عقد، تاريخ توقيع العقد) ويُستبدل بالكامل. لشاشة الداشبورد فقط — بقية التطبيق كما هو.
create table if not exists tv_contract_daily (
  contract_date date not null,
  sector text not null default '',     -- عمود "القطاع" كما بالملف (يُوحَّد عند القراءة بـ tv_region)
  kind text not null,                  -- nhc / other (developer_name = NHC)
  cnt integer not null,
  updated_at timestamptz not null default now(),
  primary key (contract_date, sector, kind)
);
alter table tv_contract_daily enable row level security;
drop policy if exists tv_contract_daily_read on tv_contract_daily;
create policy tv_contract_daily_read on tv_contract_daily for select using (true);

-- استبدال كامل مع كل رفع لملف التخصيص — يتطلّب صلاحية أدمن فعلية
create or replace function admin_replace_tv_contract_daily(p_admin text, p_pass text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_count int;
  v_total bigint;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and is_active
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  delete from tv_contract_daily where true;
  insert into tv_contract_daily (contract_date, sector, kind, cnt)
  select (r->>'contract_date')::date, coalesce(btrim(r->>'sector'), ''), coalesce(r->>'kind', 'other'), sum((r->>'cnt')::int)
  from jsonb_array_elements(p_rows) r
  where nullif(r->>'contract_date', '') is not null
  group by 1, 2, 3;

  get diagnostics v_count = row_count;
  select coalesce(sum(cnt), 0) into v_total from tv_contract_daily;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً ('||v_total||' عقداً)', 'count', v_count, 'total', v_total);
end;
$$;

-- ---------- get_tv_contracts ----------
-- العقود الموقّعة خلال السنة لكل شهر × قطاع × (NHC/مطور)، ولكل يوم من الشهر المطلوب — الشاشة تجمع
-- منها المملكة والمناطق والمنحنيات. المصدر: tv_contract_daily (عدّ ملف التخصيص كاملاً: حالة الحجز =
-- عقد، بتاريخ توقيع العقد وقطاع الملف ومطوّره، بلا أي استبعاد — يطابق فلترة الملف بالإكسل). إن كان
-- الجدول فارغاً (قبل أول رفع بعد تشغيل tv_contract_counts.sql): مرآة التخصيص كما سابقاً.
create or replace function get_tv_contracts(p_year int, p_month int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with has as (select exists(select 1 from tv_contract_daily) as f),
  m as (
    select tv_region(nullif(d.sector, ''), null) as sec, d.kind, d.contract_date, d.cnt,
           coalesce(nullif(d.sector, ''), '(فارغ)') as raw
    from tv_contract_daily d, has
    where has.f and d.contract_date >= make_date(p_year, 1, 1) and d.contract_date < make_date(p_year + 1, 1, 1)
    union all
    select tv_region(u.file_sector, u.sector), coalesce(u.file_dev_kind, u.dev_kind, 'other'), u.contract_date, 1,
           u.file_sector
    from unit_allocation_mirror u, has
    where not has.f and u.contract_date >= make_date(p_year, 1, 1) and u.contract_date < make_date(p_year + 1, 1, 1)
  )
  select jsonb_build_object(
    'ok', true,
    'source', case when (select f from has) then 'file' else 'mirror' end,
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('m', mo, 'sector', sec, 'kind', kind, 'cnt', c))
      from (select extract(month from contract_date)::int as mo, sec, kind, sum(cnt) as c from m group by 1, 2, 3) x
    ), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'sector', sec, 'kind', kind, 'cnt', c))
      from (select extract(day from contract_date)::int as d, sec, kind, sum(cnt) as c from m
            where extract(month from contract_date)::int = p_month group by 1, 2, 3) y
    ), '[]'::jsonb),
    'file_sector_rows', (select count(*) from unit_allocation_mirror where file_sector is not null),
    'rows', (select count(*) from unit_allocation_mirror),
    -- قيم عمود القطاع بالملف التي لم تُعرف (عقود السنة) — تظهر بأسفل الشاشة للتشخيص
    'unmapped', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'cnt', c) order by c desc)
      from (select raw as v, sum(cnt) as c from m
            where raw is not null and tv_norm_sector(nullif(raw, '(فارغ)')) is null
            group by 1 order by 2 desc limit 8) u
    ), '[]'::jsonb)
  );
$$;

-- ---------- دوال الشاشة الحالية — نفس تعريفها بـ tv_dashboard.sql وlive_board.sql مع قطاع الملف ----------
-- ---------- get_sector_type_sales ----------
-- مبيعات (عقود موقّعة) لكل قطاع × نوع وحدة خلال شهر معيّن: الإجمالي + تفصيل يومي —
-- من unit_allocation_mirror.contract_date الحقيقي، نفس مصدر get_sales_report الأصلية،
-- بلا أي جدول تراكمي جديد.
create or replace function get_sector_type_sales(p_year int, p_month int)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_from date := make_date(p_year, p_month, 1);
  v_to date := (make_date(p_year, p_month, 1) + interval '1 month' - interval '1 day')::date;
  v_result jsonb;
begin
  /* نسخة مُعاد هيكلتها — النسخة الأولى كانت subquery مرتبط (correlated) بداخله GROUP BY
     خاص به يرجع لعمود من الاستعلام الخارجي، فيرفضها Postgres بخطأ "subquery uses
     ungrouped column ... from outer query". الحل: تجميع واحد فقط (base) بمفتاح
     القطاع+النوع+اليوم، ثم تجميع ثانٍ (grouped) فوقه — بلا أي ارتباط متداخل إطلاقاً. */
  with base as (
    select
      tv_region(file_sector, sector) as sector,
      coalesce(unit_type,'غير محدد') as unit_type,
      contract_date,
      count(*) as dcnt
    from unit_allocation_mirror
    where status='contracted' and contract_date between v_from and v_to
    group by tv_region(file_sector, sector), coalesce(unit_type,'غير محدد'), contract_date
  ),
  grouped as (
    select
      sector, unit_type,
      sum(dcnt) as total_cnt,
      jsonb_agg(jsonb_build_object('day', extract(day from contract_date)::int, 'cnt', dcnt) order by contract_date) as daily
    from base
    group by sector, unit_type
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'sector', sector, 'unit_type', unit_type, 'total_cnt', total_cnt, 'daily', daily
  ) order by sector, unit_type), '[]'::jsonb)
  into v_result
  from grouped;

  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to, 'rows', v_result);
end;
$$;

-- ---------- get_today_activity ----------
-- نشاط اليوم: حجوزات/استصناع/عقود — على مستوى المملكة وتفصيل لكل قطاع.
-- حجوزات = booking_date اليوم (بصرف النظر عن الحالة الحالية — تاريخ حدث، لا لقطة حالة).
-- استصناع = نفس تعريف project_istisna_stats الأصلية: حالة "حجز" ولها istisna_date فعلي،
-- بهذا التاريخ تحديداً اليوم. عقود = status='contracted' وcontract_date اليوم.
create or replace function get_today_activity()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'date', current_date,
    'kingdom', jsonb_build_object(
      'bookings', (select count(*) from unit_allocation_mirror where booking_date = current_date),
      'istisna', (select count(*) from unit_allocation_mirror where status='reserved' and istisna_date = current_date),
      'contracts', (select count(*) from unit_allocation_mirror where status='contracted' and contract_date = current_date)
    ),
    'by_sector', coalesce((
      select jsonb_agg(jsonb_build_object('sector', sector, 'bookings', bookings, 'istisna', istisna, 'contracts', contracts) order by sector)
      from (
        select tv_region(file_sector, sector) as sector,
          count(*) filter (where booking_date = current_date) as bookings,
          count(*) filter (where status='reserved' and istisna_date = current_date) as istisna,
          count(*) filter (where status='contracted' and contract_date = current_date) as contracts
        from unit_allocation_mirror
        where booking_date = current_date
           or (status='reserved' and istisna_date = current_date)
           or (status='contracted' and contract_date = current_date)
        group by tv_region(file_sector, sector)
      ) s
    ), '[]'::jsonb),
    'ok', true
  );
$$;

-- ---------- get_sector_avail_pricing ----------
-- متوسط سعر الوحدات المتاحة الآن وسعر المتر (sum(price)/sum(unit_size)) لكل قطاع —
-- نفس أسلوب get_supply_buildings تماماً، على مستوى القطاع بدل المبنى.
create or replace function get_sector_avail_pricing()
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'sector', sector, 'avail_count', avail_count, 'avg_price', avg_price, 'avg_price_sqm', avg_price_sqm
  ) order by sector), '[]'::jsonb)
  from (
    select tv_region(file_sector, sector) as sector,
           count(*) as avail_count,
           round(avg(price)) as avg_price,
           case when sum(unit_size) filter (where unit_size>0)>0
                then round(sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0))
                else null end as avg_price_sqm
    from unit_allocation_mirror
    where status='avail'
    group by tv_region(file_sector, sector)
  ) t;
$$;

-- حزمة الشاشة كاملة في نداء واحد: الأوقات، الإجماليات (آخر لقطة / السابقة / أول لقطة اليوم)،
-- منحنى اليوم لقطةً لقطة، المشاريع التي باعت، وسجل الإشعارات (كل زيادة عقود بين سحبتين اليوم).
-- التجميع اليومي بتوقيت الرياض. "السابقة" محصورة باليوم نفسه — أول سحبة بالصباح لا تُقارَن بآخر
-- سحبة أمس (عمود العقود بالملف يومي، فالمقارنة عبر منتصف الليل تعطي هبوطاً وهمياً).
-- أعمدة قطاع/اسم المشروع من ملف التخصيص نفسه (تُعبّأ مع كل رفع للملف) — يُربط بها قطاع كل مشروع بالشاشة
alter table unit_allocation_mirror add column if not exists file_sector text;
alter table unit_allocation_mirror add column if not exists file_project_name text;

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
