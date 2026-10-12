#!/usr/bin/env python3
"""يبني NHC_Live_Board_DEMO.html — نسخة تجريبية من شاشة المبيعات الحيّة ببيانات وهمية.

يأخذ NHC_Live_Board.html (شغّل tools/build_live_board.py قبله)، ويستبدل إعدادات الاتصال
بقيم وهمية، ويحقن tools/demo_mock.js الذي يعترض نداءات القاعدة ويُرجع بيانات مولّدة،
ويضيف شريطاً واضحاً «نسخة تجريبية — أرقام وهمية». لا اتصال بأي قاعدة بيانات.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "NHC_Live_Board.html"
OUT = ROOT / "NHC_Live_Board_DEMO.html"
s = SRC.read_text(encoding="utf-8")
mock = (ROOT / "tools" / "demo_mock.js").read_text(encoding="utf-8")

url = re.compile(r'window\.SB_URL = "[^"]*";')
key = re.compile(r'window\.SB_KEY = "[^"]*";')
if len(url.findall(s)) != 1 or len(key.findall(s)) != 1:
    sys.exit("connection settings not found once — update build_demo_board.py")
s = url.sub('window.SB_URL = "https://demo.invalid";', s)
s = key.sub('window.SB_KEY = "demo";', s)

anchor = '<script id="xlsx-js">'
if s.count(anchor) != 1:
    sys.exit("xlsx anchor not found")
s = s.replace(anchor, "<script>\n" + mock + "\n</script>\n" + anchor)

s = s.replace("<title>NHC · شاشة المبيعات</title>", "<title>نسخة تجريبية · شاشة المبيعات</title>")
banner = ('<div style="position:fixed;top:0;left:50%;transform:translateX(-50%);z-index:9999;background:#C2491E;color:#fff;'
          'font:800 15px/1.6 \'IBM Plex Sans Arabic\',system-ui,sans-serif;padding:2px 18px;border-radius:0 0 12px 12px;'
          'pointer-events:none;direction:rtl">نسخة تجريبية — أرقام وأسماء وهمية للعرض فقط</div>')
if "</head>\n<body>" not in s:
    sys.exit("body tag not found")
s = s.replace("</head>\n<body>", "</head>\n<body>\n" + banner, 1)
OUT.write_text(s, encoding="utf-8")
print(f"wrote {OUT.name}: {len(s.encode('utf-8'))/1024:.0f} KB")
