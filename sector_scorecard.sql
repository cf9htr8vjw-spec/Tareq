-- ============================================================
-- SalesPlace — إعادة بناء "مراقبة الأداء" كمصفوفة تنفيذية بالقطاعات (بدل قائمة بطاقات
-- طويلة تبيّن غير مفيدة عملياً) — حسب تصميم مرسوم يدوياً من طارق: صف لكل قطاع (٣ قطاعات)،
-- أعمدة: مستهدف (شهر/سنة) | محقق (شهر/سنة) | مؤشر الحجوزات (IN/OUT/نسبة) | مؤشر
-- الاستصناع (IN/OUT/نسبة نفس الفكرة) — وتفصيل إضافي يظهر عند الضغط على أي قطاع، ثم تفصيل
-- أعمق لكل مشروع داخل ذلك القطاع بنفس المؤشرات.
--
-- get_sector_scorecard: صف واحد لكل قطاع — مبني فوق sales_targets (المستهدف) و
-- unit_allocation_mirror (المحقق + مؤشرا الحجوزات/الاستصناع). "IN" لكل مؤشر = عدد
-- الوحدات التي بدأ حدثها (حجز أو استصناع بالترتيب) خلال الفترة المحدَّدة (شهر معيّن أو
-- كامل السنة)، "OUT" = من ضمن هذه المجموعة بالذات، كم منها وصل لعقد نهائي حتى تاريخه
-- (بصرف النظر متى تحديداً) — قياس أفواج (cohort) لا مقارنة أحداث منفصلة بلا رابط.
--
-- get_sector_detail: تفصيل إضافي لقطاع واحد عند الضغط عليه — نسبة المتاح:المحجوب، %
-- النماذج الراكدة (بلا أي حجز أو عقد آخر 30 يوماً) مقابل % النشطة، ووسيط أيام التحوّل
-- (حجز←عقد، استصناع←عقد) — إجمالاً للقطاع، وأيضاً مفصّلاً لكل مشروع بداخله لنفس الأرقام.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor (بعد zone_number.sql وfunnel_layer2.sql).
-- ============================================================

create or replace function get_sector_scorecard(
  p_year integer, p_month integer, p_period_mode text default 'month',
  p_dev_kind text default null, p_unit_type text default null
)
returns table(
  sector text,
  target_month numeric, target_year numeric,
  achieved_month bigint, achieved_year bigint,
  booking_in bigint, booking_out bigint, booking_rate numeric,
  istisna_in bigint, istisna_out bigint, istisna_rate numeric
)
language plpgsql
stable
as $function$
declare
  v_month_start date := make_date(p_year, p_month, 1);
  v_month_end date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_year_start date := make_date(p_year, 1, 1);
  v_year_end date := make_date(p_year, 12, 31);
  v_cohort_start date := case when p_period_mode = 'year' then v_year_start else v_month_start end;
  v_cohort_end date := case when p_period_mode = 'year' then v_year_end else v_month_end end;
begin
  return query
  select
    s.sector,
    (select coalesce(sum(t.target),0) from sales_targets t
       where t.year=p_year and t.month_num=p_month and t.sector=s.sector
         and (p_dev_kind is null or (p_dev_kind='nhc' and t.developer_kind='NHC') or (p_dev_kind='other' and t.developer_kind<>'NHC'))
    )::numeric as target_month,
    (select coalesce(sum(t.target),0) from sales_targets t
       where t.year=p_year and t.sector=s.sector
         and (p_dev_kind is null or (p_dev_kind='nhc' and t.developer_kind='NHC') or (p_dev_kind='other' and t.developer_kind<>'NHC'))
    )::numeric as target_year,
    (select count(*) from unit_allocation_mirror m
       where m.sector=s.sector and m.contract_date between v_month_start and v_month_end
         and (p_dev_kind is null or (p_dev_kind='nhc' and m.dev_kind='nhc') or (p_dev_kind='other' and m.dev_kind<>'nhc'))
         and (p_unit_type is null or m.unit_type=p_unit_type)
    ) as achieved_month,
    (select count(*) from unit_allocation_mirror m
       where m.sector=s.sector and m.contract_date between v_year_start and v_month_end
         and (p_dev_kind is null or (p_dev_kind='nhc' and m.dev_kind='nhc') or (p_dev_kind='other' and m.dev_kind<>'nhc'))
         and (p_unit_type is null or m.unit_type=p_unit_type)
    ) as achieved_year,
    b.booking_in, b.booking_out,
    round(100.0 * b.booking_out / nullif(b.booking_in,0), 1) as booking_rate,
    i.istisna_in, i.istisna_out,
    round(100.0 * i.istisna_out / nullif(i.istisna_in,0), 1) as istisna_rate
  from (select distinct sector from unit_allocation_mirror where sector is not null) s
  left join lateral (
    select count(*) as booking_in, count(*) filter (where contract_date is not null) as booking_out
    from unit_allocation_mirror m
    where m.sector = s.sector and m.booking_date between v_cohort_start and v_cohort_end
      and (p_dev_kind is null or (p_dev_kind='nhc' and m.dev_kind='nhc') or (p_dev_kind='other' and m.dev_kind<>'nhc'))
      and (p_unit_type is null or m.unit_type=p_unit_type)
  ) b on true
  left join lateral (
    select count(*) as istisna_in, count(*) filter (where contract_date is not null) as istisna_out
    from unit_allocation_mirror m
    where m.sector = s.sector and m.istisna_date between v_cohort_start and v_cohort_end
      and (p_dev_kind is null or (p_dev_kind='nhc' and m.dev_kind='nhc') or (p_dev_kind='other' and m.dev_kind<>'nhc'))
      and (p_unit_type is null or m.unit_type=p_unit_type)
  ) i on true
  order by s.sector;
