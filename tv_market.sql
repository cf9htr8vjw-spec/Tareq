-- ============================================================
-- SalesPlace — صفقات السوق الأسبوعية (ملف «أسعار صفقات السوق»: أسبوع × مدينة × نوع العقار)
-- ============================================================
-- يُرفع من «⬆ رفع ملف» بالشاشة (يُتعرّف عليه تلقائياً من أعمدته: التاريخ، المنطقة، نوع العقار، اجمالي الصفقات،
-- اجمالي القيمة، شهر بيانات الأسعار، متوسط سعر المتر). كل ورقة أسبوع. السكني فقط (شقق/فلل/تاون هاوس) — الأراضي وغيرها تُهمل.
-- يغذّي خريطة الأسعار: سعر المتر في السوق لكل مدينة ونوع مقابل أسعارنا من ملف التخصيص.
-- يتطلّب: app_security.sql (البوابة). آمن لإعادة التشغيل. شغّل app_security.sql بعده مرة لتبقى الصلاحيات مضبوطة.
-- ============================================================

create table if not exists tv_market_weekly (
  wk integer not null,                 -- السنة×100 + رقم الأسبوع (مثل 202642)
  city text not null,
  unit_type text not null,             -- شقة / فيلا / تاون هاوس
  deals integer not null default 0,
  value numeric not null default 0,    -- إجمالي قيمة الصفقات
  price_month text not null default '',-- شهر بيانات سعر المتر (مثل 2026-09)
  sqm numeric,                         -- متوسط سعر المتر بالسوق (شهري)
  excluded integer not null default 0, -- صفقات مستبعدة (قيمة شاذة: أقل من 200 ألف أو أكثر من 15 مليون للصفقة)
  excluded_value numeric not null default 0,
  updated_at timestamptz not null default now(),
  primary key (wk, city, unit_type)
);
alter table tv_market_weekly enable row level security;

-- رفع (الأولى تمسح أسابيع الملف نفسها فقط — الأسابيع الأخرى تبقى) — يتطلّب صلاحية أدمن فعلية
create or replace function admin_load_tv_market(p_admin text, p_pass text, p_rows jsonb, p_reset boolean default false)
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
    where username = p_admin and pass_hash = crypt(p_pass, pass_hash) and coalesce(is_active, true)
    limit 1;
  if v_is_admin is not true then
    return jsonb_build_object('ok', false, 'msg', 'غير مصرح — تحقق من بيانات الدخول وصلاحية الإدمن');
  end if;
  if p_reset then
    delete from tv_market_weekly w where w.wk in (select distinct (r->>'wk')::int from jsonb_array_elements(p_rows) r where nullif(r->>'wk', '') is not null);
  end if;
  insert into tv_market_weekly (wk, city, unit_type, deals, value, price_month, sqm, excluded, excluded_value)
  select (r->>'wk')::int, btrim(r->>'city'), btrim(r->>'type'),
         sum(coalesce((r->>'deals')::int, 0)), sum(coalesce((r->>'value')::numeric, 0)), max(coalesce(r->>'month', '')),
         max(nullif(r->>'sqm', '')::numeric), sum(coalesce((r->>'excluded')::int, 0)), sum(coalesce((r->>'excluded_value')::numeric, 0))
  from jsonb_array_elements(p_rows) r
  where nullif(r->>'wk', '') is not null and nullif(btrim(r->>'city'), '') is not null and nullif(btrim(r->>'type'), '') is not null
  group by 1, 2, 3
  on conflict (wk, city, unit_type) do update set
    deals = excluded.deals, value = excluded.value, price_month = excluded.price_month, sqm = excluded.sqm,
    excluded = excluded.excluded, excluded_value = excluded.excluded_value, updated_at = now();
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- كل الأسابيع (الشاشة تحسب آخر أسبوع، آخر 4 أسابيع، السنة، والاتجاه)
create or replace function get_tv_market()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'ok', true,
    'as_of', (select max(updated_at) from tv_market_weekly),
    'weeks', coalesce((select jsonb_agg(distinct wk order by wk) from tv_market_weekly), '[]'::jsonb),
    'cols', jsonb_build_array('wk', 'city', 'type', 'deals', 'value', 'month', 'sqm', 'excluded'),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_array(wk, city, unit_type, deals, round(value), price_month, sqm, excluded) order by wk, city, unit_type)
      from tv_market_weekly
    ), '[]'::jsonb)
  );
$$;
