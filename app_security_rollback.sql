-- ============================================================
-- SalesPlace — التراجع عن app_security.sql (للطوارئ فقط)
-- ============================================================
-- يعيد صلاحيات القراءة والتنفيذ العامة لمفتاح التطبيق كما كانت قبل الحماية، ويعيد دالة login الأصلية
-- (التي ترجع مفتاح فك البيانات) — فتعمل النسخ السابقة من التطبيق من جديد.
-- لا يحذف الجلسات ولا الجداول الجديدة؛ النسخة الجديدة تبقى تعمل أيضاً.
-- ============================================================

do $$
declare r record; v_roles text;
begin
  v_roles := 'public'
    || case when to_regrole('anon') is not null then ', anon' else '' end
    || case when to_regrole('authenticated') is not null then ', authenticated' else '' end;
  for r in select format('%I.%I', n.nspname, c.relname) as obj from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
             and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e') loop
    execute format('grant select on table %s to %s', r.obj, v_roles);
  end loop;
  for r in select p.oid::regprocedure::text as obj from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind in ('f', 'p')
             and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e') loop
    execute format('grant execute on function %s to %s', r.obj, v_roles);
  end loop;
  execute format('alter default privileges in schema public grant execute on functions to %s', v_roles);
end $$;

-- دالة الدخول الأصلية (كما كانت في Supabase قبل الحماية)
CREATE OR REPLACE FUNCTION public.login(p_user text, p_pass text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  u app_users%rowtype;
  k text;
begin
  delete from login_log where at < now() - interval '3 days';
  select * into u from app_users where username = lower(trim(p_user));
  if not found then
    insert into login_log(username, ok, reason) values (p_user, false, 'مستخدم غير موجود');
    return json_build_object('ok', false, 'msg', 'اسم المستخدم أو كلمة المرور غير صحيحة');
  end if;
  if not u.is_active then
    insert into login_log(username, ok, reason) values (u.username, false, 'حساب موقوف');
    return json_build_object('ok', false, 'msg', 'هذا الحساب موقوف — راجع مدير النظام');
  end if;
  if u.pass_hash <> crypt(p_pass, u.pass_hash) then
    insert into login_log(username, ok, reason) values (u.username, false, 'كلمة مرور خاطئة');
    return json_build_object('ok', false, 'msg', 'اسم المستخدم أو كلمة المرور غير صحيحة');
  end if;
  update app_users set last_login = now() where username = u.username;
  insert into login_log(username, ok, reason) values (u.username, true, 'دخول ناجح');
  select data_key into k from app_secret where id = 1;
  return json_build_object('ok', true, 'name', coalesce(u.full_name, u.username),
                           'admin', u.is_admin, 'key', k);
end;
$function$;

notify pgrst, 'reload schema';
