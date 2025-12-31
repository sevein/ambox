#!/usr/bin/env bash
set -euo pipefail

# Wait for an HTTP endpoint to respond with a 2xx-4xx status code.
# Usage: wait-http.sh <url> [attempts] [sleep_seconds]

readonly url="${1:?wait-http: missing URL argument}"
readonly attempts="${2:-60}"
readonly sleep_secs="${3:-0.5}"

for ((i = 1; i <= attempts; i++)); do
  status=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
  if [[ "$status" -ge 200 && "$status" -lt 500 ]]; then
    exit 0
  fi
  sleep "$sleep_secs"
done

echo "wait-http: timeout after $attempts attempts waiting for $url" >&2
exit 1
