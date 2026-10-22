-- ============================================================
-- SalesPlace — النسخ الاحتياطي من داخل التطبيق (زر «⬇ نسخة احتياطية» في نافذة «⬆ رفع ملف»)
-- ============================================================
-- الأدمن يضغط الزر فينزل ملف واحد مضغوط (nhc_backup_….json.gz) فيه كل جداول schema public وبياناتها
-- (عدا جلسات الدخول app_session — مؤقتة). الاستعادة من نفس النافذة: «استعادة من نسخة» (تستبدل محتوى الجداول بالكامل).
-- كل الدوال تتحقق من حساب الأدمن وكلمة مروره (crypt)، وتُستدعى عبر البوابة api مثل باقي admin_*.
-- يتطلّب: app_security.sql. آمن لإعادة التشغيل. شغّل app_security.sql بعده مرة لتبقى الصلاحيات مضبوطة.
-- ملاحظة: الدوال (functions) لا تُنسخ هنا — هي في ملفات SQL بالمستودع. هذه نسخة للبيانات.
-- ============================================================

create or replace function app_backup_is_admin(p_admin text, p_pass text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'extensions'
as $$
  select coalesce((select is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true) limit 1), false);
$$;
revoke all on function app_backup_is_admin(text, text) from public;

-- الجداول المشمولة (ترتيب الاستعادة: الجدول المُشار إليه بمفتاح أجنبي قبل الجدول الذي يشير إليه)
create or replace function app_backup_tables()
returns table (name text, lvl int)
language sql
stable
security definer
set search_path to 'public'
as $$
  with recursive t as (
    select c.oid, c.relname::text as name from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relname not in ('app_session')
      and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
  ), dep as (
    select t.oid, 0 as lvl from t
    union all
    select k.conrelid, dep.lvl + 1 from pg_constraint k join dep on k.confrelid = dep.oid
    where k.contype = 'f' and k.conrelid <> k.confrelid and dep.lvl < 20
  )
  select t.name, max(dep.lvl)::int from t join dep on dep.oid = t.oid group by t.name order by 2, 1;
$$;
revoke all on function app_backup_tables() from public;

