#!/bin/bash
set -euo pipefail

url=${1:-}
attempts=${2:-60}
sleep_secs=${3:-0.5}

if [ -z "$url" ]; then
  echo "wait-http: missing URL" >&2
  exit 2
fi

for ((i=1; i<=attempts; i++)); do
  status=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
  if [ "$status" -ge 200 ] && [ "$status" -lt 500 ]; then
    exit 0
  fi
  sleep "$sleep_secs"
done

echo "wait-http: timeout waiting for $url" >&2
exit 1
