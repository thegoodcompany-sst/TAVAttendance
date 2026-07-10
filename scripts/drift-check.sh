#!/usr/bin/env bash
# Drift detector: fails when web/ code references schema objects prod lacks
# (the 2026-06-27 outage class). Run before every web deploy; also runs in CI.
#
# Requires TAVA_DB_URL (prod Postgres connection string) and psql.
# No psql (e.g. this repo's dev Mac)? From a Claude session, dump the same
# json_build_object query below via the Supabase MCP execute_sql tool into a
# file and run: node scripts/check-web-schema.mjs <file>
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TAVA_DB_URL:?Set TAVA_DB_URL to the prod Postgres connection string}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
psql "$TAVA_DB_URL" -Atc "
select json_build_object(
  'tables',   (select json_agg(distinct table_name)   from information_schema.tables   where table_schema='public'),
  'columns',  (select json_agg(distinct column_name)  from information_schema.columns  where table_schema='public'),
  'routines', (select json_agg(distinct routine_name) from information_schema.routines where routine_schema='public')
);" > "$tmp"

node scripts/check-web-schema.mjs "$tmp"
