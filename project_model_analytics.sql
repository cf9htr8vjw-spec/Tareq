-- ============================================================
-- SalesPlace — تحليل رقمي للمشروع حسب النموذج (شاشة "مبيعاتنا")
-- دالة قراءة جديدة بالكامل — لا تمسّ أي جدول أو دالة موجودة حالياً
-- (unit_allocation_mirror، unit_blocked_mirror، project_model_stats كلها تُقرأ فقط،
-- بلا أي INSERT/UPDATE عليها من هذا الملف)
-- شغّل هذا الملف كاملاً مرة واحدة في Supabase SQL editor
-- ============================================================

-- لكل نموذج تصميم (model) بمشروع معيّن: مبيعات العقود الموقّعة شهرياً لسنة مختارة
-- (من تواريخ contract_date الحقيقية بمرآة التخصيص — نفس مصدر get_sales_report/
-- get_project_totals الأصليتين، بلا أي جدول تراكمي جديد)، + اللقطة الحيّة الحالية
-- (متاح/محجوز/متعاقَد من project_model_stats، محجوب من unit_blocked_mirror).
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
      select jsonb_agg(jsonb_build_object('month', mth, 'cnt', cnt) order by mth) as arr
      from (
        select extract(month from contract_date)::int as mth, count(*) as cnt
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
