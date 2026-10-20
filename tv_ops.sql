-- ============================================================
-- SalesPlace — شاشة المبيعات: الصفحة التشغيلية (الصفحة 3)
-- ============================================================
-- من ملف التخصيص (مع كل رفع، من التطبيق أو من الشاشة):
--   tv_ops_daily : عقود كل يوم × مشروع × ضاحية × قطاع × NHC/مطور × قناة × موظف × موقع عمل × بنك
--                  مع قيمة العقود، ونسبة الربح بالعقد (إن وُجد عمودها)، ومدة التمويل، والمستفيدين، وأيام الحجز→العقد
--   tv_ops_book  : الوحدات المحجوزة أو المتعاقد عليها بتاريخ حجزها (للتحويل وأعمار الحجوزات القائمة)
-- من ملف «مميزات وسياسات الجهات التمويلية» (يُرفع من الشاشة):
--   tv_bank_policy : نسب البنوك المعلنة (مدعوم/غير مدعوم، محول الراتب/غير محول) والسياسات والمبادرات
-- من ملف «بيانات الموظفين» (يُرفع من الشاشة):
--   tv_employee_roster : الاسم، المنطقة، موقع العمل، المسمى، النوع، المشرف، المدير، المباشرة/الاستقالة
--                        (لا رقم هوية ولا بريد ولا جوال ولا أرقام وظيفية — لا تُقرأ من الملف أصلاً)
--
-- يتطلّب: tv_file_counts.sql (tv_region). آمن لإعادة التشغيل. القراءة عبر get_tv_ops فقط.
-- ============================================================

create table if not exists tv_ops_daily (
  contract_date date not null,
  project_name text not null default '',
  dest text not null default '',
  sector text not null default '',
  kind text not null default 'other',
  channel text not null default '',
  employee text not null default '',
  work text not null default '',
  bank text not null default '',            -- فارغ = نقدي
  cnt integer not null default 0,
  val_sum numeric not null default 0, val_n integer not null default 0,     -- قيمة العقود
  rate_sum numeric not null default 0, rate_n integer not null default 0,   -- نسبة الربح (الفعلية) بالعقود
  term_sum numeric not null default 0, term_n integer not null default 0,   -- مدة التمويل بالسنوات
  ben integer not null default 0,                                           -- عقود المستفيدين
  days_sum numeric not null default 0, days_n integer not null default 0,   -- أيام من الحجز إلى العقد
  updated_at timestamptz not null default now(),
  primary key (contract_date, project_name, dest, sector, kind, channel, employee, work, bank)
);
alter table tv_ops_daily enable row level security;
-- بيانات التمويل (أعمدة REDF بملف التخصيص): مجاميع وعدّادات فقط — لا بيانات شخصية
alter table tv_ops_daily add column if not exists fa_sum numeric not null default 0;     -- اجمالي مبلغ التمويل
alter table tv_ops_daily add column if not exists fa_n integer not null default 0;
alter table tv_ops_daily add column if not exists sal_sum numeric not null default 0;    -- الراتب
alter table tv_ops_daily add column if not exists sal_n integer not null default 0;
alter table tv_ops_daily add column if not exists inst_sum numeric not null default 0;   -- القسط الشهري
alter table tv_ops_daily add column if not exists inst_n integer not null default 0;
alter table tv_ops_daily add column if not exists fam_sum numeric not null default 0;    -- أفراد الأسرة
alter table tv_ops_daily add column if not exists fam_n integer not null default 0;
alter table tv_ops_daily add column if not exists job_mil integer not null default 0;    -- جهة العمل: عسكري / حكومي / خاص / أخرى
alter table tv_ops_daily add column if not exists job_gov integer not null default 0;
alter table tv_ops_daily add column if not exists job_pvt integer not null default 0;
alter table tv_ops_daily add column if not exists job_oth integer not null default 0;
alter table tv_ops_daily add column if not exists dp_n integer not null default 0;       -- باقة دعم الدفعة المقدمة
alter table tv_ops_daily add column if not exists dp_sum numeric not null default 0;
alter table tv_ops_daily add column if not exists ik_n integer not null default 0;       -- الدعم العيني
alter table tv_ops_daily add column if not exists ik_sum numeric not null default 0;
alter table tv_ops_daily add column if not exists mil_n integer not null default 0;      -- مستفيد مبادرة العسكريين
alter table tv_ops_daily add column if not exists mile_n integer not null default 0;     -- الدعم الإضافي للعسكريين (الصندوق)
alter table tv_ops_daily add column if not exists dh_n integer not null default 0;       -- منتج ذرى بلس
-- الثابت المكافئ (Flat) لكل عقد بنسبته ومدته الفعلية من الملف — مجموع وعدد
alter table tv_ops_daily add column if not exists flat_sum numeric not null default 0;
alter table tv_ops_daily add column if not exists flat_n integer not null default 0;

