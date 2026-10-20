-- ============================================================
-- SalesPlace — الحماية الموحّدة: جلسات الدخول، بوابة واحدة لكل الطلبات، صلاحية البيانات المالية،
-- وقطع كل النسخ السابقة من التطبيق عن قاعدة البيانات
-- ============================================================
-- ماذا يفعل:
--   1. login_v2  : دخول بالمستخدم وكلمة المرور ← رمز جلسة (token) ينتهي تلقائياً
--                  (المستخدم: 12 ساعة، ويُغلق بعد 90 دقيقة بلا نشاط · شاشة العرض: 30 يوماً، عرض فقط).
--                  قفل 15 دقيقة بعد 5 محاولات خاطئة. كل محاولة تُسجَّل في login_log.
--   2. api        : البوابة الوحيدة لكل الدوال — ترفض أي طلب بلا جلسة صالحة، وتفحص الصلاحية لكل دالة
--                  (user / fin / admin / self)، وتحذف الأرقام المالية من نتائج الدوال المختلطة لغير المصرّح له.
--   3. api_read   : البوابة الوحيدة لقراءة الجداول (بدل القراءة المباشرة عبر PostgREST).
--   4. can_fin    : عمود جديد في app_users — من يرى الإيرادات والتحصيل وقيم العقود ومبالغ التمويل والرواتب.
--                  الأدمن يراها دائماً. التغيير يُنهي جلسات المستخدم ليعيد الدخول.
--   5. السحب      : تُسحب كل صلاحيات مفتاح التطبيق (anon / authenticated / PUBLIC) عن كل الجداول والدوال،
--                  ولا يبقى متاحاً إلا: login_v2, api, api_read, get_app_state, admin_set_app_state, change_password, login (رسالة فقط).
--                  ⇒ أي نسخة سابقة من التطبيق تتوقف فوراً (login القديمة ترجع «نسخة قديمة» بلا مفتاح البيانات).
--
-- الترتيب: شغّل هذا الملف **بعد** نشر النسخة الجديدة من SalesPlace_01.html (النسخة القديمة تتوقف لحظة تشغيله).
-- للتراجع: app_security_rollback.sql (يعيد صلاحيات القراءة العامة ودالة login الأصلية).
-- آمن لإعادة التشغيل. يتطلّب app_users (username, pass_hash, is_admin, is_active) و app_secret(id=1, data_key).
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- 0. أعمدة وجداول مساندة (إن لم توجد) ----------
alter table app_users add column if not exists full_name text;
alter table app_users add column if not exists last_login timestamptz;
alter table app_users add column if not exists onboarded_at timestamptz;
alter table app_users add column if not exists permissions jsonb not null default
  '{"dest":true,"search":true,"deal":true,"cmp":true,"calc":true,"sales":true}'::jsonb;
alter table app_users add column if not exists can_fin boolean not null default false;   -- يرى البيانات المالية

create table if not exists login_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  username text,
  ok boolean not null default false,
  reason text
);
alter table login_log enable row level security;
create index if not exists login_log_user_at on login_log (username, at desc);

create table if not exists app_secret (id integer primary key, data_key text);
alter table app_secret enable row level security;

-- ---------- 1. الجلسات ----------
create table if not exists app_session (
  token text primary key,                       -- sha256 للرمز (الرمز نفسه لا يُحفظ)
  username text not null,
  kind text not null default 'user',            -- user | tv (شاشة عرض: عرض فقط)
  is_admin boolean not null default false,
  can_fin boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked boolean not null default false,
  ua text not null default ''
);
alter table app_session enable row level security;
create index if not exists app_session_user on app_session (username);

-- الدوال وصلاحياتها: user = أي جلسة · fin = جلسة بصلاحية مالية · admin = جلسة أدمن · self = الدالة تتحقق من كلمة المرور بنفسها
-- (دوال admin_* الحالية). ما ليس هنا: get_* ⇒ user، admin_* ⇒ self، غير ذلك مرفوض.
create table if not exists api_allow (fn text primary key, role text not null check (role in ('user', 'fin', 'admin', 'self')));
insert into api_allow (fn, role) values
  ('get_tv_prices', 'fin'), ('get_tv_revenue', 'fin'), ('get_tv_revenue_v2', 'fin'), ('tv_revenue_breakdown', 'fin'),
  ('get_my_permissions', 'self'), ('mark_onboarded', 'self'), ('mark_onboarded_v2', 'user'),
  ('dev_challenge_create', 'user'), ('dev_challenge_update', 'user'), ('dev_eval_score_upsert', 'user'),
  ('get_app_state', 'user')
