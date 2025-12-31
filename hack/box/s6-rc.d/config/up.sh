#!/usr/bin/env bash
set -e

SHARED_DIR=${AM_SHARED_DIRECTORY:-/var/archivematica/sharedDirectory}
CONFIG_DIR="$SHARED_DIR/sharedMicroServiceTasksConfigs/processingMCPConfigs"
DEFAULT_CONFIG=/src/hack/box/config/ambox.yaml
if [ -n "${AMBOX_CONFIG_FILE:-}" ]; then
  CONFIG_FILE=$AMBOX_CONFIG_FILE
elif [ -f "$DEFAULT_CONFIG" ]; then
  CONFIG_FILE=$DEFAULT_CONFIG
else
  CONFIG_FILE=/etc/ambox/config.yaml
fi
WORKFLOW_FILE=${AM_WORKFLOW_PATH:-/src/src/archivematica/MCPServer/assets/workflow.json}
SCHEMA_FILE=${AMBOX_SCHEMA_FILE:-/src/hack/box/config/schema.json}
LOADER=${AMBOX_CONFIG_LOADER:-/src/hack/box/config/loader.py}

/usr/local/bin/wait-file.sh "$CONFIG_DIR/defaultProcessingMCP.xml" 30 0.5
/usr/local/bin/wait-file.sh "$CONFIG_DIR/automatedProcessingMCP.xml" 30 0.5

DASHBOARD_URL=${AM_DASHBOARD_URL:-http://127.0.0.1:64080}
/usr/local/bin/wait-http.sh "$DASHBOARD_URL/" 60 0.5

if [ -f "$CONFIG_FILE" ]; then
  s6-setuidgid archivematica env \
    HOME=/var/archivematica \
    UV_CACHE_DIR=/var/archivematica/.cache/uv \
    /usr/local/bin/uv run "$LOADER" \
    --config "$CONFIG_FILE" \
    --output-dir "$CONFIG_DIR" \
    --workflow "$WORKFLOW_FILE" \
    --schema "$SCHEMA_FILE"
fi