create table if not exists tv_employee_roster (
  name text primary key,
  district text not null default '',        -- المنطقة (الوسطى/الغربية/الشرقية/SMART) = «موقع العمل» بملف التخصيص
  site text not null default '',            -- موقع العمل الفعلي (الضاحية/مركز البيع/المبيعات الهاتفية…)
  job text not null default '',             -- AGENT / SUPERVISOR / MANAGER …
  type text not null default '',            -- Direct-Sale / Tele-Sale …
  supervisor text not null default '',
  manager text not null default '',
  start_date date,
  resigned boolean not null default false,
  resigned_at date,
  updated_at timestamptz not null default now()
);
alter table tv_employee_roster enable row level security;

create table if not exists tv_ops_book (
  booking_date date not null,
  project_name text not null default '',
  dest text not null default '',
  sector text not null default '',
  kind text not null default 'other',
  channel text not null default '',
  status text not null,                     -- c = تحوّل لعقد، r = حجز قائم
  cnt integer not null default 0,
  ist integer not null default 0,           -- حجز قائم موقّع عقد استصناعه
  days_sum numeric not null default 0, days_n integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (booking_date, project_name, dest, sector, kind, channel, status)
);
alter table tv_ops_book enable row level security;

create table if not exists tv_bank_policy (
  bank text primary key,
  ord integer not null default 0,
  month text,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table tv_bank_policy enable row level security;

-- نسب وسياسات البنوك المعلنة (سبتمبر 2026م) — بيانات أولية فقط إن كان الجدول فارغاً؛ ملف الشهر التالي يُرفع من الشاشة («⬆ رفع ملف»)
insert into tv_bank_policy (bank, ord, month, data)
select r->>'bank', (r->>'ord')::int, r->>'month', r->'data'
from jsonb_array_elements('[{"bank": "alinma", "ord": 1, "month": "سبتمبر 2026م", "data": {"key": "alinma", "name": "مصرف الانماء", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.0395, "sub_nt": 0.0505, "uns_t": 0.0395, "uns_nt": 0.0505}, "non_transfer": true, "note": null, "init": {"min_margin": false, "easy_inst": true, "support_eq": true, "mod": true, "dhura": true, "guarantee": true}, "pol": {"amount": "10,000,000", "term": "30 سنة", "age": "75 سنة", "sal": {"gov_t": "3,000", "gov_nt": "6000", "pvt_t": "3,000", "pvt_nt": "6000", "ret_t": "3000", "ret_nt": "7000"}, "svc": {"gov_t": "شهر", "gov_nt": "6أشهر", "pvt_t": "3اشهر", "pvt_nt": "12شهر"}}}}, {"bank": "saib", "ord": 2, "month": "سبتمبر 2026م", "data": {"key": "saib", "name": "البنك الاستثمار", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.0416, "sub_nt": null, "uns_t": 0.0416, "uns_nt": null}, "non_transfer": false, "note": null, "init": {"min_margin": false, "easy_inst": false, "support_eq": false, "mod": true, "dhura": false, "guarantee": true}, "pol": {"amount": "200,0000 - 4,000,000", "term": "25", "age": "21-75", "sal": {"gov_t": "5,000", "gov_nt": "لا يوجد", "pvt_t": "5,000", "pvt_nt": "لا يوجد", "ret_t": "5,000", "ret_nt": "لا يوجد"}, "svc": {"gov_t": "بدون حد ادنى", "gov_nt": "لا يوجد", "pvt_t": "3اشهر", "pvt_nt": "لا يوجد"}}}}, {"bank": "jazira", "ord": 3, "month": "سبتمبر 2026م", "data": {"key": "jazira", "name": "بنك الجزيرة", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.045, "sub_nt": 0.0464, "uns_t": 0.045, "uns_nt": 0.0464}, "non_transfer": true, "note": null, "init": {"min_margin": false, "easy_inst": false, "support_eq": true, "mod": false, "dhura": false, "guarantee": null}, "pol": {"amount": "8,000,000", "term": "25 سنة", "age": "75 سنه", "sal": {"gov_t": "3,000", "gov_nt": "7500", "pvt_t": "3,000", "pvt_nt": "7500", "ret_t": "3,000", "ret_nt": "7500"}, "svc": {"gov_t": "من اول تعيين", "gov_nt": "6 اشهر", "pvt_t": "6 اشهر", "pvt_nt": "6 اشهر"}}}}, {"bank": "anb", "ord": 4, "month": "سبتمبر 2026م", "data": {"key": "anb", "name": "البنك العربي", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.0449, "sub_nt": null, "uns_t": 0.0449, "uns_nt": null}, "non_transfer": false, "note": null, "init": {"min_margin": false, "easy_inst": false, "support_eq": false, "mod": true, "dhura": false, "guarantee": true}, "pol": {"amount": "200,000 - 5,000,000", "term": "5سنوات- 30 سنة", "age": "18- 75", "sal": {"gov_t": "7,000", "gov_nt": "لايوجد", "pvt_t": "7,000", "pvt_nt": "لايوجد", "ret_t": "5,000", "ret_nt": "لا يوجد"}, "svc": {"gov_t": "شهر", "gov_nt": "لايوجد", "pvt_t": "3أشهر", "pvt_nt": "لايوجد"}}}}, {"bank": "alt", "ord": 5, "month": "سبتمبر 2026م", "data": {"key": "alt", "name": "التمويل البديل - البنك الأهلي", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.0375, "sub_nt": 0.0375, "uns_t": null, "uns_nt": null}, "non_transfer": true, "note": "الشروط : - تحديد سقف سعر الوحدة السكنية بما لا يتجاوز 1,150,000 ريال سعودي", "init": {"min_margin": false, "easy_inst": false, "support_eq": true, "mod": true, "dhura": false, "guarantee": true}, "pol": {"amount": "220,000- 3,500,000", "term": "10سنة - 30 سنة", "age": "20 - 75", "sal": {"gov_t": "3,000", "gov_nt": "3000", "pvt_t": "3,000", "pvt_nt": "3000", "ret_t": "3,000", "ret_nt": "3000"}, "svc": {"gov_t": "فور التعيين", "gov_nt": "فور التعيين", "pvt_t": "3أشهر", "pvt_nt": "3أشهر"}}}}, {"bank": "snb", "ord": 6, "month": "سبتمبر 2026م", "data": {"key": "snb", "name": "البنك الأهلي", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.0468, "sub_nt": 0.0518, "uns_t": 0.0518, "uns_nt": 0.0568}, "non_transfer": true, "note": "2.99%", "init": {"min_margin": false, "easy_inst": true, "support_eq": true, "mod": true, "dhura": true, "guarantee": false}, "pol": {"amount": "100,000 - 7,000,000", "term": "سنة - 30 سنة", "age": "20 - 75", "sal": {"gov_t": "5,000", "gov_nt": "10000", "pvt_t": "5,000", "pvt_nt": "10000", "ret_t": "4,000", "ret_nt": "X"}, "svc": {"gov_t": "شهر", "gov_nt": "12أشهر", "pvt_t": "3أشهر", "pvt_nt": "12أشهر"}}}}, {"bank": "riyad", "ord": 7, "month": "سبتمبر 2026م", "data": {"key": "riyad", "name": "بنك الرياض", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.046, "sub_nt": 0.0465, "uns_t": 0.049, "uns_nt": 0.057}, "non_transfer": true, "note": null, "init": {"min_margin": false, "easy_inst": true, "support_eq": true, "mod": false, "dhura": false, "guarantee": false}, "pol": {"amount": "5,000,000", "term": "25", "age": "75", "sal": {"gov_t": "5,000", "gov_nt": "8000", "pvt_t": "5,000", "pvt_nt": "8000", "ret_t": "شهر", "ret_nt": "3أشهر"}, "svc": {"gov_t": "شهر", "gov_nt": "3أشهر", "pvt_t": "3أشهر", "pvt_nt": "3أشهر"}}}}, {"bank": "bilad", "ord": 8, "month": "سبتمبر 2026م", "data": {"key": "bilad", "name": "بنك البلاد", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.046, "sub_nt": 0.056, "uns_t": 0.046, "uns_nt": 0.056}, "non_transfer": true, "note": "يتم إضافة 100 نقطة للعملاء الراغبين في تقسيط الدفعة المقدمة خلال فترة بناء المشروع", "init": {"min_margin": false, "easy_inst": true, "support_eq": true, "mod": true, "dhura": true, "guarantee": false}, "pol": {"amount": "200,000 - 5,000,000", "term": "سنة - 25 سنة", "age": "65-18سنة", "sal": {"gov_t": "3,000", "gov_nt": "15000", "pvt_t": "7,000", "pvt_nt": "15000", "ret_t": "5,000", "ret_nt": "لايوجد"}, "svc": {"gov_t": "شهر", "gov_nt": "شهر", "pvt_t": "6أشهر", "pvt_nt": "12شهر"}}}}, {"bank": "bsf", "ord": 9, "month": "سبتمبر 2026م", "data": {"key": "bsf", "name": "بنك الفرنسي", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.043, "sub_nt": null, "uns_t": 0.043, "uns_nt": null}, "non_transfer": false, "note": "اعلى من 20 الف 4.20%", "init": {"min_margin": false, "easy_inst": true, "support_eq": false, "mod": true, "dhura": false, "guarantee": true}, "pol": {"amount": "5,000,000", "term": "للمدعوم 30 سنة - غير المدعوم 25 سنة", "age": "من 21 الى 80 سنة", "sal": {"gov_t": "4,000", "gov_nt": "لايوجد", "pvt_t": "4,000", "pvt_nt": "لايوجد", "ret_t": "4,000", "ret_nt": "لايوجد"}, "svc": {"gov_t": "شهر", "gov_nt": "لا يوجد", "pvt_t": "3اشهر", "pvt_nt": "لا يوجد"}}}}, {"bank": "rajhi", "ord": 10, "month": "سبتمبر 2026م", "data": {"key": "rajhi", "name": "مصرف الراجحي", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.039, "sub_nt": 0.039, "uns_t": 0.039, "uns_nt": 0.039}, "non_transfer": true, "note": "تبدا من 5 خمس سنوات 2.89% الى 10 سنوات2.99% بدون خاصية المتزايد", "init": {"min_margin": false, "easy_inst": false, "support_eq": true, "mod": true, "dhura": false, "guarantee": true}, "pol": {"amount": "5,000,000", "term": "30 سنة", "age": "77 المتقاعد-75على راس العمل", "sal": {"gov_t": "5,000صافي الراتب بشرط الإجمالي 6000 في التعريف", "gov_nt": "10,000 للمتقاعد -7000 على راس العمل", "pvt_t": "7000 على راس العمل", "pvt_nt": "10000", "ret_t": "6,000", "ret_nt": "10000"}, "svc": {"gov_t": "شهر", "gov_nt": "3أشهر", "pvt_t": "12شهر", "pvt_nt": "سنتين"}}}}, {"bank": "sab", "ord": 11, "month": "سبتمبر 2026م", "data": {"key": "sab", "name": "البنك الأول", "feat": true, "down_pkg": true, "rates": {"sub_t": 0.041, "sub_nt": null, "uns_t": 0.041, "uns_nt": null}, "non_transfer": false, "note": "3.45% للعملاء بصافي راتب 25,000 ريال وأعلى", "init": {"min_margin": false, "easy_inst": true, "support_eq": false, "mod": null, "dhura": true, "guarantee": true, "mod_note": "جاري العمل عليها وسيتم اطلاقها قريباً"}, "pol": {"amount": "150,000- 5,000,000", "term": "سنتين - 30 سنة", "age": "21 - 77", "sal": {"gov_t": "3,500", "gov_nt": "لايوجد", "pvt_t": "3500", "pvt_nt": "لايوجد", "ret_t": "3,500", "ret_nt": "لايوجد"}, "svc": {"gov_t": "3أشهر", "gov_nt": "لايوجد", "pvt_t": "شهر", "pvt_nt": "لايوجد"}}}}]'::jsonb) r
where not exists (select 1 from tv_bank_policy);

-- رفع على دفعات (الأولى تمسح القديم) — يتطلّب صلاحية أدمن فعلية
create or replace function admin_load_tv_ops(p_admin text, p_pass text, p_table text, p_rows jsonb, p_reset boolean)
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

  if p_table = 'daily' then
    if p_reset then delete from tv_ops_daily where true; end if;
    insert into tv_ops_daily (contract_date, project_name, dest, sector, kind, channel, employee, work, bank,
                              cnt, val_sum, val_n, rate_sum, rate_n, term_sum, term_n, ben, days_sum, days_n,
                              fa_sum, fa_n, sal_sum, sal_n, inst_sum, inst_n, fam_sum, fam_n, job_mil, job_gov, job_pvt, job_oth,
                              dp_n, dp_sum, ik_n, ik_sum, mil_n, mile_n, dh_n, flat_sum, flat_n)
    select (r->>'d')::date, coalesce(btrim(r->>'p'), ''), coalesce(btrim(r->>'dest'), ''), coalesce(btrim(r->>'s'), ''),
           coalesce(r->>'k', 'other'), coalesce(btrim(r->>'ch'), ''), coalesce(btrim(r->>'e'), ''), coalesce(btrim(r->>'w'), ''),
           coalesce(btrim(r->>'b'), ''),
           sum(coalesce((r->>'n')::int, 0)), sum(coalesce((r->>'vs')::numeric, 0)), sum(coalesce((r->>'vn')::int, 0)),
           sum(coalesce((r->>'rs')::numeric, 0)), sum(coalesce((r->>'rn')::int, 0)),
           sum(coalesce((r->>'ts')::numeric, 0)), sum(coalesce((r->>'tn')::int, 0)), sum(coalesce((r->>'ben')::int, 0)),
           sum(coalesce((r->>'ds')::numeric, 0)), sum(coalesce((r->>'dn')::int, 0)),
           sum(coalesce((r->>'fa')::numeric, 0)), sum(coalesce((r->>'fan')::int, 0)), sum(coalesce((r->>'sal')::numeric, 0)), sum(coalesce((r->>'saln')::int, 0)),
           sum(coalesce((r->>'inst')::numeric, 0)), sum(coalesce((r->>'instn')::int, 0)), sum(coalesce((r->>'fam')::numeric, 0)), sum(coalesce((r->>'famn')::int, 0)),
           sum(coalesce((r->>'jm')::int, 0)), sum(coalesce((r->>'jg')::int, 0)), sum(coalesce((r->>'jp')::int, 0)), sum(coalesce((r->>'jo')::int, 0)),
           sum(coalesce((r->>'dpn')::int, 0)), sum(coalesce((r->>'dps')::numeric, 0)), sum(coalesce((r->>'ikn')::int, 0)), sum(coalesce((r->>'iks')::numeric, 0)),
           sum(coalesce((r->>'mil')::int, 0)), sum(coalesce((r->>'mile')::int, 0)), sum(coalesce((r->>'dh')::int, 0)),
           sum(coalesce((r->>'fls')::numeric, 0)), sum(coalesce((r->>'fln')::int, 0))
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'d', '') is not null
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    on conflict (contract_date, project_name, dest, sector, kind, channel, employee, work, bank) do update set
      cnt = tv_ops_daily.cnt + excluded.cnt, val_sum = tv_ops_daily.val_sum + excluded.val_sum, val_n = tv_ops_daily.val_n + excluded.val_n,
      rate_sum = tv_ops_daily.rate_sum + excluded.rate_sum, rate_n = tv_ops_daily.rate_n + excluded.rate_n,
      term_sum = tv_ops_daily.term_sum + excluded.term_sum, term_n = tv_ops_daily.term_n + excluded.term_n,
      ben = tv_ops_daily.ben + excluded.ben, days_sum = tv_ops_daily.days_sum + excluded.days_sum,
      days_n = tv_ops_daily.days_n + excluded.days_n,
      fa_sum = tv_ops_daily.fa_sum + excluded.fa_sum, fa_n = tv_ops_daily.fa_n + excluded.fa_n,
      sal_sum = tv_ops_daily.sal_sum + excluded.sal_sum, sal_n = tv_ops_daily.sal_n + excluded.sal_n,
      inst_sum = tv_ops_daily.inst_sum + excluded.inst_sum, inst_n = tv_ops_daily.inst_n + excluded.inst_n,
      fam_sum = tv_ops_daily.fam_sum + excluded.fam_sum, fam_n = tv_ops_daily.fam_n + excluded.fam_n,
      job_mil = tv_ops_daily.job_mil + excluded.job_mil, job_gov = tv_ops_daily.job_gov + excluded.job_gov,
      job_pvt = tv_ops_daily.job_pvt + excluded.job_pvt, job_oth = tv_ops_daily.job_oth + excluded.job_oth,
      dp_n = tv_ops_daily.dp_n + excluded.dp_n, dp_sum = tv_ops_daily.dp_sum + excluded.dp_sum,
      ik_n = tv_ops_daily.ik_n + excluded.ik_n, ik_sum = tv_ops_daily.ik_sum + excluded.ik_sum,
      mil_n = tv_ops_daily.mil_n + excluded.mil_n, mile_n = tv_ops_daily.mile_n + excluded.mile_n, dh_n = tv_ops_daily.dh_n + excluded.dh_n,
      flat_sum = tv_ops_daily.flat_sum + excluded.flat_sum, flat_n = tv_ops_daily.flat_n + excluded.flat_n,
      updated_at = now();
  elsif p_table = 'book' then
    if p_reset then delete from tv_ops_book where true; end if;
    insert into tv_ops_book (booking_date, project_name, dest, sector, kind, channel, status, cnt, ist, days_sum, days_n)
    select (r->>'d')::date, coalesce(btrim(r->>'p'), ''), coalesce(btrim(r->>'dest'), ''), coalesce(btrim(r->>'s'), ''),
           coalesce(r->>'k', 'other'), coalesce(btrim(r->>'ch'), ''), r->>'st',
           sum(coalesce((r->>'n')::int, 0)), sum(coalesce((r->>'ist')::int, 0)),
           sum(coalesce((r->>'ds')::numeric, 0)), sum(coalesce((r->>'dn')::int, 0))
    from jsonb_array_elements(p_rows) r
    where nullif(r->>'d', '') is not null and r->>'st' in ('c', 'r')
    group by 1, 2, 3, 4, 5, 6, 7
    on conflict (booking_date, project_name, dest, sector, kind, channel, status) do update set
      cnt = tv_ops_book.cnt + excluded.cnt, ist = tv_ops_book.ist + excluded.ist,
      days_sum = tv_ops_book.days_sum + excluded.days_sum, days_n = tv_ops_book.days_n + excluded.days_n, updated_at = now();
  elsif p_table = 'policy' then
    if p_reset then delete from tv_bank_policy where true; end if;
    insert into tv_bank_policy (bank, ord, month, data)
    select btrim(r->>'bank'), coalesce((r->>'ord')::int, 0), nullif(btrim(r->>'month'), ''), coalesce(r->'data', '{}'::jsonb)
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'bank'), '') is not null
    on conflict (bank) do update set ord = excluded.ord, month = excluded.month, data = excluded.data, updated_at = now();
  elsif p_table = 'roster' then
    if p_reset then delete from tv_employee_roster where true; end if;
    insert into tv_employee_roster (name, district, site, job, type, supervisor, manager, start_date, resigned, resigned_at)
    select distinct on (btrim(r->>'name')) btrim(r->>'name'), coalesce(btrim(r->>'district'), ''), coalesce(btrim(r->>'site'), ''),
           coalesce(btrim(r->>'job'), ''), coalesce(btrim(r->>'type'), ''), coalesce(btrim(r->>'sup'), ''), coalesce(btrim(r->>'mgr'), ''),
           nullif(r->>'start', '')::date, coalesce((r->>'resigned')::boolean, false), nullif(r->>'resigned_at', '')::date
    from jsonb_array_elements(p_rows) r
    where nullif(btrim(r->>'name'), '') is not null
    order by btrim(r->>'name'), coalesce((r->>'resigned')::boolean, false)
    on conflict (name) do update set district = excluded.district, site = excluded.site, job = excluded.job, type = excluded.type,
      supervisor = excluded.supervisor, manager = excluded.manager, start_date = excluded.start_date,
      resigned = excluded.resigned, resigned_at = excluded.resigned_at, updated_at = now();
  else
    return jsonb_build_object('ok', false, 'msg', 'جدول غير معروف');
  end if;
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'msg', 'حُفظ '||v_count||' صفاً', 'count', v_count);
end;
$$;