on conflict (fn) do update set role = excluded.role;

-- مفاتيح مالية تُحذف من نتائج هذه الدوال لمن لا يملك صلاحية مالية (العدّادات تبقى)
create table if not exists api_fin_strip (fn text primary key, keys text[] not null);
insert into api_fin_strip (fn, keys) values
  ('get_tv_contracts', '{fin,cash}'),
  ('get_tv_period_projects', '{fin,cash}'),
  ('get_dashboard_targets', '{rev_total,rev_by_sector}'),
  ('get_tv_ops', '{vs,fa,sal,inst,dps,iks}')
on conflict (fn) do update set keys = excluded.keys;

-- الجداول المسموح قراءتها عبر api_read
create table if not exists api_read_allow (tbl text primary key);
insert into api_read_allow (tbl) values
  ('bank_rates'), ('dev_challenges'), ('dev_eval_criteria'), ('dev_eval_scores'), ('market_price_stats'), ('news_items'),
  ('project_blocked_stats'), ('project_dev_eval'), ('project_istisna_stats'), ('project_model_stats'), ('project_segment_stats'),
  ('project_support_offers'), ('sync_status'), ('unit_allocation_mirror'), ('unit_status'), ('unit_support_detail')
on conflict do nothing;

-- ---------- 2. أدوات ----------
create or replace function jsonb_strip_keys(j jsonb, keys text[])
returns jsonb
language plpgsql
immutable
as $$
begin
  if j is null then return null; end if;
  case jsonb_typeof(j)
    when 'object' then
      return coalesce((select jsonb_object_agg(e.k, jsonb_strip_keys(e.v, keys)) from jsonb_each(j) e(k, v) where not (e.k = any(keys))), '{}'::jsonb);
    when 'array' then
      return coalesce((select jsonb_agg(jsonb_strip_keys(e, keys)) from jsonb_array_elements(j) e), '[]'::jsonb);
    else
      return j;
  end case;
end;
$$;

create or replace function app_session_check(p_token text)
returns app_session
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  s app_session;
  h text;
begin
  if p_token is null or p_token = '' then raise exception 'SESSION_EXPIRED'; end if;
  h := encode(digest(p_token, 'sha256'), 'hex');
  select * into s from app_session where token = h;
  if not found or s.revoked or s.expires_at < now()
     or (s.kind = 'user' and s.last_seen < now() - interval '90 minutes') then
    raise exception 'SESSION_EXPIRED';
  end if;
  if not exists (select 1 from app_users where username = s.username and coalesce(is_active, true)) then
    raise exception 'SESSION_EXPIRED';
  end if;
  if s.last_seen < now() - interval '1 minute' then
    update app_session set last_seen = now() where token = h;
  end if;
  return s;
end;
$$;

-- ---------- 3. الدخول ----------
create or replace function login_v2(p_user text, p_pass text, p_kind text default 'user', p_ua text default '')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  u app_users%rowtype;
  v_fail int;
  v_tok text;
  v_kind text;
  v_exp timestamptz;
  v_perm jsonb;
  v_key text;
  v_admin boolean;
  v_fin boolean;
