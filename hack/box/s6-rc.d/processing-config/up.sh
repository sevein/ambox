#!/bin/sh
set -e

STAMP=${AM_PROCESSING_CONFIG_STAMP:-/var/archivematica/sharedDirectory/.processing-config-updated}
if [ -f "$STAMP" ]; then
  echo "processing-config: stamp present; skipping."
  exit 0
fi

SHARED_DIR=${AM_SHARED_DIRECTORY:-/var/archivematica/sharedDirectory}
CONFIG_DIR="$SHARED_DIR/sharedMicroServiceTasksConfigs/processingMCPConfigs"

for i in $(seq 1 60); do
  if [ -f "$CONFIG_DIR/defaultProcessingMCP.xml" ] && [ -f "$CONFIG_DIR/automatedProcessingMCP.xml" ]; then
    break
  fi
  sleep 0.5
done

DASHBOARD_URL=${AM_DASHBOARD_URL:-http://127.0.0.1:64080}
for i in $(seq 1 60); do
  status=$(curl -s -o /dev/null -w '%{http_code}' "$DASHBOARD_URL/" || true)
  if [ "$status" -ge 200 ] && [ "$status" -lt 500 ]; then
    break
  fi
  sleep 0.5
done

s6-setuidgid archivematica env \
  HOME=/var/archivematica \
  UV_CACHE_DIR=/var/archivematica/.cache/uv \
  /usr/local/bin/uv run /usr/local/bin/disable-virus-scan.py

s6-setuidgid archivematica /bin/sh -c "touch \"$STAMP\""
