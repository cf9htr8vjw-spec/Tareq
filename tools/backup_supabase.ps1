# ============================================================
# SalesPlace — نسخة احتياطية من قاعدة Supabase (Windows PowerShell)
# ============================================================
# الاستعمال (من PowerShell):
#   .\backup_supabase.ps1
# أول مرة يسألك عن رابط الاتصال وكلمة المرور، ويحفظ الرابط فقط في backup_config.json بجانب السكربت
# (كلمة المرور لا تُحفظ في ملف — تُسأل كل مرة، أو ضعها في متغير البيئة SUPABASE_DB_PASSWORD).
#
# المتطلبات: أدوات PostgreSQL (pg_dump / pg_restore) — نزّلها من https://www.postgresql.org/download/windows/
#   واختر "Command Line Tools" فقط. تأكد أن الإصدار 15 فأعلى (Supabase يعمل على 15/17).
# رابط الاتصال: Supabase → Project Settings → Database → Connection string → Session pooler (المنفذ 5432)
#   يشبه: postgresql://postgres.xxxxxxxx:[YOUR-PASSWORD]@aws-0-eu-central-1.pooler.supabase.com:5432/postgres
#   (استعمل Session pooler لأن الاتصال المباشر IPv6 فقط. انسخه كما هو، السكربت يضع كلمة المرور مكان [YOUR-PASSWORD].)
#
# الناتج في مجلد backups\ :
#   nhc_YYYY-MM-DD_HHMM.dump   (صيغة pg_dump المضغوطة — للاستعادة الكاملة)
#   nhc_YYYY-MM-DD_HHMM_schema.sql (الجداول والدوال فقط، نص مقروء)
#   يحتفظ بآخر 30 نسخة ويحذف الأقدم.
#
# الاستعادة (إلى مشروع Supabase جديد أو نفس المشروع):
#   pg_restore --clean --if-exists --no-owner --no-privileges --schema=public -d "<رابط الاتصال بكلمة المرور>" backups\nhc_....dump
#   ثم شغّل app_security.sql مرة واحدة لإعادة ضبط الصلاحيات.
#
# تنبيه: الملف يحتوي بيانات المستخدمين (أسماء الدخول وتجزئات كلمات المرور) والجلسات وبيانات التخصيص —
#   احفظه في مكان آمن (OneDrive الخاص بالعمل مثلاً) ولا ترفعه إلى GitHub أو أي مكان عام.
# ============================================================

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $here "backup_config.json"
$outDir = Join-Path $here "backups"
$keep = 30

# 1) أدوات PostgreSQL
$pgdump = Get-Command pg_dump -ErrorAction SilentlyContinue
if (-not $pgdump) {
  $cands = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\pg_dump.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
  if ($cands) { $env:Path = (Split-Path $cands[0].FullName) + ";" + $env:Path; $pgdump = Get-Command pg_dump }
}
if (-not $pgdump) { Write-Host "لم أجد pg_dump — ثبّت PostgreSQL Command Line Tools ثم أعد المحاولة." -ForegroundColor Red; exit 1 }
Write-Host ("pg_dump: " + (& pg_dump --version))

# 2) رابط الاتصال (يُحفظ بلا كلمة مرور)
if (Test-Path $cfgPath) { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $cfg = $null }
if (-not $cfg -or -not $cfg.url) {
  $url = Read-Host "الصق رابط الاتصال (Session pooler, port 5432) من Supabase"
  $url = $url.Trim()
  @{ url = $url } | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
  Write-Host "حُفظ الرابط في $cfgPath (بلا كلمة المرور)."
} else { $url = $cfg.url }

# 3) كلمة المرور (من متغير البيئة أو سؤال)
$pw = $env:SUPABASE_DB_PASSWORD
if (-not $pw) {
  $sec = Read-Host "كلمة مرور قاعدة البيانات (Database password من Supabase)" -AsSecureString
  $pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$pwEnc = [uri]::EscapeDataString($pw)
$conn = $url -replace '\[YOUR-PASSWORD\]', $pwEnc
if ($conn -eq $url -and $url -notmatch '://[^:]+:[^@]+@') {   # الرابط بلا موضع لكلمة المرور — نحقنها بعد اسم المستخدم
  $conn = $url -replace '^(postgres(?:ql)?://[^:/@]+)@', ('$1:' + $pwEnc + '@')
}

# 4) التنفيذ
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$dump = Join-Path $outDir "nhc_$stamp.dump"
$schema = Join-Path $outDir "nhc_${stamp}_schema.sql"

Write-Host "جارٍ النسخ الكامل (schema public: الجداول والدوال والبيانات)..."
& pg_dump --dbname="$conn" --schema=public --no-owner --no-privileges --format=custom --compress=6 --file="$dump"
if ($LASTEXITCODE -ne 0) { Write-Host "فشل pg_dump (تحقق من الرابط وكلمة المرور والشبكة)." -ForegroundColor Red; exit 1 }

Write-Host "جارٍ نسخة الهيكل المقروءة (بلا بيانات)..."
& pg_dump --dbname="$conn" --schema=public --no-owner --no-privileges --schema-only --file="$schema"

$sz = [math]::Round((Get-Item $dump).Length / 1MB, 1)
Write-Host ("تم: " + $dump + "  (" + $sz + " MB)") -ForegroundColor Green

# 5) الاحتفاظ بآخر N نسخ
Get-ChildItem $outDir -Filter "nhc_*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -Skip $keep | ForEach-Object {
  Remove-Item $_.FullName -Force
  $s = $_.FullName -replace '\.dump$', '_schema.sql'; if (Test-Path $s) { Remove-Item $s -Force }
}

# 6) فحص سريع لمحتوى النسخة
Write-Host "جداول في النسخة:"
& pg_restore --list "$dump" | Select-String "TABLE DATA" | ForEach-Object { ($_ -split '\s+')[-2] } | Sort-Object -Unique | ForEach-Object { "  - $_" }