begin
  delete from login_log where at < now() - interval '30 days';
  delete from app_session where expires_at < now() - interval '7 days' or (revoked and created_at < now() - interval '7 days');
  p_user := lower(trim(coalesce(p_user, '')));

  select count(*) into v_fail from login_log
    where username = p_user and not ok and at > now() - interval '15 minutes';
  if v_fail >= 5 then
    insert into login_log (username, ok, reason) values (p_user, false, 'مقفل — محاولات كثيرة');
    return jsonb_build_object('ok', false, 'msg', 'محاولات خاطئة كثيرة — انتظر 15 دقيقة ثم أعد المحاولة');
  end if;

  select * into u from app_users where username = p_user;
  if not found then
    insert into login_log (username, ok, reason) values (p_user, false, 'مستخدم غير موجود');
    return jsonb_build_object('ok', false, 'msg', 'اسم المستخدم أو كلمة المرور غير صحيحة');
  end if;
  if not coalesce(u.is_active, true) then
    insert into login_log (username, ok, reason) values (u.username, false, 'حساب موقوف');
    return jsonb_build_object('ok', false, 'msg', 'هذا الحساب موقوف — راجع مدير النظام');
  end if;
  if u.pass_hash is null or u.pass_hash <> crypt(coalesce(p_pass, ''), u.pass_hash) then
    insert into login_log (username, ok, reason) values (u.username, false, 'كلمة مرور خاطئة');
    return jsonb_build_object('ok', false, 'msg', 'اسم المستخدم أو كلمة المرور غير صحيحة');
  end if;

  v_kind := case when p_kind = 'tv' then 'tv' else 'user' end;
  v_exp := case when v_kind = 'tv' then now() + interval '30 days' else now() + interval '12 hours' end;
  -- شاشة العرض: جلسة طويلة لكنها عرض فقط (لا إدارة ولا بيانات مالية) حتى لو كان الحساب أدمن
  v_admin := v_kind = 'user' and coalesce(u.is_admin, false);
  v_fin := v_kind = 'user' and (coalesce(u.is_admin, false) or coalesce(u.can_fin, false));
  v_tok := encode(gen_random_bytes(32), 'hex');
  insert into app_session (token, username, kind, is_admin, can_fin, expires_at, ua)
  values (encode(digest(v_tok, 'sha256'), 'hex'), u.username, v_kind, v_admin, v_fin, v_exp, left(coalesce(p_ua, ''), 200));

  update app_users set last_login = now() where username = u.username;
  insert into login_log (username, ok, reason) values (u.username, true, case when v_kind = 'tv' then 'دخول شاشة عرض' else 'دخول ناجح' end);
  select data_key into v_key from app_secret where id = 1;
  v_perm := case when coalesce(u.is_admin, false) then '{"dest":true,"search":true,"deal":true,"cmp":true,"calc":true,"sales":true,"devmgmt":true,"supply":true}'::jsonb
                 else coalesce(u.permissions, '{}'::jsonb) end;

  return jsonb_build_object('ok', true, 'token', v_tok, 'user', u.username, 'name', coalesce(u.full_name, u.username),
    'admin', v_admin, 'fin', v_fin, 'kind', v_kind, 'perms', v_perm, 'onboarded', u.onboarded_at is not null,
    'expires', v_exp, 'key', v_key);
end;
$$;

