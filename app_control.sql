-- ============================================================
-- SalesPlace — إيقاف / تشغيل التطبيق بالكامل من قاعدة البيانات
-- ============================================================
-- عند الإيقاف: تُسحب صلاحيات القراءة والكتابة والتنفيذ من مفتاح التطبيق (anon / authenticated / PUBLIC)
-- على كل جداول ودوال المخطط public — فيتوقف كل شيء فعلياً على السيرفر: الدخول للتطبيق (جوال/كمبيوتر)،
-- شاشة المبيعات (التلفزيون والجوال)، الرفع والتحديث. حتى نسخة قديمة من الملف أو أي أداة تستعمل نفس المفتاح.
-- قبل السحب تُحفظ الصلاحيات كما هي بالضبط في app_control_saved، وعند التشغيل تُعاد كما كانت.
--
-- يبقى متاحاً أثناء الإيقاف دالتان فقط: get_app_state (لعرض رسالة الإيقاف) و admin_set_app_state
-- (لإعادة التشغيل — تتطلّب حساب أدمن فعلياً بكلمة مروره، يُتحقق منها هنا على السيرفر).
--
-- شغّل هذا الملف مرة واحدة (آمن لإعادة التشغيل). إن شغّلت ملفات SQL أخرى أثناء الإيقاف فالدوال الجديدة
-- تأخذ الصلاحيات الافتراضية — أعد الإيقاف من التطبيق بعدها (أو شغّل: select app_control_apply();).
-- ============================================================

create table if not exists app_control (
  id integer primary key default 1 check (id = 1),
  enabled boolean not null default true,
  message text not null default '',
  updated_at timestamptz not null default now(),
  updated_by text not null default ''
);
insert into app_control (id) values (1) on conflict (id) do nothing;
alter table app_control enable row level security;   -- بلا سياسة قراءة: القراءة عبر get_app_state فقط

-- الصلاحيات المحفوظة لحظة الإيقاف (لإعادتها كما كانت)
create table if not exists app_control_saved (
  kind text not null,          -- 'table' | 'function'
  obj text not null,           -- الاسم المؤهّل (للدوال مع أنواع المعاملات)
  grantee text not null,       -- 'PUBLIC' | 'anon' | 'authenticated'
  priv text not null,          -- SELECT / INSERT / ... / EXECUTE
  primary key (kind, obj, grantee, priv)
);
alter table app_control_saved enable row level security;

create table if not exists app_control_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  by_user text not null,
  action text not null,        -- 'stop' | 'start' | 'message'
  message text not null default '',
  objects integer
);
alter table app_control_log enable row level security;

-- الدوال التي لا تُسحب صلاحيتها أبداً
create or replace function app_control_keep(p_name text)
returns boolean
language sql
immutable
as $$ select p_name in ('get_app_state', 'admin_set_app_state') $$;

-- يطبّق الحالة الحالية: إيقاف ⇒ حفظ الصلاحيات (إن لم تُحفظ) ثم سحبها؛ تشغيل ⇒ إعادتها ومسح المحفوظ
create or replace function app_control_apply()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_enabled boolean;
  v_roles text;
  v_n integer := 0;
  r record;
