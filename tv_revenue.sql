-- ============================================================
-- SalesPlace — شاشة المبيعات: الإيرادات (المستهدف والمحقق)
-- ============================================================
-- • المستهدف: عمود revenue بجدول dashboard_targets (مذكرات الاستثمار — صف «إيرادات تطوير وحدات
--   سكنية» بالخطة بالسنوات)، مجموعاً لكل قطاع.
-- • المحقق: الإيراد المستحق من عقود السنة (ملف التخصيص) — نفس منهجية العروض:
--     عقد ممول بنكياً  → قيمة العقد كاملة (الدفعة الأولى + مبلغ التمويل)
--     عقد شراء نقدي   → الدفعة الأولى من قيمة العقد (النسبة تُطبَّق بالشاشة، 10% افتراضياً)
--   لذلك يُحفظ لكل يوم × مشروع × قطاع × نوع مجموع قيمة العقود الممولة والنقدية منفصلين.
--
-- يتطلّب: tv_board_upload.sql مُشغَّلاً قبله. شغّل هذا الملف مرة واحدة، ثم ارفع ملف التخصيص من
-- جديد (من الشاشة أو التطبيق) ليُملأ عمودا التمويل والنقد. آمن لإعادة التشغيل.
-- ============================================================

alter table tv_contract_daily add column if not exists fin_sum  numeric not null default 0;  -- قيمة العقود الممولة بنكياً
alter table tv_contract_daily add column if not exists fin_n    integer not null default 0;
alter table tv_contract_daily add column if not exists cash_sum numeric not null default 0;  -- قيمة عقود الشراء النقدي
alter table tv_contract_daily add column if not exists cash_n   integer not null default 0;

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
    insert into tv_contract_daily (contract_date, project_name, sector, dest, kind, unit_type, cnt, price_sum, price_n,
                                   fin_sum, fin_n, cash_sum, cash_n)
    select (r->>'contract_date')::date, coalesce(btrim(r->>'project_name'), ''), coalesce(btrim(r->>'sector'), ''),
           coalesce(btrim(r->>'dest'), ''), coalesce(r->>'kind', 'other'), coalesce(btrim(r->>'unit_type'), ''),
           sum((r->>'cnt')::int), sum(coalesce(nullif(r->>'price_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'price_n', '')::int, 0)),
           sum(coalesce(nullif(r->>'fin_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'fin_n', '')::int, 0)),
           sum(coalesce(nullif(r->>'cash_sum', '')::numeric, 0)), sum(coalesce(nullif(r->>'cash_n', '')::int, 0))
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'contract_date', '') is not null
    group by 1, 2, 3, 4, 5, 6
    on conflict (contract_date, project_name, sector, dest, kind, unit_type) do update set
      cnt = tv_contract_daily.cnt + excluded.cnt, price_sum = tv_contract_daily.price_sum + excluded.price_sum,
      price_n = tv_contract_daily.price_n + excluded.price_n,
      fin_sum = tv_contract_daily.fin_sum + excluded.fin_sum, fin_n = tv_contract_daily.fin_n + excluded.fin_n,
      cash_sum = tv_contract_daily.cash_sum + excluded.cash_sum, cash_n = tv_contract_daily.cash_n + excluded.cash_n,
      updated_at = now();
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

-- ---------- حزمة عقود الشاشة: نفس get_tv_contracts + قيمة العقود الممولة والنقدية لكل شهر ويوم ----------
create or replace function get_tv_contracts(p_year int, p_month int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with has as (select exists(select 1 from tv_contract_daily) as f),
  m as (
    select tv_region(nullif(d.sector, ''), null) as sec, d.kind, d.contract_date, d.cnt, d.fin_sum, d.cash_sum, d.fin_n, d.cash_n,
           coalesce(nullif(d.sector, ''), '(فارغ)') as raw
    from tv_contract_daily d, has
    where has.f and d.contract_date >= make_date(p_year, 1, 1) and d.contract_date < make_date(p_year + 1, 1, 1)
    union all
    select tv_region(u.file_sector, u.sector), coalesce(u.file_dev_kind, u.dev_kind, 'other'), u.contract_date, 1, 0, 0, 0, 0,
           u.file_sector
    from unit_allocation_mirror u, has
    where not has.f and u.contract_date >= make_date(p_year, 1, 1) and u.contract_date < make_date(p_year + 1, 1, 1)
  )
  select jsonb_build_object(
    'ok', true,
    'source', case when (select f from has) then 'file' else 'mirror' end,
    'months', coalesce((
      select jsonb_agg(jsonb_build_object('m', mo, 'sector', sec, 'kind', kind, 'cnt', c, 'fin', fs, 'cash', cs))
      from (select extract(month from contract_date)::int as mo, sec, kind, sum(cnt) as c, sum(fin_sum) as fs, sum(cash_sum) as cs
            from m group by 1, 2, 3) x
    ), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'sector', sec, 'kind', kind, 'cnt', c, 'fin', fs, 'cash', cs))
      from (select extract(day from contract_date)::int as d, sec, kind, sum(cnt) as c, sum(fin_sum) as fs, sum(cash_sum) as cs from m
            where extract(month from contract_date)::int = p_month group by 1, 2, 3) y
    ), '[]'::jsonb),
    -- عقود السنة المصنّفة (ممول/نقدي): صفر = الملف المرفوع بلا عمود البنك أو قبل تشغيل هذا الملف
    'rev_classified', (select coalesce(sum(fin_n + cash_n), 0) from m),
    'file_sector_rows', (select count(*) from unit_allocation_mirror where file_sector is not null),
    'rows', (select count(*) from unit_allocation_mirror),
    'unmapped', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'cnt', c) order by c desc)
      from (select raw as v, sum(cnt) as c from m
            where raw is not null and tv_norm_sector(nullif(raw, '(فارغ)')) is null
            group by 1 order by 2 desc limit 8) u
    ), '[]'::jsonb)
  );
