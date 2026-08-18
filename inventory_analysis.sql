-- ============================================================
-- SalesPlace — "تحليل المخزون" بشاشة مبيعاتنا: توزيع كامل للمخزون (متاح/محجوز/مباع/محجوب)
-- + متوسط السعر وسعر المتر والمساحة لكل من المتاح والمحجوب، مع تفصيل حسب المشروع — بنفس
-- فلاتر القطاع/المطوّر/نوع المنتج الموجودة أصلاً بالشاشة.
--
-- تُبنى مباشرة فوق unit_allocation_mirror (التخصيص اليومي: متاح/محجوز/متعاقَد) و
-- unit_blocked_mirror (المحجوب) — كلا الجدولين أُنشئا وأُدير مخططهما بالكامل ضمن هذا
-- المستودع (blocked_units.sql وملفات supply_*.sql)، على عكس get_sales_report/
-- get_project_totals القديمتين، فلا يوجد خطر تخمين منطق غير معروف هنا.
--
-- ملاحظة: بخلاف شاشة "توزيع المعروض" (تقتصر على وحدات غير المستفيدين/المستثمرين حصراً)،
-- هذا التحليل يشمل كل الوحدات بصرف النظر عن الشريحة — رؤية عامة كاملة للمخزون كما طُلب.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor.
-- ============================================================

create or replace function get_inventory_analysis(p_sector text default null, p_dev_kind text default null, p_unit_type text default null)
returns jsonb
language plpgsql
stable
as $function$
declare
  v_totals jsonb;
  v_avail jsonb;
  v_avail_by_proj jsonb;
  v_blocked jsonb;
  v_blocked_by_proj jsonb;
begin
  select jsonb_build_object(
    'avail_count', count(*) filter (where status='avail'),
    'reserved_count', count(*) filter (where status='reserved'),
    'contracted_count', count(*) filter (where status='contracted')
  ) into v_totals
  from unit_allocation_mirror
  where (p_sector is null or sector = p_sector)
    and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
    and (p_unit_type is null or unit_type = p_unit_type);

  select jsonb_build_object(
    'count', count(*),
    'avg_price', round(avg(price) filter (where price>0)),
    'avg_sqm_price', case when sum(unit_size) filter (where unit_size>0)>0
      then round(sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0))
      else null end,
    'avg_size', round(avg(unit_size) filter (where unit_size>0))
  ) into v_avail
  from unit_allocation_mirror
  where status='avail'
    and (p_sector is null or sector = p_sector)
    and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
    and (p_unit_type is null or unit_type = p_unit_type);

  select coalesce(jsonb_agg(jsonb_build_object('project_name',project_name,'count',cnt,'avg_price',avg_price) order by cnt desc), '[]'::jsonb)
  into v_avail_by_proj
  from (
    select project_name, count(*) cnt, round(avg(price) filter (where price>0)) avg_price
    from unit_allocation_mirror
    where status='avail' and project_name is not null
      and (p_sector is null or sector = p_sector)
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_name
  ) t;

  select jsonb_build_object(
    'count', count(*),
    'avg_price', round(avg(price) filter (where price>0)),
    'avg_sqm_price', case when sum(unit_size) filter (where unit_size>0)>0
      then round(sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0))
      else null end,
    'avg_size', round(avg(unit_size) filter (where unit_size>0))
  ) into v_blocked
  from unit_blocked_mirror
  where (p_sector is null or sector = p_sector)
    and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
    and (p_unit_type is null or unit_type = p_unit_type);

  select coalesce(jsonb_agg(jsonb_build_object('project_name',project_name,'count',cnt,'avg_price',avg_price) order by cnt desc), '[]'::jsonb)
  into v_blocked_by_proj
  from (
    select project_name, count(*) cnt, round(avg(price) filter (where price>0)) avg_price
    from unit_blocked_mirror
    where project_name is not null
      and (p_sector is null or sector = p_sector)
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_name
  ) t;

  return jsonb_build_object(
    'totals', v_totals || jsonb_build_object('blocked_count', coalesce((v_blocked->>'count')::int,0)),
    'avail', v_avail || jsonb_build_object('by_project', v_avail_by_proj),
    'blocked', v_blocked || jsonb_build_object('by_project', v_blocked_by_proj)
  );
end;
$function$;