begin
  select enabled into v_enabled from app_control where id = 1;
  v_roles := 'public'
    || case when to_regrole('anon') is not null then ', anon' else '' end
    || case when to_regrole('authenticated') is not null then ', authenticated' else '' end;

  if coalesce(v_enabled, true) then
    -- تشغيل: أعد كل صلاحية محفوظة كما كانت
    for r in select * from app_control_saved loop
      begin
        if r.kind = 'table' then
          execute format('grant %s on table %s to %s', r.priv, r.obj, case when r.grantee = 'PUBLIC' then 'public' else quote_ident(r.grantee) end);
        else
          execute format('grant execute on function %s to %s', r.obj, case when r.grantee = 'PUBLIC' then 'public' else quote_ident(r.grantee) end);
        end if;
        v_n := v_n + 1;
      exception when others then
        raise notice 'تعذّرت إعادة % على %: %', r.priv, r.obj, sqlerrm;
      end;
    end loop;
    delete from app_control_saved where true;
    notify pgrst, 'reload schema';   -- تحديث ذاكرة PostgREST (Supabase) بعد إعادة الصلاحيات
    return v_n;
  end if;

  -- إيقاف: احفظ الصلاحيات الحالية (للجداول والدوال التي نملكها في public، بلا دوال الإضافات)
  insert into app_control_saved (kind, obj, grantee, priv)
  select 'table', format('%I.%I', n.nspname, c.relname),
         case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end, a.privilege_type
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
  where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
    and pg_get_userbyid(c.relowner) = current_user
    and (a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated')))
    and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
  on conflict do nothing;

  insert into app_control_saved (kind, obj, grantee, priv)
  select 'function', p.oid::regprocedure::text,
         case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end, a.privilege_type
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where n.nspname = 'public' and p.prokind in ('f', 'p')
    and pg_get_userbyid(p.proowner) = current_user
    and not app_control_keep(p.proname)
    and (a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated')))
    and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  on conflict do nothing;

  -- ثم اسحبها
  for r in
    select format('%I.%I', n.nspname, c.relname) as obj
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
      and pg_get_userbyid(c.relowner) = current_user
      and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('revoke all on table %s from %s', r.obj, v_roles);
    v_n := v_n + 1;
  end loop;
  for r in
    select p.oid::regprocedure::text as obj
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind in ('f', 'p')
      and pg_get_userbyid(p.proowner) = current_user
      and not app_control_keep(p.proname)
      and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke execute on function %s from %s', r.obj, v_roles);
    v_n := v_n + 1;
  end loop;
  notify pgrst, 'reload schema';
  return v_n;
end;
$$;

-- الحالة (متاحة دائماً، حتى أثناء الإيقاف)
create or replace function get_app_state()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object('ok', true, 'enabled', enabled, 'message', message, 'updated_at', updated_at)
  from app_control where id = 1;
$$;

-- إيقاف / تشغيل / تغيير الرسالة — أدمن فقط (يُتحقق من كلمة المرور هنا)
create or replace function admin_set_app_state(p_admin text, p_pass text, p_enabled boolean, p_message text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_is_admin boolean;
  v_was boolean;
  v_n integer := 0;
begin
  select is_admin into v_is_admin from app_users
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true)
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;

  select enabled into v_was from app_control where id = 1 for update;
  update app_control set
    enabled = coalesce(p_enabled, enabled),
    message = coalesce(p_message, message),
    updated_at = now(), updated_by = p_admin
  where id = 1;

  if p_enabled is not null and p_enabled is distinct from v_was then
    v_n := app_control_apply();
  end if;
  insert into app_control_log (by_user, action, message, objects)
  values (p_admin,
          case when p_enabled is null or p_enabled = v_was then 'message' when p_enabled then 'start' else 'stop' end,
          coalesce(p_message, ''), v_n);

  return jsonb_build_object('ok', true, 'enabled', coalesce(p_enabled, v_was), 'objects', v_n,
    'msg', case when p_enabled is null or p_enabled = v_was then 'حُفظت الرسالة'
                when p_enabled then 'أُعيد تشغيل التطبيق (' || v_n || ' صلاحية أُعيدت)'
                else 'أُوقف التطبيق (' || v_n || ' جدولاً ودالة أُغلقت)' end);
end;
$$;

-- أدوات الإدارة الداخلية لا يستدعيها مفتاح التطبيق مباشرة
revoke all on function app_control_apply() from public;
do $$ begin
  if to_regrole('anon') is not null then execute 'revoke all on function app_control_apply() from anon'; end if;
  if to_regrole('authenticated') is not null then execute 'revoke all on function app_control_apply() from authenticated'; end if;
end $$;
grant execute on function get_app_state() to public;
grant execute on function admin_set_app_state(text, text, boolean, text) to public;

-- فحص سريع:
--   select get_app_state();
--   select * from app_control_log order by at desc limit 20;
--   select count(*) from app_control_saved;   -- > 0 أثناء الإيقاف فقط