-- دالة الدخول القديمة: تبقى قابلة للنداء لكنها لا تفتح شيئاً — النسخ السابقة ترى رسالة واضحة
create or replace function login(p_user text, p_pass text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
  insert into login_log (username, ok, reason) values (lower(trim(coalesce(p_user, ''))), false, 'نسخة قديمة من التطبيق');
  return json_build_object('ok', false, 'msg', 'هذه نسخة قديمة من التطبيق ولم تعد تعمل — افتح الرابط الجديد الموحّد (SalesPlace) ثم سجّل الدخول');
end;
$function$;

-- ---------- 4. البوابة: كل الدوال ----------
create or replace function api(p_token text, p_fn text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  s app_session;
  v_role text;
  v_fin boolean;
  v_keys text[];
  p record;
  v_args text := '';
  v_sql text;
  v_res jsonb;
  i int;
  an text;
  tn text;
  u app_users%rowtype;
begin
  p_args := coalesce(p_args, '{}'::jsonb);
  s := app_session_check(p_token);
  v_fin := s.is_admin or s.can_fin;

  -- طلبات الجلسة نفسها
  if p_fn = 'session_info' then
    select * into u from app_users where username = s.username;
    return jsonb_build_object('ok', true, 'user', s.username, 'name', coalesce(u.full_name, s.username), 'admin', s.is_admin, 'fin', v_fin,
      'kind', s.kind, 'expires', s.expires_at, 'onboarded', u.onboarded_at is not null,
      'perms', case when s.is_admin then '{"dest":true,"search":true,"deal":true,"cmp":true,"calc":true,"sales":true,"devmgmt":true,"supply":true}'::jsonb
                    else coalesce(u.permissions, '{}'::jsonb) end,
      'key', (select data_key from app_secret where id = 1));
  elsif p_fn = 'logout' then
    update app_session set revoked = true where token = s.token;
    return jsonb_build_object('ok', true);
  end if;

  v_role := coalesce((select role from api_allow where fn = p_fn),
                     case when p_fn like 'get\_%' then 'user' when p_fn like 'admin\_%' then 'self' else null end);
  if v_role is null then raise exception 'API_DENIED: %', p_fn; end if;
  if v_role = 'fin' and not v_fin then raise exception 'API_FIN'; end if;
  if v_role = 'admin' and not s.is_admin then raise exception 'API_ADMIN'; end if;

  perform set_config('app.user', s.username, true);
  perform set_config('app.fin', case when v_fin then 'on' else 'off' end, true);
  perform set_config('app.admin', case when s.is_admin then 'on' else 'off' end, true);

  -- اختيار النسخة (overload) التي تطابق أسماء المعاملات المرسلة
  select pr.oid, pr.proargnames, pr.proargtypes, pr.pronargs, pr.pronargdefaults, pr.proretset, pr.prorettype
    into p
  from pg_proc pr
  where pr.pronamespace = 'public'::regnamespace and pr.proname = p_fn and pr.prokind = 'f'
  order by (select count(*) from unnest(coalesce(pr.proargnames, '{}'::text[])) a where p_args ? a) desc, pr.pronargs asc
  limit 1;
  if p.oid is null then raise exception 'API_NOFN: %', p_fn; end if;

  for i in 1..coalesce(p.pronargs, 0) loop
    an := p.proargnames[i];
    tn := format_type(p.proargtypes[i - 1], null);
    if an is null or an = '' then raise exception 'API_ARGS: %', p_fn; end if;
    if not (p_args ? an) then
      if i > p.pronargs - p.pronargdefaults then continue; end if;   -- له قيمة افتراضية
      v_args := v_args || case when v_args = '' then '' else ', ' end || format('%I := null', an);
      continue;
    end if;
    v_args := v_args || case when v_args = '' then '' else ', ' end ||
      case
        when tn in ('json', 'jsonb') then format('%I := ($1->%L)::%s', an, an, tn)
        when tn like '%[]' then format('%I := (select array_agg(x::%s) from jsonb_array_elements_text($1->%L) x)', an, left(tn, length(tn) - 2), an)
        else format('%I := ($1->>%L)::%s', an, an, tn)
      end;
  end loop;
  v_sql := format('public.%I(%s)', p_fn, v_args);

  if p.prorettype = 'void'::regtype then
    execute 'select ' || v_sql using p_args;
    v_res := '{"ok":true}'::jsonb;
  elsif p.proretset then
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from %s t', v_sql) into v_res using p_args;
  elsif p.prorettype in ('json'::regtype, 'jsonb'::regtype) then
    execute format('select (%s)::jsonb', v_sql) into v_res using p_args;
  else
    execute format('select to_jsonb(%s)', v_sql) into v_res using p_args;
  end if;

  if not v_fin then
    select keys into v_keys from api_fin_strip where fn = p_fn;
    if v_keys is not null then v_res := jsonb_strip_keys(v_res, v_keys); end if;
  end if;
  return v_res;
end;
$$;

-- ---------- 5. البوابة: قراءة الجداول ----------
-- p_params مثل PostgREST: {"select":"a,b","order":"a.asc,b.desc","limit":"2000","offset":"0","col":"eq.value","col2":"ilike.%x%"}
create or replace function api_read(p_token text, p_table text, p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  s app_session;
  v_cols text := '*';
  v_where text := '';
  v_order text := '';
  v_lim int := 2000;
  v_off int := 0;
  v_res jsonb;
  e record;
  c text;
  op text;
  val text;
  parts text[];
begin
  p_params := coalesce(p_params, '{}'::jsonb);
  s := app_session_check(p_token);
  if not exists (select 1 from api_read_allow where tbl = p_table) then raise exception 'API_DENIED: %', p_table; end if;
  if to_regclass('public.' || quote_ident(p_table)) is null then raise exception 'API_NOTABLE: %', p_table; end if;

  if coalesce(p_params->>'select', '*') <> '*' then
    select string_agg(quote_ident(trim(x)), ', ') into v_cols
    from unnest(string_to_array(p_params->>'select', ',')) x
    where exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = p_table and column_name = trim(x));
    if v_cols is null then raise exception 'API_COLS'; end if;
  end if;
  if p_params ? 'order' then
    select string_agg(quote_ident(split_part(trim(x), '.', 1)) || case when lower(split_part(trim(x), '.', 2)) = 'desc' then ' desc' else ' asc' end, ', ')
      into v_order
    from unnest(string_to_array(p_params->>'order', ',')) x
    where exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = p_table and column_name = split_part(trim(x), '.', 1));
    v_order := coalesce(' order by ' || nullif(v_order, ''), '');
  end if;
  v_lim := least(coalesce(nullif(p_params->>'limit', '')::int, 2000), 5000);
  v_off := greatest(coalesce(nullif(p_params->>'offset', '')::int, 0), 0);

  for e in select k, v from jsonb_each_text(p_params) t(k, v) loop
    if e.k in ('select', 'order', 'limit', 'offset') then continue; end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = p_table and column_name = e.k) then
      raise exception 'API_COL: %', e.k;
    end if;
    op := split_part(e.v, '.', 1);
    val := substr(e.v, length(op) + 2);
    c := quote_ident(e.k);
    v_where := v_where || case when v_where = '' then ' where ' else ' and ' end ||
      case op
        when 'eq' then format('%s = %L', c, val)
        when 'neq' then format('%s <> %L', c, val)
        when 'gt' then format('%s > %L', c, val)
        when 'gte' then format('%s >= %L', c, val)
        when 'lt' then format('%s < %L', c, val)
        when 'lte' then format('%s <= %L', c, val)
        when 'like' then format('%s like %L', c, replace(val, '*', '%'))
        when 'ilike' then format('%s ilike %L', c, replace(val, '*', '%'))
        when 'is' then format('%s is %s', c, case when val in ('null', 'true', 'false') then val else 'null' end)
        else null
      end;
    if v_where is null then raise exception 'API_OP: %', op; end if;
  end loop;

  execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select %s from public.%I%s%s limit %s offset %s) t',
                 v_cols, p_table, v_where, v_order, v_lim, v_off) into v_res;
  return v_res;
