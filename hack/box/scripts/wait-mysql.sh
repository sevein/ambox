#!/usr/bin/env bash
set -euo pipefail

# Wait for MySQL to be ready via socket connection.
# Usage: wait-mysql.sh [attempts] [sleep_seconds]

readonly attempts="${1:-60}"
readonly sleep_secs="${2:-0.5}"
readonly socket="/run/mysqld/mysqld.sock"
readonly ping_cmd=(mysqladmin --protocol=socket --socket="$socket" -uroot ping --silent)

for ((i = 1; i <= attempts; i++)); do
  if "${ping_cmd[@]}" &>/dev/null; then
    exit 0
  fi
  sleep "$sleep_secs"
done

echo "wait-mysql: timeout after $attempts attempts waiting for socket $socket" >&2
exit 1
