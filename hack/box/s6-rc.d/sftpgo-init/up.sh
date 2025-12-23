#!/bin/sh
set -e

SFTPGO_CONFIG_DIR=${SFTPGO_CONFIG_DIR:-/var/lib/sftpgo}
SFTPGO_CONFIG_FILE=${SFTPGO_CONFIG_FILE:-/etc/sftpgo/sftpgo.json}
SFTPGO_LOADDATA_FROM=${SFTPGO_LOADDATA_FROM:-/etc/sftpgo/initial-data.json}

if [ -f "$SFTPGO_LOADDATA_FROM" ]; then
  s6-setuidgid archivematica sftpgo initprovider \
    --config-dir "$SFTPGO_CONFIG_DIR" \
    --config-file "$SFTPGO_CONFIG_FILE" \
    --loaddata-from "$SFTPGO_LOADDATA_FROM" \
    --loaddata-mode 0
else
  s6-setuidgid archivematica sftpgo initprovider \
    --config-dir "$SFTPGO_CONFIG_DIR" \
    --config-file "$SFTPGO_CONFIG_FILE"
fi
