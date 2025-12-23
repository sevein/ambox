#!/bin/sh
set -e
# Wait for SS and Dashboard HTTP endpoints
for i in $(seq 1 60); do
  status=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/ || true)
  if [ "$status" -ge 200 ] && [ "$status" -lt 500 ]; then
    break
  fi
  sleep 0.5
done
for i in $(seq 1 60); do
  status=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8002/ || true)
  if [ "$status" -ge 200 ] && [ "$status" -lt 500 ]; then
    break
  fi
  sleep 0.5
done
