#!/usr/bin/env bash
# Explicitly destructive, restricted to Pass A's assigned local throwaway databases.
set -euo pipefail
cd "$(dirname "$0")"
db="${1:-tp_a}"
tz="${2:-UTC}"
case "$tz" in UTC|Asia/Singapore|America/Los_Angeles) ;; *) echo 'Unsupported test timezone' >&2; exit 2;; esac
case "$db" in tp_a|tp_a_scratch) ;; *) echo 'Only tp_a or tp_a_scratch is permitted' >&2; exit 2;; esac
# Discard inherited libpq options, including alternate services and password files.
for var in ${!PG@}; do unset "$var"; done
export PGPASSFILE=/dev/null
args=(-h localhost -p 55432 -U postgres)
log=$(mktemp)
trap 'rm -f "$log"' EXIT
passed=0
run() {
  if "$@" >"$log" 2>&1; then
    local count
    count=$(awk '/NOTICE:  PASS / {n++} END {print n+0}' "$log")
    passed=$((passed+count))
    echo "PASS $label ($count assertions)"
  else
    cat "$log" >&2
    echo "FAIL $label; summary: $passed assertions passed, 1 failed" >&2
    exit 1
  fi
}
label=reset
run dropdb "${args[@]}" --if-exists "$db"
run createdb "${args[@]}" "$db"
label=timezone
run psql -X "${args[@]}" -d "$db" -v ON_ERROR_STOP=1 -q -c "ALTER DATABASE \"$db\" SET timezone TO '$tz'"
for file in ../local/supabase_shim.sql ../migrations/*.sql; do
  label="$(basename "$file")"; run psql -X "${args[@]}" -d "$db" -v ON_ERROR_STOP=1 -q -f "$file"
done
label=schema_test.sql; run psql -X "${args[@]}" -d "$db" -v ON_ERROR_STOP=1 -q -f schema_test.sql
label=demo_week.sql; run psql -X "${args[@]}" -d "$db" -v ON_ERROR_STOP=1 -q -f ../seed/demo_week.sql
label=demo_week_repeat.sql; run psql -X "${args[@]}" -d "$db" -v ON_ERROR_STOP=1 -q -f ../seed/demo_week.sql
for file in *_test.sql; do
  [[ "$file" == schema_test.sql ]] && continue
  label="$file"; run psql -X "${args[@]}" -d "$db" -v ON_ERROR_STOP=1 -q -f "$file"
done
label=concurrency_test.py; run python3 concurrency_test.py "$db"
echo "SUMMARY: $passed assertions passed, 0 failed"
