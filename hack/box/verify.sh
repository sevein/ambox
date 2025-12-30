#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DASH_HTML="$(mktemp -t ambox-dashboard.XXXXXX.html)"
LOGIN_HITS="$(mktemp -t ambox-login.XXXXXX.txt)"

cleanup() {
  rm -f "$DASH_HTML" "$LOGIN_HITS"
  if docker ps --format '{{.Names}}' | grep -q '^ambox-test$'; then
    docker stop ambox-test >/dev/null 2>&1 || true
  fi
  if [ -n "${MAKE_PID:-}" ]; then
    kill "$MAKE_PID" >/dev/null 2>&1 || true
    wait "$MAKE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

make -C "$ROOT_DIR/hack/box" run &
MAKE_PID=$!

DASH_OK=0
LOGIN_OK=0

for _ in {1..60}; do
  if curl -fsSL http://localhost:64080/ >"$DASH_HTML" 2>/dev/null; then
    DASH_OK=1
    break
  fi
  sleep 5
done

if [ "$DASH_OK" -eq 1 ]; then
  if grep -n -E 'login|Log in|Sign in' "$DASH_HTML" >"$LOGIN_HITS" 2>/dev/null; then
    LOGIN_OK=1
    echo "dashboard_ok=true"
    echo "login_form_snippet:"
    head -n 5 "$LOGIN_HITS"
  else
    echo "dashboard_ok=true"
    echo "login_form_snippet: not found"
  fi
else
  echo "dashboard_ok=false"
fi

if [ "$DASH_OK" -ne 1 ] || [ "$LOGIN_OK" -ne 1 ]; then
  exit 1
fi
