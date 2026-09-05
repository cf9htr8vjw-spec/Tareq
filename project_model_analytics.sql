-- ============================================================
-- SalesPlace — تحليل رقمي للمشروع حسب النموذج (شاشة "مبيعاتنا")
-- دالة قراءة جديدة بالكامل — لا تمسّ أي جدول أو دالة موجودة حالياً
-- (unit_allocation_mirror، unit_blocked_mirror، project_model_stats كلها تُقرأ فقط،
-- بلا أي INSERT/UPDATE عليها من هذا الملف)
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

-- لكل نموذج تصميم (model) بمشروع معيّن:
--  - مبيعات العقود الموقّعة شهرياً (عدد + قيمة) لسنة مختارة، من تواريخ contract_date
--    الحقيقية بمرآة التخصيص — نفس مصدر get_sales_report/get_project_totals الأصليتين،
--    بلا أي جدول تراكمي جديد.
--  - أعداد اللقطة الحيّة الحالية (متاح/محجوز/متعاقَد من project_model_stats،
--    محجوب من unit_blocked_mirror) — نفس أسلوب باقي شاشات الداشبورد (لا تُحسب حياً
--    لتفادي مسح آلاف الصفوف بكل فتح شاشة).
--  - قيمة المتاح والمحجوب ومتوسط سعر المتر (sum(price)/sum(unit_size)) — تُحسب حياً
--    مباشرة من المرايا الخام لأنه لا يوجد جدول تجميع للقيمة بعد، بنفس أسلوب
--    get_supply_buildings تماماً (avail_value/avail_sqm_value) بملف supply_building_details.sql.
-- بلا معاملات دخول — نفس نمط get_supply_overview/get_target_summary (قراءة عامة فقط).
create or replace function get_project_model_analytics(p_project_id int, p_year int)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_models jsonb;
begin
  select coalesce(jsonb_agg(t order by t->>'model'), '[]'::jsonb)
  into v_models
  from (
    select jsonb_build_object(
      'model', um.model,
      'avail_count', coalesce(pms.avail_count,0),
      'reserved_count', coalesce(pms.reserved_count,0),
      'contracted_count', coalesce(pms.contracted_count,0),
      'blocked_count', coalesce(bm.blocked_count,0),
      'avail_value', coalesce(av.avail_value,0),
      'avail_sqm_value', av.avail_sqm_value,
      'blocked_value', coalesce(bv.blocked_value,0),
      'blocked_sqm_value', bv.blocked_sqm_value,
      'monthly', coalesce(mo.arr,'[]'::jsonb)
    ) as t
    from (
      select distinct model
      from unit_allocation_mirror
      where project_id = p_project_id and model is not null
    ) um
    left join project_model_stats pms
      on pms.project_id = p_project_id and pms.model = um.model
    left join (
      select model, count(*) as blocked_count
      from unit_blocked_mirror
      where project_id = p_project_id and model is not null
      group by model
    ) bm on bm.model = um.model
    left join lateral (
      select sum(price) as avail_value,
             case when sum(unit_size) filter (where unit_size>0)>0
                  then sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0)
                  else null end as avail_sqm_value
      from unit_allocation_mirror u3
      where u3.project_id = p_project_id and u3.model = um.model and u3.status = 'avail'
    ) av on true
    left join lateral (
      select sum(price) as blocked_value,
             case when sum(unit_size) filter (where unit_size>0)>0
                  then sum(price) filter (where unit_size>0) / sum(unit_size) filter (where unit_size>0)
                  else null end as blocked_sqm_value
      from unit_blocked_mirror u4
      where u4.project_id = p_project_id and u4.model = um.model
    ) bv on true
    left join lateral (
      select jsonb_agg(jsonb_build_object('month', mth, 'cnt', cnt, 'value', val) order by mth) as arr
      from (
        select extract(month from contract_date)::int as mth, count(*) as cnt, sum(price) as val
        from unit_allocation_mirror u2
        where u2.project_id = p_project_id and u2.model = um.model
          and u2.status = 'contracted' and u2.contract_date is not null
          and extract(year from u2.contract_date) = p_year
        group by 1
      ) x
    ) mo on true
  ) t;

  return jsonb_build_object('ok', true, 'models', v_models);
end;
$$;
