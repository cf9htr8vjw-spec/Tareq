-- ============================================================
-- SalesPlace — "مراقبة الأداء": استبدال قائمة "الوحدات العالقة" (مستوى وحدة) بقائمة
-- "مشاريع بلا حركة" (مستوى مشروع) — بطلب صريح: عرض وحدات فردية غير مناسب هنا، المطلوب رؤية
-- أي مشروع كامل توقّفت فيه الحركة (لا حجوزات ولا عقود استصناع ولا عقود نهائية) خلال فترة
-- معيّنة، مع آخر نشاط حقيقي سُجِّل فيه (متى كان، إن وُجد أصلاً).
--
-- get_dormant_projects: لكل مشروع (بنفس فلاتر القطاع/المطوّر/نوع المنتج)، نحسب آخر تاريخ
-- حجز أو استصناع أو عقد (أيهما أحدث) عبر كامل تاريخ المشروع، ثم نُرجع فقط المشاريع التي لم
-- يسجَّل فيها أي من هذه الأحداث الثلاثة خلال آخر p_inactive_days يوماً (فترة "عدم النشاط" —
-- تُمرَّر كمعامل من الواجهة، وليست ثابتة). مشروع بلا أي حدث مسجَّل إطلاقاً (لم يُحجز منه شيء
-- قط) يظهر أيضاً بتاريخ نشاط فارغ (null) في أعلى القائمة.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL editor (بعد zone_number.sql وfunnel_layer2.sql).
-- ============================================================

create or replace function get_dormant_projects(
  p_sector text default null, p_dev_kind text default null, p_unit_type text default null,
  p_inactive_days integer default 90
)
returns table(
  project_name text, last_activity_date date, days_since_activity integer
)
language sql
stable
as $function$
  with proj as (
    select project_name,
      greatest(max(booking_date), max(istisna_date), max(contract_date)) as last_activity
    from unit_allocation_mirror
    where project_name is not null
      and (p_sector is null or sector = p_sector)
      and (p_dev_kind is null or (p_dev_kind='nhc' and dev_kind='nhc') or (p_dev_kind='other' and dev_kind<>'nhc'))
      and (p_unit_type is null or unit_type = p_unit_type)
    group by project_name
  )
  select project_name, last_activity,
    case when last_activity is not null then (current_date - last_activity)::int else null end as days_since_activity
  from proj
  where last_activity is null or last_activity < current_date - (p_inactive_days || ' days')::interval
  order by last_activity asc nulls first;
$function$;