end;
$$;

-- ---------- 6. دوال تعتمد على الجلسة (لا تحتاج كلمة المرور) ----------
-- الإيرادات بالجلسة (تتطلّب صلاحية مالية عبر البوابة) — نفس tv_revenue_data من tv_revenue.sql
create or replace function get_tv_revenue_v2(p_year int, p_month int)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  if current_setting('app.fin', true) is distinct from 'on' then
    return jsonb_build_object('ok', false, 'auth', false, 'msg', 'لا تملك صلاحية عرض البيانات المالية');
  end if;
  return tv_revenue_data(p_year, p_month);
end;
$$;

create or replace function mark_onboarded_v2()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if coalesce(current_setting('app.user', true), '') = '' then return jsonb_build_object('ok', false); end if;
  update app_users set onboarded_at = coalesce(onboarded_at, now()) where username = current_setting('app.user', true);
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------- 7. إدارة: الصلاحية المالية والجلسات (تتحقق من كلمة مرور الأدمن مثل بقية admin_*) ----------
create or replace function admin_list_users_v3(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare v_admin boolean;
begin
  select is_admin into v_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true) limit 1;
  if v_admin is not true then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  return jsonb_build_object('ok', true, 'users', coalesce((
    select jsonb_agg(jsonb_build_object('username', username, 'full_name', coalesce(full_name, username), 'is_admin', coalesce(is_admin, false),
      'is_active', coalesce(is_active, true), 'last_login', last_login, 'can_fin', coalesce(can_fin, false),
      'permissions', coalesce(permissions, '{}'::jsonb),
      'sessions', (select count(*) from app_session s where s.username = u.username and not s.revoked and s.expires_at > now()
                   and (s.kind = 'tv' or s.last_seen > now() - interval '90 minutes'))) order by username)
    from app_users u), '[]'::jsonb));
end;
$$;