$$;

-- ---------- المشاريع التي باعت خلال فترة: + قيمة العقود الممولة والنقدية ----------
create or replace function get_tv_period_projects(p_from date, p_to date)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with c as (
    select project_name, kind, sum(cnt) as cnt, sum(fin_sum) as fin, sum(cash_sum) as cash,
           mode() within group (order by tv_region(nullif(sector, ''), null)) as sec,
           mode() within group (order by dest) as dest
    from tv_contract_daily
    where contract_date between p_from and p_to and project_name <> ''
    group by 1, 2
  ),
  info as (
    select project_name, max(developer) as developer, max(city) as city
    from tv_unit_status group by 1
  )
  select jsonb_build_object(
    'ok', true,
    'from', p_from, 'to', p_to,
    'as_of', (select max(updated_at) from tv_contract_daily),
    'last_date', (select max(contract_date) from tv_contract_daily),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'project', c.project_name, 'is_nhc', c.kind = 'nhc', 'developer', i.developer, 'city', i.city,
        'sector', c.sec, 'dest', nullif(c.dest, ''), 'cnt', c.cnt, 'fin', c.fin, 'cash', c.cash
      ) order by c.cnt desc, c.project_name)
      from c left join info i using (project_name)
    ), '[]'::jsonb)
  );
$$;

-- ---------- المستهدفات: نفس get_dashboard_targets + مستهدف الإيراد لكل نطاق وقطاع ----------
create or replace function get_dashboard_targets(p_year int)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with s as (
    select scope, coalesce(sector,'غير محدد') as sector, sum(units) as u, sum(revenue) as rv, max(source) as src
    from dashboard_targets where year = p_year
    group by scope, coalesce(sector,'غير محدد')
  ),
  sc as (
    select scope, sum(u) as total, max(src) as source, jsonb_object_agg(sector, u) as by_sector,
           sum(rv) as rev_total, jsonb_object_agg(sector, rv) filter (where rv is not null) as rev_by_sector
    from s group by scope
  ),
  pc as (
    select scope, count(distinct project_name) as projects,
           -- مشاريع لها مستهدف وحدات بلا مستهدف إيراد (لا تدخل مستهدف الإيراد)
           coalesce(sum(units) filter (where revenue is null), 0) as rev_missing_units,
           count(distinct project_name) filter (where revenue is null and units > 0) as rev_missing_projects
    from dashboard_targets where year = p_year group by scope
  )
  select jsonb_build_object(
    'ok', true, 'year', p_year,
    'scopes', coalesce((
      select jsonb_object_agg(sc.scope, jsonb_build_object(
        'total', sc.total, 'projects', pc.projects, 'source', sc.source, 'by_sector', sc.by_sector,
        'rev_total', sc.rev_total, 'rev_by_sector', coalesce(sc.rev_by_sector, '{}'::jsonb),
        'rev_missing_units', pc.rev_missing_units, 'rev_missing_projects', pc.rev_missing_projects))
      from sc join pc using (scope)
    ), '{}'::jsonb)
  );
$$;