-- قائمة الجداول وعدد صفوفها
create or replace function admin_backup_list(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare r record; v_n bigint; v_out jsonb := '[]'::jsonb;
begin
  if not app_backup_is_admin(p_admin, p_pass) then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  for r in select * from app_backup_tables() loop
    /* الجداول الكبيرة: تقدير سريع (للعرض فقط — النسخ نفسه يقرأ كل الصفوف) */
    select case when c.reltuples >= 20000 then c.reltuples::bigint else null end into v_n from pg_class c where c.oid = format('public.%I', r.name)::regclass;
    if v_n is null then execute format('select count(*) from public.%I', r.name) into v_n; end if;
    v_out := v_out || jsonb_build_object('name', r.name, 'rows', v_n, 'lvl', r.lvl);
  end loop;
  return jsonb_build_object('ok', true, 'at', now(), 'db', current_database(), 'tables', v_out);
end;
$$;

-- صفحة من جدول (ترقيم بموقع الصف ctid — ثابت أثناء النسخ): p_after = آخر ctid من الصفحة السابقة ('' للبداية)
create or replace function admin_backup_rows(p_admin text, p_pass text, p_table text, p_after text default '', p_limit int default 2000)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare v_rows jsonb; v_last text; v_lim int := least(greatest(coalesce(p_limit, 2000), 1), 5000);
begin
  if not app_backup_is_admin(p_admin, p_pass) then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  if not exists (select 1 from app_backup_tables() t where t.name = p_table) then return jsonb_build_object('ok', false, 'msg', 'جدول غير معروف'); end if;
  execute format(
    'with p as (select ctid as k, to_jsonb(x) as j from public.%I x where ($1 = '''' or ctid > $1::tid) order by ctid limit $2)
     select coalesce(jsonb_agg(j order by k), ''[]''::jsonb), (select max(k)::text from p) from p', p_table)
    into v_rows, v_last using coalesce(p_after, ''), v_lim;
  return jsonb_build_object('ok', true, 'rows', v_rows, 'last', v_last, 'done', jsonb_array_length(v_rows) < v_lim);
end;
$$;

-- الاستعادة: p_reset يفرّغ الجدول أولاً، ثم تُدرج الصفوف كما هي (دفعات 1000 صف من التطبيق).
-- الأعمدة غير الموجودة في النسخة تأخذ قيمتها الافتراضية؛ الأعمدة الزائدة في النسخة تُهمل.
-- app_users: دمج بالاسم (لا تفريغ) — والتطبيق يستعيده آخراً.
create or replace function admin_backup_restore(p_admin text, p_pass text, p_table text, p_rows jsonb, p_reset boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare v_cols text; v_n int;
begin
  if not app_backup_is_admin(p_admin, p_pass) then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  if not exists (select 1 from app_backup_tables() t where t.name = p_table) then return jsonb_build_object('ok', false, 'msg', 'جدول غير موجود في القاعدة: ' || p_table); end if;
  /* جدول المستخدمين لا يُفرّغ أبداً (حتى لا يُقفل الأدمن أثناء الاستعادة): يُستبدل فقط المستخدمون الموجودون في النسخة، ويبقى غيرهم */
  if p_table = 'app_users' then
    if p_rows is null or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('ok', true, 'count', 0, 'more', false); end if;
    delete from app_users u where u.username in (select e->>'username' from jsonb_array_elements(p_rows) e);
    /* حساب الاستعادة المؤقت (من سكربت إعادة البناء) يُحذف بانتهاء الاستعادة — جلسته الحالية تبقى حتى الخروج */
    delete from app_users u where u.username = 'restore_tmp';
    p_reset := false;
  end if;
  /* التفريغ: TRUNCATE فوري إن لم يُشر إليه جدول آخر، وإلا حذف على دفعات (20 ألفاً) حتى لا يتجاوز مهلة الطلب — يكرّره التطبيق ما دام more=true */
  if p_reset then
    if not exists (select 1 from pg_constraint k where k.contype = 'f' and k.confrelid = format('public.%I', p_table)::regclass and k.conrelid <> k.confrelid) then
      execute format('truncate table public.%I', p_table);
    else
      execute format('delete from public.%I where ctid in (select ctid from public.%I limit 20000)', p_table, p_table);
      get diagnostics v_n = row_count;
      if v_n >= 20000 then return jsonb_build_object('ok', true, 'count', 0, 'more', true); end if;
    end if;
  end if;
  if p_rows is null or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('ok', true, 'count', 0, 'more', false); end if;
  /* الأعمدة المشتركة بين الجدول والنسخة فقط (عدا المحسوبة) */
  select string_agg(format('%I', a.attname), ', ' order by a.attnum) into v_cols
  from pg_attribute a
  where a.attrelid = format('public.%I', p_table)::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
    and exists (select 1 from jsonb_array_elements(p_rows) e where e ? a.attname limit 1);
  if v_cols is null then return jsonb_build_object('ok', false, 'msg', 'لا أعمدة مطابقة في ' || p_table); end if;
  execute format('insert into public.%I (%s) overriding system value select %s from jsonb_populate_recordset(null::public.%I, $1)', p_table, v_cols, v_cols, p_table)
    using p_rows;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;

-- بعد الاستعادة: إعادة ضبط عدّادات المعرّفات (serial/identity) على أعلى قيمة
create or replace function admin_backup_fix_sequences(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare r record; v_max bigint; v_n int := 0;
begin
  if not app_backup_is_admin(p_admin, p_pass) then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  for r in
    select c.relname as tbl, a.attname as col, pg_get_serial_sequence(format('public.%I', c.relname), a.attname) as seq
    from pg_class c join pg_namespace n on n.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid
    where n.nspname = 'public' and c.relkind in ('r', 'p') and a.attnum > 0 and not a.attisdropped
      and pg_get_serial_sequence(format('public.%I', c.relname), a.attname) is not null
  loop
    execute format('select max(%I)::bigint from public.%I', r.col, r.tbl) into v_max;
    if v_max is not null then perform setval(r.seq, v_max, true); v_n := v_n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;

notify pgrst, 'reload schema';

-- ============================================================
-- هيكل القاعدة كاملاً (يُحفظ داخل ملف النسخة) — لإعادة البناء في مشروع Supabase جديد إن ضاع الحساب
-- ============================================================
-- يولّد سكربت SQL واحداً قابلاً لإعادة التشغيل: الإضافات، الأنواع، العدّادات، الجداول وقيودها وفهارسها، RLS،
-- كل الدوال، العروض، المشغّلات، السياسات، والصلاحيات كما هي الآن (البوابة login_v2/api/api_read فقط لمفتاح التطبيق).
-- وفي آخره سطر حساب أدمن مؤقت restore_tmp (كلمة مروره يكتبها المستخدم في أداة إعادة البناء) يُحذف تلقائياً بعد الاستعادة.
create or replace function app_backup_schema_sql()
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_catalog'
as $fn$
declare
  o text := ''; r record; c record; v text; v2 text; nl text := E'\n';
  ext_ok text[] := array['pgcrypto', 'uuid-ossp', 'pg_trgm', 'unaccent', 'citext'];
begin
  o := o || '-- SalesPlace — إعادة بناء القاعدة (مولّد تلقائياً من النسخة الاحتياطية بتاريخ ' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' || nl
         || '-- شغّله كاملاً في Supabase → SQL Editor بمشروع جديد. آمن لإعادة التشغيل.' || nl
         || 'set check_function_bodies = off;' || nl || 'set client_min_messages = warning;' || nl || 'set search_path = public, extensions;' || nl
         || 'create schema if not exists extensions;' || nl || nl;
  /* الإضافات */
  for r in select extname from pg_extension where extname = any(ext_ok) order by 1 loop
    o := o || format('create extension if not exists %I with schema extensions;', r.extname) || nl;
  end loop;
  /* أنواع enum */
  for r in select t.typname, string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder) as labels
           from pg_type t join pg_namespace n on n.oid = t.typnamespace join pg_enum e on e.enumtypid = t.oid
           where n.nspname = 'public' group by t.typname loop
    o := o || format('do $x$ begin create type public.%I as enum (%s); exception when duplicate_object then null; end $x$;', r.typname, r.labels) || nl;
  end loop;
  /* العدّادات (غير التابعة لأعمدة identity) */
  for r in select c2.relname from pg_class c2 join pg_namespace n on n.oid = c2.relnamespace
           where n.nspname = 'public' and c2.relkind = 'S'
             and not exists (select 1 from pg_depend d where d.objid = c2.oid and d.deptype = 'i') order by 1 loop
    o := o || format('create sequence if not exists public.%I;', r.relname) || nl;
  end loop;
  o := o || nl;
  /* الجداول */
  for r in select c2.oid, c2.relname, c2.relrowsecurity from pg_class c2 join pg_namespace n on n.oid = c2.relnamespace
           where n.nspname = 'public' and c2.relkind = 'r'
             and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c2.oid and d.deptype = 'e') order by 2 loop
    select string_agg(format('  %I %s%s%s%s', a.attname, format_type(a.atttypid, a.atttypmod),
             case a.attidentity when 'a' then ' generated always as identity' when 'd' then ' generated by default as identity' else '' end,
             case when a.attgenerated = 's' then ' generated always as (' || pg_get_expr(d.adbin, d.adrelid) || ') stored'
                  when d.adbin is not null then ' default ' || pg_get_expr(d.adbin, d.adrelid) else '' end,
             case when a.attnotnull then ' not null' else '' end), ',' || nl order by a.attnum)
      into v
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped;
    o := o || format('create table if not exists public.%I (', r.relname) || nl || coalesce(v, '') || nl || ');' || nl;
    /* أعمدة أُضيفت لاحقاً لجدول موجود مسبقاً */
    for c in select a.attname, format_type(a.atttypid, a.atttypmod) as typ, pg_get_expr(d.adbin, d.adrelid) as def, a.attgenerated, a.attidentity
             from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped and a.attidentity = '' and a.attgenerated = '' order by a.attnum loop
      o := o || format('alter table public.%I add column if not exists %I %s%s;', r.relname, c.attname, c.typ, case when c.def is not null then ' default ' || c.def else '' end) || nl;
    end loop;
    if r.relrowsecurity then o := o || format('alter table public.%I enable row level security;', r.relname) || nl; end if;
    o := o || nl;
  end loop;
  /* القيود: المفاتيح والتفرّد والتحقق، ثم المفاتيح الأجنبية */
  for r in select k.conname, c2.relname, pg_get_constraintdef(k.oid) as def, k.contype
           from pg_constraint k join pg_class c2 on c2.oid = k.conrelid join pg_namespace n on n.oid = c2.relnamespace
           where n.nspname = 'public' and c2.relkind = 'r' and k.contype in ('p', 'u', 'c', 'x', 'f')
           order by case k.contype when 'f' then 1 else 0 end, c2.relname, k.conname loop
    o := o || format('do $x$ begin alter table public.%I add constraint %I %s; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $x$;',
                     r.relname, r.conname, r.def) || nl;
  end loop;
  /* الفهارس (غير المرتبطة بقيد) */
  for r in select pg_get_indexdef(i.indexrelid) as def from pg_index i join pg_class c2 on c2.oid = i.indrelid join pg_namespace n on n.oid = c2.relnamespace
           where n.nspname = 'public' and c2.relkind = 'r' and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid) order by 1 loop
    o := o || regexp_replace(r.def, '^CREATE (UNIQUE )?INDEX ', 'CREATE \1INDEX IF NOT EXISTS ') || ';' || nl;
  end loop;
  /* ملكية العدّادات (serial) */
  for r in select s.relname as seq, t.relname as tbl, a.attname
           from pg_depend d join pg_class s on s.oid = d.objid and s.relkind = 'S' join pg_class t on t.oid = d.refobjid
           join pg_attribute a on a.attrelid = t.oid and a.attnum = d.refobjsubid join pg_namespace n on n.oid = s.relnamespace
           where n.nspname = 'public' and d.deptype = 'a' loop
    o := o || format('alter sequence public.%I owned by public.%I.%I;', r.seq, r.tbl, r.attname) || nl;
  end loop;
  o := o || nl || '-- ===== الدوال =====' || nl;
  for r in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind in ('f', 'p')
             and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e') order by p.proname, p.oid loop
    o := o || pg_get_functiondef(r.oid) || ';' || nl || nl;
  end loop;
  /* العروض */
  for r in select c2.relname, c2.relkind, pg_get_viewdef(c2.oid, true) as def from pg_class c2 join pg_namespace n on n.oid = c2.relnamespace
           where n.nspname = 'public' and c2.relkind in ('v', 'm') order by c2.oid loop
    o := o || case when r.relkind = 'v' then format('create or replace view public.%I as %s', r.relname, rtrim(r.def, ';'))
                   else format('create materialized view if not exists public.%I as %s with no data', r.relname, rtrim(r.def, ';')) end || ';' || nl;
  end loop;
  /* المشغّلات */
  for r in select t.tgname, c2.relname, pg_get_triggerdef(t.oid) as def from pg_trigger t join pg_class c2 on c2.oid = t.tgrelid join pg_namespace n on n.oid = c2.relnamespace
           where n.nspname = 'public' and not t.tgisinternal order by 2, 1 loop
    o := o || format('drop trigger if exists %I on public.%I;', r.tgname, r.relname) || nl || r.def || ';' || nl;
  end loop;
  /* سياسات RLS */
  for r in select pol.polname, c2.relname, pol.polpermissive, pol.polcmd,
                  coalesce((select string_agg(case when x = 0 then 'public' else quote_ident(rolname) end, ', ') from unnest(pol.polroles) x left join pg_roles ro on ro.oid = x), 'public') as roles,
                  pg_get_expr(pol.polqual, pol.polrelid) as q, pg_get_expr(pol.polwithcheck, pol.polrelid) as wc
           from pg_policy pol join pg_class c2 on c2.oid = pol.polrelid join pg_namespace n on n.oid = c2.relnamespace where n.nspname = 'public' loop
    o := o || format('do $x$ begin create policy %I on public.%I as %s for %s to %s%s%s; exception when duplicate_object then null; end $x$;',
      r.polname, r.relname, case when r.polpermissive then 'permissive' else 'restrictive' end,
      case r.polcmd when 'r' then 'select' when 'a' then 'insert' when 'w' then 'update' when 'd' then 'delete' else 'all' end, r.roles,
      case when r.q is not null then ' using (' || r.q || ')' else '' end, case when r.wc is not null then ' with check (' || r.wc || ')' else '' end) || nl;
  end loop;
  /* الصلاحيات كما هي الآن: سحب الكل ثم منح ما هو ممنوح فعلاً لمفتاح التطبيق */
  o := o || nl || '-- ===== الصلاحيات =====' || nl
    || 'do $x$ declare v text := ''public'' || case when to_regrole(''anon'') is not null then '', anon'' else '''' end || case when to_regrole(''authenticated'') is not null then '', authenticated'' else '''' end; begin' || nl
    || '  execute format(''revoke all on all tables in schema public from %s'', v);' || nl
    || '  execute format(''revoke all on all sequences in schema public from %s'', v);' || nl
    || '  execute format(''revoke all on all functions in schema public from %s'', v);' || nl
    || '  execute format(''alter default privileges in schema public revoke all on tables from %s'', v);' || nl
    || '  execute format(''alter default privileges in schema public revoke all on functions from %s'', v);' || nl
    || 'end $x$;' || nl;
  for r in select c2.relname, a.privilege_type, case when a.grantee = 0 then 'public' else quote_ident(g.rolname) end as who
           from pg_class c2 join pg_namespace n on n.oid = c2.relnamespace, aclexplode(c2.relacl) a left join pg_roles g on g.oid = a.grantee
           where n.nspname = 'public' and c2.relkind in ('r', 'v', 'm') and (a.grantee = 0 or g.rolname in ('anon', 'authenticated')) loop
    o := o || format('do $x$ begin grant %s on public.%I to %s; exception when undefined_object then null; end $x$;', r.privilege_type, r.relname, r.who) || nl;
  end loop;
  for r in select p.oid::regprocedure::text as f, case when a.grantee = 0 then 'public' else quote_ident(g.rolname) end as who
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a left join pg_roles g on g.oid = a.grantee
           where n.nspname = 'public' and p.prokind in ('f', 'p') and a.privilege_type = 'EXECUTE' and (a.grantee = 0 or g.rolname in ('anon', 'authenticated'))
             and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e') loop
    o := o || format('do $x$ begin grant execute on function %s to %s; exception when undefined_object then null; end $x$;', r.f, r.who) || nl;
  end loop;
  /* حساب أدمن مؤقت للدخول وتشغيل الاستعادة (يُحذف تلقائياً بعد استعادة المستخدمين) */
  if to_regclass('public.app_users') is not null then
    select string_agg(quote_ident(a.attname), ', ' order by a.attnum),
           string_agg(case a.attname when 'username' then '''restore_tmp''' when 'pass_hash' then 'crypt(''__TEMP_PASSWORD__'', gen_salt(''bf''))'
                        when 'is_admin' then 'true' when 'is_active' then 'true' when 'full_name' then '''حساب الاستعادة المؤقت'''
                        else case when a.atttypid = 'bool'::regtype then 'false' when a.atttypid in ('int2'::regtype, 'int4'::regtype, 'int8'::regtype, 'numeric'::regtype, 'float8'::regtype) then '0'
                                  when a.atttypid in ('timestamptz'::regtype, 'timestamp'::regtype, 'date'::regtype) then 'now()' when a.atttypid in ('json'::regtype, 'jsonb'::regtype) then '''{}''' else '''''' end end, ', ' order by a.attnum)
      into v, v2
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = 'public.app_users'::regclass and a.attnum > 0 and not a.attisdropped and a.attidentity = '' and a.attgenerated = ''
        and (a.attname in ('username', 'pass_hash', 'is_admin', 'is_active', 'full_name') or (a.attnotnull and d.adbin is null));
    o := o || nl || '-- ===== حساب الاستعادة المؤقت =====' || nl
      || format('insert into public.app_users (%s) select %s where not exists (select 1 from public.app_users where username = ''restore_tmp'');', v, v2) || nl;
  end if;
  o := o || nl || 'notify pgrst, ''reload schema'';' || nl;
  return o;
end;
$fn$;
revoke all on function app_backup_schema_sql() from public;

create or replace function admin_backup_schema(p_admin text, p_pass text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
begin
  if not app_backup_is_admin(p_admin, p_pass) then return jsonb_build_object('ok', false, 'msg', 'هذا الإجراء يتطلب صلاحية مدير'); end if;
  return jsonb_build_object('ok', true, 'sql', app_backup_schema_sql());
end;
$$;

/* كل الاستدعاءات تمرّ عبر البوابة api (مالكها يملك الدوال) — لا تُستدعى مباشرة بمفتاح التطبيق */
do $$
declare f text; v text := 'public' || case when to_regrole('anon') is not null then ', anon' else '' end || case when to_regrole('authenticated') is not null then ', authenticated' else '' end;
begin
  foreach f in array array['admin_backup_list(text,text)', 'admin_backup_rows(text,text,text,text,integer)', 'admin_backup_restore(text,text,text,jsonb,boolean)',
                           'admin_backup_fix_sequences(text,text)', 'admin_backup_schema(text,text)', 'app_backup_is_admin(text,text)', 'app_backup_tables()', 'app_backup_schema_sql()'] loop
    execute format('revoke all on function %s from %s', f, v);
  end loop;
end $$;

notify pgrst, 'reload schema';