create or replace function admin_set_fin(p_admin text, p_pass text, p_target text, p_fin boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare v_admin boolean;
begin
  select is_admin into v_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true) limit 1;
  if v_admin is not true then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  update app_users set can_fin = coalesce(p_fin, false) where username = p_target;
  if not found then return jsonb_build_object('ok', false, 'msg', 'المستخدم غير موجود'); end if;
  update app_session set revoked = true where username = p_target and kind = 'user';   -- يعيد الدخول بالصلاحية الجديدة
  return jsonb_build_object('ok', true, 'msg', case when p_fin then 'صار يرى البيانات المالية' else 'لم يعد يرى البيانات المالية' end || ' — سيُطلب منه الدخول من جديد');
end;
$$;

create or replace function admin_sessions(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare v_admin boolean;
begin
  select is_admin into v_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true) limit 1;
  if v_admin is not true then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  return jsonb_build_object('ok', true, 'sessions', coalesce((
    select jsonb_agg(jsonb_build_object('id', left(token, 12), 'user', username, 'kind', kind, 'admin', is_admin, 'fin', can_fin,
      'since', created_at, 'last_seen', last_seen, 'expires', expires_at, 'ua', ua) order by last_seen desc)
    from app_session where not revoked and expires_at > now() and (kind = 'tv' or last_seen > now() - interval '90 minutes')), '[]'::jsonb));
end;
$$;

-- p_id: أول 12 خانة من معرّف الجلسة (من admin_sessions) — أو اسم مستخدم لإنهاء كل جلساته
create or replace function admin_revoke_session(p_admin text, p_pass text, p_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare v_admin boolean; v_n int;
begin
  select is_admin into v_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true) limit 1;
  if v_admin is not true then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  update app_session set revoked = true where not revoked and (left(token, 12) = p_id or username = p_id);
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'count', v_n, 'msg', 'أُنهيت ' || v_n || ' جلسة');
end;
$$;

-- ---------- 8. سحب كل الصلاحيات عن مفتاح التطبيق، وإبقاء البوابة فقط ----------
do $$
declare r record; v_roles text;
begin
  v_roles := 'public'
    || case when to_regrole('anon') is not null then ', anon' else '' end
    || case when to_regrole('authenticated') is not null then ', authenticated' else '' end;
  for r in select format('%I.%I', n.nspname, c.relname) as obj from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
             and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e') loop
    execute format('revoke all on table %s from %s', r.obj, v_roles);
  end loop;
  for r in select format('%I.%I', n.nspname, c.relname) as obj from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'S' loop
    execute format('revoke all on sequence %s from %s', r.obj, v_roles);
  end loop;
  for r in select p.oid::regprocedure::text as obj from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind in ('f', 'p')
             and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e') loop
    execute format('revoke all on function %s from %s', r.obj, v_roles);
  end loop;
  -- الدوال الجديدة مستقبلاً لا تأخذ صلاحية تلقائية لمفتاح التطبيق
  execute format('alter default privileges in schema public revoke execute on functions from %s', v_roles);
  execute format('alter default privileges in schema public revoke all on tables from %s', v_roles);
  -- ما يبقى متاحاً
  for r in select unnest(array[
      'login_v2(text, text, text, text)', 'api(text, text, jsonb)', 'api_read(text, text, jsonb)',
      'get_app_state()', 'admin_set_app_state(text, text, boolean, text)', 'login(text, text)', 'change_password(text, text, text)']) as obj loop
    begin
      execute format('grant execute on function %s to %s', r.obj, v_roles);
    exception when undefined_function then
      raise notice 'غير موجودة (تُتجاهل): %', r.obj;
    end;
  end loop;
end $$;

-- إيقاف التطبيق (app_control.sql) يسحب البوابة أيضاً ثم يعيدها — لا تغيير مطلوب هناك
notify pgrst, 'reload schema';

-- فحص سريع بعد التشغيل:
--   select login_v2('اسمك', 'كلمة المرور');                       -- ok:true + token
--   select api('<token>', 'get_live_board');                       -- نتيجة الدالة
--   select api_read('<token>', 'sync_status', '{"select":"last_synced_at","limit":"1"}');
--   select login('x', 'y');                                        -- رسالة «نسخة قديمة»
--   select * from admin_sessions('اسمك', 'كلمة المرور');
