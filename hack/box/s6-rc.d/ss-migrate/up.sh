#!/bin/sh
set -e
export PYTHONPATH="/src/hack/submodules/archivematica-storage-service/src:${PYTHONPATH:-/src/src}"

: "${SS_DJANGO_SETTINGS_MODULE:=archivematica.storage_service.storage_service.settings.local}"
: "${DJANGO_SETTINGS_MODULE:=$SS_DJANGO_SETTINGS_MODULE}"
export DJANGO_SETTINGS_MODULE

: "${SS_DB_URL:=mysql://archivematica:demo@localhost/SS}"
export SS_DB_URL
: "${SS_GNUPG_HOME_PATH:=/var/archivematica/storage_service/.gnupg}"
export SS_GNUPG_HOME_PATH
SEED_STAMP=${AM_DB_SEED_STAMP:-/var/lib/mysql/.am_db_seeded}
if [ -f "$SEED_STAMP" ]; then
  echo "ss-migrate: seed stamp present; skipping."
  exit 0
fi

MANAGE_PY=/src/hack/submodules/archivematica-storage-service/src/archivematica/storage_service/manage.py
if [ ! -f "$MANAGE_PY" ]; then
  echo "Storage Service manage.py not found at $MANAGE_PY" >&2
  exit 2
fi
/usr/local/bin/wait-mysql.sh 40 0.5
/venv-ss/bin/python3 "$MANAGE_PY" migrate --noinput
SS_ADMIN_USERNAME=${SS_ADMIN_USERNAME:-test}
SS_ADMIN_PASSWORD=${SS_ADMIN_PASSWORD:-test}
SS_ADMIN_EMAIL=${SS_ADMIN_EMAIL:-test@test.com}
SS_ADMIN_API_KEY=${SS_ADMIN_API_KEY:-test}

/venv-ss/bin/python3 "$MANAGE_PY" create_user \
  --username="$SS_ADMIN_USERNAME" \
  --password="$SS_ADMIN_PASSWORD" \
  --email="$SS_ADMIN_EMAIL" \
  --api-key="$SS_ADMIN_API_KEY" \
  --superuser