end;
$function$;

create or replace function get_sector_detail(
  p_sector text, p_dev_kind text default null, p_unit_type text default null
)
returns jsonb
language plpgsql
stable
as $function$
declare
  v_avail bigint;
  v_blocked bigint;
  v_stagnant int;
  v_active int;
  v_total_models int;
  v_median_book_contract numeric;
  v_median_istisna_contract numeric;
  v_by_project jsonb;
begin
  select count(*) into v_avail from unit_allocation_mirror
    where sector = p_sector and status = 'avail'
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type);

  select count(*) into v_blocked from unit_blocked_mirror
    where sector = p_sector
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type);

  select
    count(*) filter (where not has_activity),
    count(*) filter (where has_activity),
    count(*)
  into v_stagnant, v_active, v_total_models
  from (
    select project_name, model,
      bool_or(booking_date >= current_date - interval '30 days' or contract_date >= current_date - interval '30 days') as has_activity
    from unit_allocation_mirror
    where sector = p_sector and model is not null and project_name is not null
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_name, model
  ) t;

  select round((percentile_cont(0.5) within group (order by (contract_date - booking_date)))::numeric, 1)
  into v_median_book_contract
  from unit_allocation_mirror
  where sector = p_sector and contract_date is not null and booking_date is not null
    and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
    and (p_unit_type is null or unit_type = p_unit_type);

  select round((percentile_cont(0.5) within group (order by (contract_date - istisna_date)))::numeric, 1)
  into v_median_istisna_contract
  from unit_allocation_mirror
  where sector = p_sector and contract_date is not null and istisna_date is not null
    and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
    and (p_unit_type is null or unit_type = p_unit_type);

  select coalesce(jsonb_agg(jsonb_build_object(
      'project_name', p.project_name,
      'avail_count', p.avail_count, 'blocked_count', p.blocked_count,
      'pct_stagnant', p.pct_stagnant, 'pct_active', p.pct_active,
      'median_book_contract', p.median_book_contract, 'median_istisna_contract', p.median_istisna_contract
    ) order by p.project_name), '[]'::jsonb)
  into v_by_project
  from (
    select
      pr.project_name,
      (select count(*) from unit_allocation_mirror a where a.project_name = pr.project_name and a.status='avail') as avail_count,
      (select count(*) from unit_blocked_mirror bl where bl.project_name = pr.project_name) as blocked_count,
      (select round(100.0*count(*) filter (where not has_activity)/nullif(count(*),0),1)
        from (select model, bool_or(booking_date>=current_date-interval '30 days' or contract_date>=current_date-interval '30 days') has_activity
              from unit_allocation_mirror where project_name=pr.project_name and model is not null group by model) tm
      ) as pct_stagnant,
      (select round(100.0*count(*) filter (where has_activity)/nullif(count(*),0),1)
        from (select model, bool_or(booking_date>=current_date-interval '30 days' or contract_date>=current_date-interval '30 days') has_activity
              from unit_allocation_mirror where project_name=pr.project_name and model is not null group by model) tm2
      ) as pct_active,
      (select round((percentile_cont(0.5) within group (order by (contract_date-booking_date)))::numeric,1)
        from unit_allocation_mirror where project_name=pr.project_name and contract_date is not null and booking_date is not null
      ) as median_book_contract,
      (select round((percentile_cont(0.5) within group (order by (contract_date-istisna_date)))::numeric,1)
        from unit_allocation_mirror where project_name=pr.project_name and contract_date is not null and istisna_date is not null
      ) as median_istisna_contract
    from (select distinct project_name from unit_allocation_mirror
          where sector = p_sector and project_name is not null
            and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
            and (p_unit_type is null or unit_type = p_unit_type)
         ) pr
  ) p;

  return jsonb_build_object(
    'avail_count', v_avail, 'blocked_count', v_blocked,
    'avail_blocked_ratio', case when v_blocked > 0 then round(v_avail::numeric / v_blocked, 2) else null end,
    'pct_stagnant', case when v_total_models > 0 then round(100.0 * v_stagnant / v_total_models, 1) else null end,
    'pct_active', case when v_total_models > 0 then round(100.0 * v_active / v_total_models, 1) else null end,
    'median_book_contract', v_median_book_contract,
    'median_istisna_contract', v_median_istisna_contract,
    'by_project', v_by_project
  );
end;
$function$;
