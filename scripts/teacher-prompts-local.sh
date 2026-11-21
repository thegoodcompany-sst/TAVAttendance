#!/usr/bin/env bash
# Local fake-data launcher. Never load .env or accept a caller-supplied URL.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

usage() {
  cat <<'USAGE'
Usage: scripts/teacher-prompts-local.sh --db <assigned_db> [--reset] [--fixed-week] [--check]
  --db          Required supervisor-assigned throwaway database (Pass H: tp_h or tp_h2).
  --reset       Drop/recreate ONLY that local database; default preserves it.
  --fixed-week  Do not shift demo dates to today (combine with reset for Jan 2027).
  --check       Run SQL/concurrency/package unit tests, without starting web.
  --help        Show this message without connecting or changing anything.
Only localhost:55432, user postgres, PostgreSQL 17; real push is never enabled.
USAGE
}
fail() { printf '%s\n' "teacher-prompts: $*" >&2; exit 1; }
db_name='' reset=0 fixed_week=0 check=0
while (($#)); do
  case "$1" in
    --db) (($# >= 2)) || fail '--db needs a value'; [[ -z "$db_name" ]] || fail 'duplicate --db'; db_name=$2; shift 2 ;;
    --reset) reset=1; shift ;;
    --fixed-week) fixed_week=1; shift ;;
    --check) check=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail 'unknown option; use --help' ;;
  esac
