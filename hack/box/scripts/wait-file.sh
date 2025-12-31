#!/usr/bin/env bash
set -euo pipefail

# usage: wait-file.sh <file> [timeout_seconds] [interval_seconds]

file=$1
timeout=${2:-30}
interval=${3:-0.5}

start=$(date +%s)

while true; do
  if [[ -f "$file" ]]; then
    exit 0
  fi

  now=$(date +%s)
  if (( now - start >= timeout )); then
    echo "wait-file.sh: timeout waiting for $file" >&2
    exit 1
  fi

  sleep "$interval"
done
