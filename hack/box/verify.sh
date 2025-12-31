#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DASH_HTML="$(mktemp -t ambox-dashboard.XXXXXX.html)"
LOGIN_HITS="$(mktemp -t ambox-login.XXXXXX.txt)"

RESULT_DASH_LINE=""
RESULT_LOGIN_LINE=""
RESULT_SNIPPET=""

print_results() {
  if [ -n "$RESULT_DASH_LINE" ]; then
    echo "$RESULT_DASH_LINE"
  fi
  if [ -n "$RESULT_LOGIN_LINE" ]; then
    echo "$RESULT_LOGIN_LINE"
  fi
  if [ -n "$RESULT_SNIPPET" ]; then
    printf '%s\n' "$RESULT_SNIPPET"
  fi
}

cleanup() {
  local exit_code=$?
  rm -f "$DASH_HTML" "$LOGIN_HITS"
  if docker ps --format '{{.Names}}' | grep -q '^ambox-test$'; then
    docker stop ambox-test >/dev/null 2>&1 || true
  fi
  if [ -n "${MAKE_PID:-}" ]; then
    kill "$MAKE_PID" >/dev/null 2>&1 || true
    wait "$MAKE_PID" >/dev/null 2>&1 || true
  fi
  print_results
  exit "$exit_code"
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
  RESULT_DASH_LINE="dashboard_ok=true"
  if grep -n -E 'login|Log in|Sign in' "$DASH_HTML" >"$LOGIN_HITS" 2>/dev/null; then
    LOGIN_OK=1
    RESULT_LOGIN_LINE="login_form_snippet:"
    RESULT_SNIPPET="$(head -n 5 "$LOGIN_HITS")"
  else
    RESULT_LOGIN_LINE="login_form_snippet: not found"
  fi
else
  RESULT_DASH_LINE="dashboard_ok=false"
fi

if [ "$DASH_OK" -ne 1 ] || [ "$LOGIN_OK" -ne 1 ]; then
  exit 1
fi