done
[[ "$db_name" =~ ^tp_[a-z0-9_]{1,60}$ ]] || fail 'explicit valid --db is required'
case "$db_name" in postgres|template0|template1) fail 'reserved database name' ;; esac
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
web_dir="$repo_root/prototypes/teacher-prompts"
worker_dir="$repo_root/supabase/v2/functions"
pg_bundle=/workspace/tav-teacher-prompts/pgbin/package/native/bin
runner_tmp=$(mktemp -d /tmp/teacher-prompts-run.XXXXXX)
touch "$runner_tmp/pgpass" "$runner_tmp/pgservice.conf"
children=()
cleanup() {
  local code=$?
  trap - EXIT INT TERM
  for pid in "${children[@]}"; do kill -TERM -- "-$pid" 2>/dev/null || true; done
  for pid in "${children[@]}"; do wait "$pid" 2>/dev/null || true; done
  rm -rf -- "$runner_tmp"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for tool in python3 bun psql createdb dropdb pg_isready setsid; do
  command -v "$tool" >/dev/null || fail "missing dependency: $tool"
done
# Fresh environment excludes inherited database, Supabase and APNs credentials.
# psql also disables user startup/password/service files explicitly.
clean_env=(env -i "PATH=$PATH" LANG=C.UTF-8 "TMPDIR=$runner_tmp"
  "PGPASSFILE=$runner_tmp/pgpass" "PGSERVICEFILE=$runner_tmp/pgservice.conf" "PGSYSCONFDIR=$runner_tmp"
  PGCONNECT_TIMEOUT=5 NEXT_TELEMETRY_DISABLED=1)
psql_local() { "${clean_env[@]}" psql -X -w -h localhost -p 55432 -U postgres -d "$db_name" -v ON_ERROR_STOP=1 "$@"; }

# Check the entire integration input before touching the database. Never inspect
# .env contents; refuse their presence where Bun/Next could load them implicitly.
"${clean_env[@]}" python3 - "$repo_root" "$check" <<'PY'
import pathlib, sys
root=pathlib.Path(sys.argv[1]); check=sys.argv[2]=='1'
required=['supabase/v2/local/supabase_shim.sql',
 'supabase/v2/migrations/0001_core.sql','supabase/v2/migrations/0002_calendar.sql',
 'supabase/v2/migrations/0003_attendance_rpc.sql','supabase/v2/migrations/0004_prompt_scheduler.sql',
 'supabase/v2/seed/demo_week.sql','supabase/v2/functions/package.json',
 'supabase/v2/functions/bun.lock','supabase/v2/functions/teacher-prompt-dispatch/local.ts',
 'prototypes/teacher-prompts/package.json','prototypes/teacher-prompts/bun.lock']
if check:
 required += ['supabase/v2/tests/'+name+'_test.sql' for name in
  ('schema','calendar','rls','attendance','submission','scheduler','devices','demo')]
 required += ['supabase/v2/tests/concurrency_test.py', 'supabase/v2/tests/hostile_acl_setup.sql', 'supabase/v2/tests/runner_guard_test.py']
missing=[p for p in required if not (root/p).is_file()]
if missing:
 print('Integration inputs not ready:\n'+'\n'.join(missing), file=sys.stderr); sys.exit(1)
paths=set()
for leaf in (root/'prototypes/teacher-prompts',root/'supabase/v2/functions'):
 paths.update([leaf,*leaf.parents])
for directory in paths:
 if any(directory.glob('.env*')):
  sys.exit('Refusing startup: an automatic environment file is present in an app/ancestor directory.')
PY

# The server is shared, but every SQL connection below names only the assigned DB.
if ! "${clean_env[@]}" pg_isready -q -h localhost -p 55432 -U postgres -d "$db_name"; then
  if [[ -x "$pg_bundle/pg_ctl" && -x "$pg_bundle/initdb" ]]; then
    pg_ctl_bin="$pg_bundle/pg_ctl"; initdb_bin="$pg_bundle/initdb"
  else
    pg_ctl_bin=$(command -v pg_ctl) || fail 'Postgres server missing; install PostgreSQL 17 first'
    initdb_bin=$(command -v initdb) || fail 'initdb missing; install PostgreSQL 17 first'
  fi
  [[ $("$pg_ctl_bin" --version) == *' 17.'* ]] || fail 'PostgreSQL 17 server required'
  pg_data="/tmp/teacher-prompts-pg17-$UID"
  mkdir -p -- "$pg_data"
  if [[ ! -f "$pg_data/PG_VERSION" ]]; then
    "${clean_env[@]}" "$initdb_bin" -D "$pg_data" -U postgres --auth=trust --encoding=UTF8 --no-locale >"$runner_tmp/initdb.log" 2>&1 || fail 'initdb failed; no server started'
  fi
  [[ $(<"$pg_data/PG_VERSION") == 17 ]] || fail 'local data directory is not PostgreSQL 17'
  "${clean_env[@]}" "$pg_ctl_bin" -D "$pg_data" -l "$pg_data/server.log" \
    -o "-h localhost -p 55432 -k $pg_data" -w -t 30 start || fail 'local server could not start'
fi

if ((reset)); then
  "${clean_env[@]}" dropdb -w -h localhost -p 55432 -U postgres --if-exists "$db_name"
fi
new_database=0
if ! psql_local -qAtc 'SELECT 1' > /dev/null 2>"$runner_tmp/connect.log"; then
  "${clean_env[@]}" createdb -w -h localhost -p 55432 -U postgres "$db_name" || fail 'database creation failed (no fallback connection attempted)'
  new_database=1
fi
server_version=$(psql_local -qAtc 'SHOW server_version_num')
[[ "$server_version" =~ ^17[0-9]{4}$ ]] || fail 'connected server must be PostgreSQL 17'

# Store input hashes in the local database comment. This is a runner marker,
# not a migration-ledger claim or a production-schema assertion.
fingerprint=$("${clean_env[@]}" python3 - "$repo_root" <<'PY'
import hashlib, pathlib, sys
root=pathlib.Path(sys.argv[1]); h=hashlib.sha256()
paths=[root/'supabase/v2/local/supabase_shim.sql',
 *sorted((root/'supabase/v2/migrations').glob('*.sql')),root/'supabase/v2/seed/demo_week.sql']
for p in paths:
 h.update(str(p.relative_to(root)).encode()); h.update(b'\0'); h.update(p.read_bytes()); h.update(b'\0')
print(h.hexdigest())
PY
)
marker="teacher-prompts-local:v1:$fingerprint"
if ((new_database)); then
  psql_local -q -f "$repo_root/supabase/v2/local/supabase_shim.sql"
  if ((check)); then
    psql_local -q -f "$repo_root/supabase/v2/tests/hostile_acl_setup.sql"
  fi
  for migration in "$repo_root"/supabase/v2/migrations/*.sql; do
    printf 'Applying %s\n' "${migration##*/}"
    psql_local -q -f "$migration"
  done
  if ((check)); then
    printf '%s\n' 'Checking schema_test.sql before demo seed'
    psql_local -f "$repo_root/supabase/v2/tests/schema_test.sql"
  fi
  psql_local -q -f "$repo_root/supabase/v2/seed/demo_week.sql"
  psql_local -q -v db_name="$db_name" -v marker="$marker" <<'SQL'
