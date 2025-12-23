#!/bin/sh
set -e

: "${PYTHONPATH:=/src/src}"
export PYTHONPATH
cd /src

: "${AM_DASHBOARD_DJANGO_SETTINGS_MODULE:=archivematica.dashboard.settings.local}"
: "${DJANGO_SETTINGS_MODULE:=$AM_DASHBOARD_DJANGO_SETTINGS_MODULE}"
export DJANGO_SETTINGS_MODULE

# Ensure the dashboard DB configuration is always present, even when
# /etc/archivematica/archivematicaCommon/dbsettings is not mounted.
: "${ARCHIVEMATICA_DASHBOARD_CLIENT_ENGINE:=django.db.backends.mysql}"
: "${ARCHIVEMATICA_DASHBOARD_CLIENT_DATABASE:=MCP}"
: "${ARCHIVEMATICA_DASHBOARD_CLIENT_USER:=archivematica}"
: "${ARCHIVEMATICA_DASHBOARD_CLIENT_PASSWORD:=demo}"
: "${ARCHIVEMATICA_DASHBOARD_CLIENT_HOST:=localhost}"
: "${ARCHIVEMATICA_DASHBOARD_CLIENT_PORT:=3306}"
export ARCHIVEMATICA_DASHBOARD_CLIENT_ENGINE
export ARCHIVEMATICA_DASHBOARD_CLIENT_DATABASE
export ARCHIVEMATICA_DASHBOARD_CLIENT_USER
export ARCHIVEMATICA_DASHBOARD_CLIENT_PASSWORD
export ARCHIVEMATICA_DASHBOARD_CLIENT_HOST
export ARCHIVEMATICA_DASHBOARD_CLIENT_PORT
SEED_STAMP=${AM_DB_SEED_STAMP:-/var/lib/mysql/.am_db_seeded}
if [ -f "$SEED_STAMP" ]; then
  echo "dashboard-migrate: seed stamp present; skipping."
  exit 0
fi

for i in $(seq 1 40); do
  if mysqladmin ping -h127.0.0.1 --silent >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
# Ensure SS API is up before install
for i in $(seq 1 60); do
  status=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/ || true)
  if [ "$status" -ge 200 ] && [ "$status" -lt 500 ]; then
    break
  fi
  sleep 0.5
done
python3 /src/src/archivematica/dashboard/manage.py migrate --noinput
python3 /src/src/archivematica/dashboard/manage.py install \
  --username="test" --password="test" --email="test@test.com" \
  --org-name="test" --org-id="test" --api-key="test" \
  --ss-url="http://127.0.0.1:8001" --ss-user="test" --ss-api-key="test" \
  --site-url="http://127.0.0.1"