-- الصفحة التشغيلية لفترة ونطاق: القنوات (سلسلة زمنية ومقارنة بالفترة السابقة)، الموظفون، البنوك ونسبها، مؤشرات التشغيل،
-- تحويل الحجوزات وأعمار القائم منها، وقوائم الوجهات والمشاريع للتصفية، وسياسات البنوك المعلنة
create or replace function get_tv_ops(p_from date, p_to date, p_sector text default null, p_kind text default null,
                                      p_dest text default null, p_project text default null, p_channel text default null)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with f as (
    select d.*, tv_region(nullif(d.sector, ''), null) as sec from tv_ops_daily d
    where (p_sector is null or tv_region(nullif(d.sector, ''), null) = p_sector)
      and (p_kind is null or d.kind = p_kind)
      and (p_dest is null or d.dest = p_dest)
      and (p_project is null or d.project_name = p_project)
  ),
  fc as (select * from f where p_channel is null or channel = p_channel),
  cur as (select * from fc where contract_date between p_from and p_to),
  prv as (select * from fc where contract_date between p_from - (p_to - p_from + 1) and p_from - 1),
  b as (
    select k.* from tv_ops_book k
    where (p_sector is null or tv_region(nullif(k.sector, ''), null) = p_sector)
      and (p_kind is null or k.kind = p_kind)
      and (p_dest is null or k.dest = p_dest)
      and (p_project is null or k.project_name = p_project)
      and (p_channel is null or k.channel = p_channel)
  ),
  snap as (select coalesce(max(updated_at)::date, current_date) as d from tv_ops_book),
  monthly as (select (p_to - p_from) > 62 as m)
  select jsonb_build_object(
    'ok', true, 'from', p_from, 'to', p_to,
    'as_of', (select max(contract_date) from tv_ops_daily),
    'loaded', (select max(updated_at) from tv_ops_daily),
    'has_rate', exists(select 1 from tv_ops_daily where rate_n > 0),
    'has_term', exists(select 1 from tv_ops_daily where term_n > 0),
    'has_channel', exists(select 1 from tv_ops_daily where channel <> ''),
    'has_emp', exists(select 1 from tv_ops_daily where employee <> ''),
    'has_book', exists(select 1 from tv_ops_book),
    'has_fin', exists(select 1 from tv_ops_daily where fa_n > 0 or sal_n > 0 or job_mil + job_gov + job_pvt > 0),
    'bucket', case when (select m from monthly) then 'month' else 'day' end,
    -- سلسلة كل القنوات (القناة المختارة تُبرز بالشاشة) بنفس تصفية الوجهة/المشروع
    'series', coalesce((
      select jsonb_agg(jsonb_build_object('t', t, 'ch', channel, 'n', n) order by t)
      from (select case when (select m from monthly) then date_trunc('month', contract_date)::date else contract_date end as t,
                   channel, sum(cnt) as n
            from f where contract_date between p_from and p_to group by 1, 2) s
    ), '[]'::jsonb),
    'channels', coalesce((
      select jsonb_agg(jsonb_build_object('ch', channel, 'n', n, 'prev', pn) order by n desc)
      from (select coalesce(c.channel, p.channel) as channel, coalesce(c.n, 0) as n, coalesce(p.n, 0) as pn
            from (select channel, sum(cnt) as n from f where contract_date between p_from and p_to group by 1) c
            full join (select channel, sum(cnt) as n from f where contract_date between p_from - (p_to - p_from + 1) and p_from - 1 group by 1) p
              using (channel)) x
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object('e', employee, 'w', w, 'n', n, 'ch', ch, 'prev', pn) order by n desc, employee)
      from (
        select e.employee, e.n,
               (select work from cur c2 where c2.employee = e.employee group by work order by sum(cnt) desc limit 1) as w,
               (select channel from cur c3 where c3.employee = e.employee group by channel order by sum(cnt) desc limit 1) as ch,
               coalesce((select sum(cnt) from prv p where p.employee = e.employee), 0) as pn
        from (select employee, sum(cnt) as n from cur where employee <> '' group by 1 order by 2 desc limit 300) e
      ) z
    ), '[]'::jsonb),
    'banks', coalesce((
      select jsonb_agg(jsonb_build_object('b', bank, 'n', n, 'rs', rs, 'rn', rn, 'ts', ts, 'tn', tn, 'vs', vs, 'vn', vn, 'prev', pn,
               'fs', fs, 'fn', fln, 'fa', fa, 'fan', fan, 'sal', sal, 'saln', saln, 'jm', jm, 'jg', jg, 'jp', jp, 'dpn', dpn) order by n desc)
      from (select c.bank, sum(c.cnt) as n, sum(c.rate_sum) as rs, sum(c.rate_n) as rn, sum(c.term_sum) as ts, sum(c.term_n) as tn,
                   sum(c.flat_sum) as fs, sum(c.flat_n) as fln,
                   sum(c.val_sum) as vs, sum(c.val_n) as vn, sum(c.fa_sum) as fa, sum(c.fa_n) as fan, sum(c.sal_sum) as sal, sum(c.sal_n) as saln,
                   sum(c.job_mil) as jm, sum(c.job_gov) as jg, sum(c.job_pvt) as jp, sum(c.dp_n) as dpn,
                   coalesce((select sum(cnt) from prv p where p.bank = c.bank), 0) as pn
            from cur c group by 1) x
    ), '[]'::jsonb),
    'kpi', (
      select jsonb_build_object('n', coalesce(sum(cnt), 0), 'vs', coalesce(sum(val_sum), 0), 'vn', coalesce(sum(val_n), 0),
        'ben', coalesce(sum(ben), 0), 'cash', coalesce(sum(cnt) filter (where bank = ''), 0),
        'ds', coalesce(sum(days_sum), 0), 'dn', coalesce(sum(days_n), 0),
        'no_emp', coalesce(sum(cnt) filter (where employee = ''), 0), 'no_chan', coalesce(sum(cnt) filter (where channel = ''), 0),
        'projects', count(distinct project_name) filter (where cnt > 0),
        'fa', coalesce(sum(fa_sum), 0), 'fan', coalesce(sum(fa_n), 0), 'sal', coalesce(sum(sal_sum), 0), 'saln', coalesce(sum(sal_n), 0),
        'inst', coalesce(sum(inst_sum), 0), 'instn', coalesce(sum(inst_n), 0), 'fam', coalesce(sum(fam_sum), 0), 'famn', coalesce(sum(fam_n), 0),
        'jm', coalesce(sum(job_mil), 0), 'jg', coalesce(sum(job_gov), 0), 'jp', coalesce(sum(job_pvt), 0), 'jo', coalesce(sum(job_oth), 0),
        'dpn', coalesce(sum(dp_n), 0), 'dps', coalesce(sum(dp_sum), 0), 'ikn', coalesce(sum(ik_n), 0), 'iks', coalesce(sum(ik_sum), 0),
        'mil', coalesce(sum(mil_n), 0), 'mile', coalesce(sum(mile_n), 0), 'dh', coalesce(sum(dh_n), 0),
        'ts', coalesce(sum(term_sum), 0), 'tn', coalesce(sum(term_n), 0), 'fls', coalesce(sum(flat_sum), 0), 'fln', coalesce(sum(flat_n), 0),
        'prev', (select coalesce(sum(cnt), 0) from prv))
      from cur
    ),
    'book', (
      select jsonb_build_object(
        'c', coalesce(sum(cnt) filter (where status = 'c' and booking_date between p_from and p_to), 0),
        'r', coalesce(sum(cnt) filter (where status = 'r' and booking_date between p_from and p_to), 0),
        'open', coalesce(sum(cnt) filter (where status = 'r'), 0),
        'open_ist', coalesce(sum(ist) filter (where status = 'r'), 0),
        'a7', coalesce(sum(cnt) filter (where status = 'r' and (select d from snap) - booking_date <= 7), 0),
        'a30', coalesce(sum(cnt) filter (where status = 'r' and (select d from snap) - booking_date between 8 and 30), 0),
        'a90', coalesce(sum(cnt) filter (where status = 'r' and (select d from snap) - booking_date between 31 and 90), 0),
        'a91', coalesce(sum(cnt) filter (where status = 'r' and (select d from snap) - booking_date > 90), 0),
        'snap', (select d from snap))
      from b
    ),
    'dims', jsonb_build_object(
      'dests', coalesce((select jsonb_agg(jsonb_build_object('v', dest, 'n', n) order by n desc)
        from (select dest, sum(cnt) as n from tv_ops_daily d
              where dest <> '' and (p_sector is null or tv_region(nullif(d.sector, ''), null) = p_sector) and (p_kind is null or d.kind = p_kind)
              group by 1) x), '[]'::jsonb),
      'projects', coalesce((select jsonb_agg(jsonb_build_object('v', project_name, 'dest', dest, 'k', kind, 'n', n) order by n desc)
        from (select project_name, max(dest) as dest, max(kind) as kind, sum(cnt) as n from tv_ops_daily d
              where project_name <> '' and (p_sector is null or tv_region(nullif(d.sector, ''), null) = p_sector) and (p_kind is null or d.kind = p_kind)
                and (p_dest is null or d.dest = p_dest)
              group by 1) x), '[]'::jsonb),
      'channels', coalesce((select jsonb_agg(channel order by n desc) from (select channel, sum(cnt) n from tv_ops_daily where channel <> '' group by 1) x), '[]'::jsonb)),
    -- قائمة الموظفين (لإظهار من لم يسجّل عقداً بالفترة): من باشر قبل نهاية الفترة ولم يستقِل قبل بدايتها، بمنطقة الرأس إن اختيرت
    'has_roster', exists(select 1 from tv_employee_roster),
    'roster', coalesce((select jsonb_agg(jsonb_build_object('e', name, 'd', district, 's', site, 'j', job, 't', type, 'sup', supervisor) order by name)
      from tv_employee_roster r
      where not (r.resigned and (r.resigned_at is null or r.resigned_at < p_from))
        and (r.start_date is null or r.start_date <= p_to)
        and (p_sector is null or tv_region(nullif(btrim(r.district), ''), null) = p_sector)), '[]'::jsonb),
    'policy', coalesce((select jsonb_agg(jsonb_build_object('bank', bank, 'month', month, 'data', data) order by ord, bank) from tv_bank_policy), '[]'::jsonb)
  );
$$;