SELECT format('COMMENT ON DATABASE %I IS %L', :'db_name', :'marker') \gexec
SQL
else
  (( !check )) || fail '--check needs a fresh database; use --reset --fixed-week to verify OFF defaults before seed'
  actual_marker=$(psql_local -qAtc "SELECT coalesce(shobj_description(oid,'pg_database'),'') FROM pg_database WHERE datname=current_database()")
  [[ "$actual_marker" == "$marker" ]] || fail 'existing DB has no matching runner/schema fingerprint; use --reset for the assigned throwaway DB'
fi
[[ $(psql_local -qAtc 'SELECT demo_enabled FROM public.runtime_settings WHERE id') == t ]] || fail 'database is not marked as a demo'
[[ $(psql_local -qAtc "SELECT enabled FROM public.feature_flags WHERE key='teacher_prompt_push'") == f ]] || fail 'real push flag must remain OFF'
# --check uses the seeded canonical fixtures unless the caller reused shifted data.
# Tests must own/rollback their fixtures; pass --reset --fixed-week for a fresh check.
if ((!fixed_week && !check)); then
  psql_local -qAtc 'BEGIN; SET LOCAL ROLE service_role; SELECT public.demo_shift_to_today(); COMMIT;'
fi

app_env=("${clean_env[@]}" "TEACHER_PROMPTS_DATABASE_URL=postgresql://postgres@localhost:55432/$db_name"
  "TEACHER_PROMPTS_DB_NAME=$db_name" "TP_DB=$db_name" TEACHER_PROMPTS_DEMO=1)
for package_dir in "$worker_dir" "$web_dir"; do
  (cd -- "$package_dir" && "${clean_env[@]}" bun --no-env-file install --frozen-lockfile)
done
if ((check)); then
  "${clean_env[@]}" python3 "$repo_root/supabase/v2/tests/runner_guard_test.py"
  for sql_test in "$repo_root"/supabase/v2/tests/*_test.sql; do
    [[ ${sql_test##*/} == schema_test.sql ]] && continue
    printf 'Checking %s\n' "${sql_test##*/}"
    psql_local -f "$sql_test"
  done
  (cd -- "$repo_root" && "${app_env[@]}" python3 supabase/v2/tests/concurrency_test.py "$db_name")
  (cd -- "$worker_dir" && "${app_env[@]}" bun --no-env-file run test)
  (cd -- "$web_dir" && "${app_env[@]}" bun --no-env-file run test)
  printf '%s\n' 'Local SQL, concurrency and package unit checks completed.'
  exit 0
fi
# Fail without stopping any other pass's server.
"${clean_env[@]}" python3 - <<'PY'
import socket
with socket.socket() as s:
 try: s.bind(('127.0.0.1',3100))
 except OSError: raise SystemExit('Port 3100 is in use; stop your own prior preview before retrying.')
PY
(cd -- "$repo_root" && exec "${app_env[@]}" setsid bun --no-env-file supabase/v2/functions/teacher-prompt-dispatch/local.ts --watch) &
children+=("$!")
(cd -- "$web_dir" && exec "${app_env[@]}" setsid bun --no-env-file run dev) &
children+=("$!")
# Wait for a real HTTP response, and fail if either child exits during startup.
ready=0
for ((attempt=0; attempt<60; attempt++)); do
  for pid in "${children[@]}"; do
    kill -0 "$pid" 2>/dev/null || fail 'worker or web exited during startup'
  done
  if "${clean_env[@]}" python3 - <<'PY'
import urllib.request, sys
try:
 opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 with opener.open('http://127.0.0.1:3100/demo', timeout=1) as response:
  sys.exit(0 if response.status == 200 else 1)
except Exception: sys.exit(1)
PY
  then ready=1; break; fi
  sleep 1
done
((ready)) || fail 'web did not become ready on port 3100 within startup window'
printf '%s\n' 'Fake data only; push is dry-run. Ctrl-C stops web and worker.' \
  'Choose account: http://127.0.0.1:3100/demo' \
  'Lessons:        http://127.0.0.1:3100/' \
  'Admin:          http://127.0.0.1:3100/admin'
# Wait for either child, then EXIT cleanup stops the other process group.
set +e
wait -n "${children[@]}"
child_status=$?
set -e
((child_status != 0)) || child_status=1
exit "$child_status"
