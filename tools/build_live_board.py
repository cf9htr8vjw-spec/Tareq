#!/usr/bin/env python3
"""يبني NHC_Live_Board.html — شاشة المبيعات الحيّة كملف مستقل تماماً عن التطبيق الأساسي.

المصدر الوحيد للشاشة يبقى SalesPlace_01.html (وضع ?tv=1)؛ هذا السكربت يقتطع منه
CSS الشاشة وعناصرها وكودها والدوال المشتركة التي تحتاجها (الاتصال بـ Supabase، قراءة
إكسل، تنسيق الأرقام) بعلامات نصية ثابتة، فأي تعديل على الشاشة يُعمل مرة واحدة في
الملف الأساسي ثم يُعاد تشغيل:  python3 tools/build_live_board.py
الملف الناتج لا يحوي الكتالوج المشفّر ولا شاشة الدخول ولا أي شاشة أخرى من التطبيق.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SalesPlace_01.html"
OUT = ROOT / "NHC_Live_Board.html"
s = SRC.read_text(encoding="utf-8")


def cut(start, end, *, include_end=False, frm=0):
    i = s.find(start, frm)
    if i < 0:
        sys.exit(f"anchor not found: {start[:60]!r}")
    j = s.find(end, i + len(start))
    if j < 0:
        sys.exit(f"end anchor not found after {start[:40]!r}: {end[:60]!r}")
    return s[i: j + (len(end) if include_end else 0)]


def line_starting(prefix):
    m = re.search(r"^" + re.escape(prefix) + r".*$", s, re.M)
    if not m:
        sys.exit(f"line not found: {prefix!r}")
    return m.group(0)


def func(sig):
    """دالة كاملة من توقيعها حتى أول سطر '}' في بداية السطر."""
    return cut(sig, "\n}\n", include_end=True)


css = cut("/* ===== TV board (?tv=1)", "/* print-only report header/footer")
markup = cut("<!-- TV board (?tv=1)", "\n<script>")
config = cut("<script>\n/* ====", "</script>", include_end=True)
xlsx = cut('<script id="xlsx-js">', "</script>", include_end=True)

helpers = "\n".join([
    line_starting("const $=id=>"),
    cut("const nf=new Intl.NumberFormat", "const priceLbl"),
    cut("const MNAMES=", "function periodLabel"),
    func("async function sbSelect("),
    func("async function sbCall("),
    cut("/* قراءة ورقة إكسل بأمان", "const UNIT_CODE_CANDIDATES"),  # xlsxFixRef/xlsxBestSheet + loadSheetJS + مطابقة الأعمدة
])
tv = cut("/* ---------- TV board (?tv=1): no-login", "if(isTvMode()) startTvMode();", include_end=True)
live = cut("/* ---------- سحب العقود الساعي", "/* ---- لوحة الإدارة ----")
upload = cut("/* ---- شاشة التلفزيون: رفع سحب جديد", "if(isTvMode()) tvInitUpload();", include_end=True)

# الملف المستقل هو الشاشة دائماً — لا حاجة لـ ?tv=1 بالرابط
TV_SWITCH = "function isTvMode(){ return tvParam('tv')==='1'; }"
if tv.count(TV_SWITCH) != 1:
    sys.exit("isTvMode() definition changed — update build_live_board.py")
tv = tv.replace(TV_SWITCH, "function isTvMode(){ return true; }")

icons = "\n".join([line_starting('<link rel="apple-touch-icon"'), line_starting('<link rel="icon"')])
fonts = "\n".join([line_starting('<link rel="preconnect" href="https://fonts.googleapis.com"'),
                   line_starting('<link href="https://fonts.googleapis.com/css2')])
# بيان PWA خاص بالشاشة: اسم مختلف عن التطبيق، ويفتح بملء الشاشة عند إضافته للشاشة الرئيسية (أفقي للتلفزيون، عمودي بتصميم الجوال)
manifest = ('<link rel="manifest" href="data:application/manifest+json,'
            '%7B%22name%22%3A%22NHC%20%E2%80%94%20%D8%A7%D9%84%D9%85%D8%A8%D9%8A%D8%B9%D8%A7%D8%AA%20%D8%A7%D9%84%D8%AD%D9%8A%D9%91%D8%A9%22'
            '%2C%22short_name%22%3A%22%D9%85%D8%A8%D9%8A%D8%B9%D8%A7%D8%AA%20NHC%22%2C%22lang%22%3A%22ar%22%2C%22dir%22%3A%22rtl%22'
            '%2C%22start_url%22%3A%22.%22%2C%22display%22%3A%22fullscreen%22%2C%22orientation%22%3A%22any%22'
            '%2C%22background_color%22%3A%22%23F4F1E9%22%2C%22theme_color%22%3A%22%230B4332%22%7D">')

out = f"""<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<!-- مُولَّد آلياً من SalesPlace_01.html بواسطة tools/build_live_board.py — لا تعدّل هذا الملف يدوياً -->
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0B4332">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="مبيعات NHC">
<meta name="robots" content="noindex,nofollow">
<title>NHC · شاشة المبيعات</title>
{manifest}
{icons}
{fonts}
<style>
*{{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}}
html,body{{height:100%}}
body{{background:#F4F1E9;color:#0B4332;font-family:"IBM Plex Sans Arabic",system-ui,sans-serif;font-size:14.5px;line-height:1.55}}
button{{font-family:inherit;cursor:pointer;border:none;background:none;color:inherit}}
input,select{{font-family:inherit;font-size:14px;color:#0B4332}}
{css}</style>
</head>
<body>
{markup}
{config}
{xlsx}
<script>
let splashDone=false;
{helpers}
{tv}

{live}
{upload}
</script>
</body>
</html>
"""
OUT.write_text(out, encoding="utf-8")
print(f"wrote {OUT.name}: {len(out.encode('utf-8'))/1024:.0f} KB")
