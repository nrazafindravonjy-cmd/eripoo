#!/usr/bin/env bash
# Runs the SQL tests on a throwaway database.
#
#   supabase/tests/run_local.sh --stub   # plain PostgreSQL + auth stub (partial)
#   supabase/tests/run_local.sh          # database already migrated by Supabase
#
# Connection through the usual PG* environment variables.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
psql_run() { psql -X -v ON_ERROR_STOP=1 -q "$@"; }

if [[ "${1:-}" == "--stub" ]]; then
  db="eripoo_test_$$"
  createdb "$db"
  trap 'dropdb --if-exists "$db"' EXIT
  export PGDATABASE="$db"
  psql_run -f "$here/local_stub/auth_stub.sql"
  for migration in "$here"/../migrations/*.sql; do
    psql_run -f "$migration"
  done
fi

status=0
for test in "$here"/sql/*.sql; do
  echo "== $(basename "$test")"
  if output="$(psql_run -f "$test" 2>&1)"; then
    printf '%s\n' "$output" | grep -o 'ok - .*' | sed 's/^/  /' || true
  else
    printf '%s\n' "$output" | grep -E 'ok - |FAILED|ERROR' | sed 's/^/  /'
    status=1
  fi
done
[[ $status -eq 0 ]] && echo "All SQL tests passed." || echo "SQL tests FAILED."
exit $status
