import sys, openpyxl, datetime, json
src, dst = sys.argv[1], sys.argv[2]
wb = openpyxl.load_workbook(src)
ys = wb["إيراد 2026 والتحصيل"]
REG = {"الرياض":"الوسطى","المدينة المنورة":"الغربية","مكة المكرمة":"الغربية","تبوك":"الغربية","المنطقة الشرقية":"الشرقية"}
CITY = {"الرياض":"الرياض","المدينة المنورة":"المدينة المنورة","مكة المكرمة":"جدة","تبوك":"تبوك","المنطقة الشرقية":"الدمام"}
rows=[]; region=None
for r in ys.iter_rows(min_row=6, values_only=True):
    nm = r[0]
    if not nm: continue
    nm=str(nm).strip()
    if nm.startswith("إجمالي") or nm.startswith("الإيراد من"): continue
    if nm in REG: region=nm; continue
    rows.append((nm, region))
ws = wb.create_sheet("مفتاح المشاريع والمصادر")
ws["A1"] = "مفتاح المشاريع والمصادر"
meta = [("تاريخ القطع", datetime.datetime(2026,9,30)), ("لقطة نظام التخصيص", datetime.datetime(2026,10,1)), ("تقرير المالية", datetime.datetime(2026,9,30)),
        ("ملف عقود الدفعات المرنة", datetime.datetime(2026,9,6)), ("تصدير CRM", datetime.datetime(2026,10,15)), ("عدد المشاريع في الورقة المالية", len(rows)), ("عدد المشاريع المحتسبة في أداء البيع", len(rows)-5)]
for i,(k,v) in enumerate(meta):
    ws.cell(row=3+i, column=1, value=k); c=ws.cell(row=3+i, column=2, value=v)
    if isinstance(v, datetime.datetime): c.number_format="dd/mm/yyyy"
hdr=["المشروع كما يرد في هذا الملف","كود المشروع في نظام التخصيص","كود المشروع في نظام المالية","المدينة","المنطقة","النطاق"]
for j,h in enumerate(hdr): ws.cell(row=10, column=1+j, value=h)
codes={}
NOFIN={"رشا","رحاب الورود","رحاب الواجهة","رحاب بوابة مكة"}
EXCL={"مريفة","عبية","مجتمع الأصالة"}
for i,(nm,reg) in enumerate(rows):
    code = f"02-01-{1000+i:04d}"
    if i in (3,7): code = f"{code} + 02-01-{1500+i:04d}"
    dan = "دانية" in nm or "دانيه" in nm
    fin = "— لا يوجد —" if (dan or nm in NOFIN) else f"FIN-{300+i}"
    scope = "الدانيات مالي فقط" if dan else ("مستبعد مباع" if nm in EXCL else "محتسب")
    vals=[nm, code, fin, CITY[reg], REG[reg], scope]
    for j,v in enumerate(vals): ws.cell(row=11+i, column=1+j, value=v)
    codes[nm]={"codes":[c.strip() for c in code.split("+")],"region":reg}
wb.save(dst)
json.dump(codes, open(dst+".codes.json","w"), ensure_ascii=False)
print(len(rows), "projects")
