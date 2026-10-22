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
