#!/usr/bin/env bash
# ============================================================
# SalesPlace — نسخة احتياطية من قاعدة Supabase (Mac / Linux)
# ============================================================
# الاستعمال:
#   export SUPABASE_DB_URL='postgresql://postgres.xxxx:[YOUR-PASSWORD]@aws-0-xx.pooler.supabase.com:5432/postgres'
#   export SUPABASE_DB_PASSWORD='كلمة مرور قاعدة البيانات'
#   ./backup_supabase.sh
# المتطلبات: pg_dump 15+ (Mac: brew install libpq && brew link --force libpq)
# الناتج: backups/nhc_YYYY-MM-DD_HHMM.dump (+ _schema.sql). يحتفظ بآخر 30 نسخة.
# الاستعادة: pg_restore --clean --if-exists --no-owner --no-privileges --schema=public -d "$CONN" backups/nhc_....dump ثم app_security.sql
# تنبيه: النسخة تحوي بيانات المستخدمين والجلسات — احفظها في مكان آمن ولا ترفعها إلى GitHub.
# ============================================================
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; out="$here/backups"; keep=30
[ -n "${SUPABASE_DB_URL:-}" ] || { read -rp "رابط الاتصال (Session pooler 5432): " SUPABASE_DB_URL; }
[ -n "${SUPABASE_DB_PASSWORD:-}" ] || { read -rsp "كلمة مرور قاعدة البيانات: " SUPABASE_DB_PASSWORD; echo; }
command -v pg_dump >/dev/null || { echo "pg_dump غير موجود — ثبّت أدوات PostgreSQL"; exit 1; }
enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$SUPABASE_DB_PASSWORD")
conn="${SUPABASE_DB_URL/\[YOUR-PASSWORD\]/$enc}"
if [ "$conn" = "$SUPABASE_DB_URL" ] && ! [[ "$SUPABASE_DB_URL" =~ ://[^:]+:[^@]+@ ]]; then conn=$(sed -E "s#^(postgres(ql)?://[^:/@]+)@#\1:$enc@#" <<<"$SUPABASE_DB_URL"); fi
mkdir -p "$out"; stamp=$(date +%Y-%m-%d_%H%M); dump="$out/nhc_$stamp.dump"
echo "جارٍ النسخ الكامل..."; pg_dump --dbname="$conn" --schema=public --no-owner --no-privileges --format=custom --compress=6 --file="$dump"
pg_dump --dbname="$conn" --schema=public --no-owner --no-privileges --schema-only --file="$out/nhc_${stamp}_schema.sql"
echo "تم: $dump ($(du -h "$dump" | cut -f1))"
ls -1t "$out"/nhc_*.dump | tail -n +$((keep+1)) | while read -r f; do rm -f "$f" "${f%.dump}_schema.sql"; done
echo "جداول في النسخة:"; pg_restore --list "$dump" | grep "TABLE DATA" | awk '{print "  - "$(NF-1)}' | sort -u
