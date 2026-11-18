-- ============================================================
-- SalesPlace — ثبات أرقام القطاعات بالشاشة (العدّادات الغربي/الأوسط/الشرقي)
-- ============================================================
-- • tv_live_psec: قطاع كل مشروع بسحوبات داشبورد NHC اليوم بطريقة ثابتة. النسخة السابقة كانت تأخذ
--   «أول صف» (limit 1 بلا ترتيب) من ملف التخصيص أو من مدينة المشروع — فإن اختلف القطاع بين صفوف
--   المشروع/المدينة (أو كانت المدينة فارغة) قد يذهب نفس المشروع لقطاع مختلف بكل تحديث، فتتغيّر عقود اليوم
--   لكل قطاع ونسبة العدّاد دون أي بيانات جديدة. الآن: القطاع الغالب (الأكثر وحدات) وبترتيب ثابت، والمدينة
--   الفارغة لا تُستعمل.
-- • get_live_board: نفس النسخة المعتمدة (tv_board_upload.sql) مع الربط الجديد. هذا الملف يغلبها.
--
-- يتطلّب: tv_board_upload.sql مُشغَّلاً قبله. شغّل هذا الملف مرة واحدة. آمن لإعادة التشغيل. لا حاجة لإعادة الرفع.
-- ============================================================

create or replace function tv_live_psec(p_day date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_object_agg(pn, sec), '{}'::jsonb) from (
    select p.pn, coalesce(
      -- 1) آخر ملف تخصيص مرفوع (tv_unit_status) بنفس اسم المشروع: القطاع الأكثر وحدات
      (select s from (select tv_norm_sector(u.sector) as s, sum(u.cnt) as n from tv_unit_status u
          where u.project_name = p.pn group by 1) x
        where s is not null order by n desc, s limit 1),
      -- 2) مرآة التخصيص بنفس اسم المشروع
      (select s from (select tv_norm_sector(m.file_sector) as s, count(*) as n from unit_allocation_mirror m
          where m.file_project_name = p.pn group by 1) x
        where s is not null order by n desc, s limit 1),
      -- 3) قطاع مدينة المشروع من آخر ملف تخصيص (المدينة الفارغة لا تُستعمل)
      (select s from (select tv_norm_sector(u.sector) as s, sum(u.cnt) as n from tv_unit_status u
          where p.city <> '' and btrim(u.city) = p.city group by 1) x
        where s is not null order by n desc, s limit 1),
      -- 4) قطاع المدينة من مرآة التخصيص (عيّنة مفهرسة محدودة حتى لا تتجاوز المهلة)
      (select s from (select tv_region(m.file_sector, m.sector) as s, count(*) as n
          from (select file_sector, sector from unit_allocation_mirror where p.city <> '' and city = p.city limit 3000) m
          group by 1) x
        where s <> 'غير محدد' order by n desc, s limit 1),
      'غير محدد') as sec
    from (
      select distinct on (btrim(project_name)) btrim(project_name) as pn, coalesce(btrim(city), '') as city
      from live_project_snapshots
      where (snapshot_at at time zone 'Asia/Riyadh')::date = p_day
      order by btrim(project_name), snapshot_at desc
    ) p
  ) z;
$$;
revoke execute on function tv_live_psec(date) from public, anon, authenticated;

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


  -- قطاع كل مشروع بسحوبات اليوم — ثابت (انظر tv_live_psec أعلاه)
  v_psec := tv_live_psec(v_day);

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
revoke execute on function get_live_board() from public, anon, authenticated;

-- ---------- مهلة التنفيذ ----------
-- Supabase يقطع أي نداء من التطبيق بعد ~3 ثوانٍ (دور anon). رفع ملف التخصيص الكبير وبعض قراءات الشاشة
-- تتجاوزها أحياناً («canceling statement due to statement timeout»). كل النداءات تمرّ عبر البوابة بجلسة دخول،
-- فرفع المهلة لا يفتح شيئاً جديداً. التطبيق يصغّر دفعات الرفع تلقائياً عند انتهاء المهلة أيضاً.
alter role anon set statement_timeout = '20s';
alter role authenticated set statement_timeout = '20s';
notify pgrst, 'reload config';
