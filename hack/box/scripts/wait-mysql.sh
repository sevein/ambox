#!/bin/bash
set -euo pipefail

attempts=${1:-60}
sleep_secs=${2:-0.5}

socket=/run/mysqld/mysqld.sock
ping_cmd=(mysqladmin --protocol=socket --socket="$socket" -uroot ping --silent)

for ((i=1; i<=attempts; i++)); do
  if "${ping_cmd[@]}" >/dev/null 2>&1; then
    exit 0
  fi
  sleep "$sleep_secs"
done

echo "wait-mysql: timeout waiting for socket $socket" >&2
exit 1
