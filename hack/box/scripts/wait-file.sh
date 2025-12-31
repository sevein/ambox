#!/usr/bin/env bash
set -euo pipefail

# Wait for a file to exist.
# Usage: wait-file.sh <file> [timeout_seconds] [interval_seconds]

readonly file="${1:?wait-file: missing file argument}"
readonly timeout="${2:-30}"
readonly interval="${3:-0.5}"
readonly start=$SECONDS

while true; do
  [[ -f "$file" ]] && exit 0

  if (( SECONDS - start >= timeout )); then
    echo "wait-file: timeout after ${timeout}s waiting for $file" >&2
    exit 1
  fi

  sleep "$interval"
done
