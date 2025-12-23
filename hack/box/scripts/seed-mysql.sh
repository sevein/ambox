#!/bin/sh
set -e

DATA_DIR=/var/lib/mysql
SOCKET_DIR=/run/mysqld
SOCKET_PATH=/run/mysqld/mysqld.sock
SEED_DIR=/docker-seed

if [ ! -d "$DATA_DIR/mysql" ]; then
  if command -v mariadb-install-db >/dev/null 2>&1; then
    mariadb-install-db --user=mysql --datadir="$DATA_DIR" >/dev/null
  elif command -v mysqld >/dev/null 2>&1; then
    mysqld --initialize-insecure --user=mysql --datadir="$DATA_DIR" >/dev/null
  else
    echo "seed-mysql: mysqld not found; cannot initialize data directory" >&2
    exit 1
  fi
fi

chown -R mysql:mysql "$DATA_DIR"
install -d -o mysql -g mysql -m 0775 "$SOCKET_DIR"

mysqld --user=mysql --datadir="$DATA_DIR" --skip-networking=0 \
  --socket="$SOCKET_PATH" \
  --character-set-server=utf8mb4 --collation-server=utf8mb4_0900_ai_ci &
mysql_pid=$!

MYSQL_ADMIN="mysqladmin --protocol=socket --socket=$SOCKET_PATH -uroot"
MYSQL="mysql --protocol=socket --socket=$SOCKET_PATH -uroot"

for i in $(seq 1 60); do
  if $MYSQL_ADMIN ping --silent >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
if ! $MYSQL_ADMIN ping --silent >/dev/null 2>&1; then
  echo "seed-mysql: MySQL did not become ready" >&2
  exit 1
fi

echo "seed-mysql: running mysql-init..."
sh /etc/s6-overlay/s6-rc.d/mysql-init/up.sh

echo "seed-mysql: running Storage Service migrations..."
su -s /bin/sh -c '\
  SS_PYTHONPATH="/src/hack/submodules/archivematica-storage-service/src:${PYTHONPATH:-/src/src}" \
  SS_DB_URL="mysql://archivematica:demo@localhost/SS" \
  SS_DJANGO_SETTINGS_MODULE="archivematica.storage_service.storage_service.settings.local" \
  DJANGO_SETTINGS_MODULE="archivematica.storage_service.storage_service.settings.local" \
  SS_GNUPG_HOME_PATH="/var/archivematica/storage_service/.gnupg" \
  PYTHONPATH="$SS_PYTHONPATH" \
  /venv-ss/bin/python3 /src/hack/submodules/archivematica-storage-service/src/archivematica/storage_service/manage.py migrate --noinput' archivematica

su -s /bin/sh -c '\
  SS_PYTHONPATH="/src/hack/submodules/archivematica-storage-service/src:${PYTHONPATH:-/src/src}" \
  SS_DB_URL="mysql://archivematica:demo@localhost/SS" \
  SS_DJANGO_SETTINGS_MODULE="archivematica.storage_service.storage_service.settings.local" \
  DJANGO_SETTINGS_MODULE="archivematica.storage_service.storage_service.settings.local" \
  SS_GNUPG_HOME_PATH="/var/archivematica/storage_service/.gnupg" \
  PYTHONPATH="$SS_PYTHONPATH" \
  /venv-ss/bin/python3 /src/hack/submodules/archivematica-storage-service/src/archivematica/storage_service/manage.py create_user \
    --username="test" --password="test" --email="test@test.com" --api-key="test" --superuser' archivematica

echo "seed-mysql: starting SS gunicorn for dashboard install..."
su -s /bin/sh -c '\
  SS_PYTHONPATH="/src/hack/submodules/archivematica-storage-service/src:${PYTHONPATH:-/src/src}" \
  SS_DB_URL="mysql://archivematica:demo@localhost/SS" \
  SS_DJANGO_SETTINGS_MODULE="archivematica.storage_service.storage_service.settings.local" \
  DJANGO_SETTINGS_MODULE="archivematica.storage_service.storage_service.settings.local" \
  SS_GNUPG_HOME_PATH="/var/archivematica/storage_service/.gnupg" \
  PYTHONPATH="$SS_PYTHONPATH" \
  /venv-ss/bin/python3 -m gunicorn \
    --config=/src/hack/submodules/archivematica-storage-service/install/storage-service.gunicorn-config.py \
    archivematica.storage_service.storage_service.wsgi:application' archivematica &
ss_pid=$!

for i in $(seq 1 60); do
  status=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/ || true)
  if [ "$status" -ge 200 ] && [ "$status" -lt 500 ]; then
    break
  fi
  sleep 0.5
done

echo "seed-mysql: running Dashboard migrations/install..."
su -s /bin/sh -c '\
  PYTHONPATH="/src/src" \
  DJANGO_SETTINGS_MODULE="archivematica.dashboard.settings.local" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_ENGINE="django.db.backends.mysql" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_DATABASE="MCP" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_USER="archivematica" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_PASSWORD="demo" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_HOST="localhost" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_PORT="3306" \
  /venv/bin/python3 /src/src/archivematica/dashboard/manage.py migrate --noinput' archivematica

su -s /bin/sh -c '\
  PYTHONPATH="/src/src" \
  DJANGO_SETTINGS_MODULE="archivematica.dashboard.settings.local" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_ENGINE="django.db.backends.mysql" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_DATABASE="MCP" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_USER="archivematica" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_PASSWORD="demo" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_HOST="localhost" \
  ARCHIVEMATICA_DASHBOARD_CLIENT_PORT="3306" \
  /venv/bin/python3 /src/src/archivematica/dashboard/manage.py install \
    --username="test" --password="test" --email="test@test.com" \
    --org-name="test" --org-id="test" --api-key="test" \
    --ss-url="http://127.0.0.1:8001" --ss-user="test" --ss-api-key="test" \
    --site-url="http://127.0.0.1"' archivematica

echo "seed-mysql: stopping SS gunicorn..."
kill "$ss_pid"
wait "$ss_pid" || true

echo "seed-mysql: dumping databases..."
install -d "$SEED_DIR"
mysqldump --protocol=socket --socket="$SOCKET_PATH" -uroot \
  --single-transaction --quick --skip-comments --compact --routines --triggers MCP \
  | gzip -9 > "$SEED_DIR/mcp.sql.gz"
mysqldump --protocol=socket --socket="$SOCKET_PATH" -uroot \
  --single-transaction --quick --skip-comments --compact --routines --triggers SS \
  | gzip -9 > "$SEED_DIR/ss.sql.gz"

echo "seed-mysql: shutting down MySQL..."
mysqladmin --protocol=socket --socket="$SOCKET_PATH" -uroot shutdown
wait "$mysql_pid" || true

echo "seed-mysql: completed."
