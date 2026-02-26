#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/var/lib/mysql
SOCKET_DIR=/run/mysqld
SOCKET_PATH=/run/mysqld/mysqld.sock
SEED_DIR=/docker-seed

if [ -f "$SEED_DIR/mcp.sql.gz" ] && [ -f "$SEED_DIR/ss.sql.gz" ]; then
  echo "seed-mysql: seed dumps already present; skipping."
  exit 0
fi

if [ ! -d "$DATA_DIR/mysql" ]; then
  mysqld --initialize-insecure --user=mysql --datadir="$DATA_DIR" >/dev/null
fi

chown -R mysql:mysql "$DATA_DIR"
install -d -o mysql -g mysql -m 0775 "$SOCKET_DIR"

mysqld --user=mysql --datadir="$DATA_DIR" --skip-networking=0 \
  --socket="$SOCKET_PATH" \
  --character-set-server=utf8mb4 --collation-server=utf8mb4_0900_ai_ci &
mysql_pid=$!

MYSQL="mysql --protocol=socket --socket=$SOCKET_PATH -uroot"

if ! /usr/local/bin/wait-mysql.sh 60 0.5; then
  echo "seed-mysql: MySQL did not become ready" >&2
  exit 1
fi

echo "seed-mysql: creating databases and user..."
mysql --protocol=socket --socket="$SOCKET_PATH" -uroot --execute="CREATE DATABASE IF NOT EXISTS SS; CREATE DATABASE IF NOT EXISTS MCP; CREATE USER IF NOT EXISTS 'archivematica'@'%' IDENTIFIED BY 'demo'; GRANT ALL PRIVILEGES ON SS.* TO 'archivematica'@'%'; GRANT ALL PRIVILEGES ON MCP.* TO 'archivematica'@'%'; FLUSH PRIVILEGES;"

echo "seed-mysql: running Storage Service migrations..."
su -s /bin/bash archivematica -c '/command/s6-envdir /etc/ambox/envs/storage \
  /venv-ss/bin/python /src/hack/submodules/archivematica-storage-service/src/archivematica/storage_service/manage.py migrate --noinput'

su -s /bin/bash archivematica -c '/command/s6-envdir /etc/ambox/envs/storage \
  /venv-ss/bin/python /src/hack/submodules/archivematica-storage-service/src/archivematica/storage_service/manage.py create_user \
    --username="test" --password="test" --email="test@test.com" --api-key="test" --superuser'

echo "seed-mysql: starting SS gunicorn for dashboard install..."
su -s /bin/bash archivematica -c '/command/s6-envdir /etc/ambox/envs/storage \
  /venv-ss/bin/python -m gunicorn \
    --config=/src/hack/submodules/archivematica-storage-service/install/storage-service.gunicorn-config.py \
    archivematica.storage_service.storage_service.wsgi:application' &
ss_pid=$!

if ! /usr/local/bin/wait-http.sh http://127.0.0.1:8001/ 60 0.5; then
  echo "seed-mysql: Storage Service did not become ready" >&2
  exit 1
fi

echo "seed-mysql: running Dashboard migrations/install..."
su -s /bin/bash archivematica -c 'cd /src && /command/s6-envdir /etc/ambox/envs/dashboard \
  /venv/bin/python src/archivematica/dashboard/manage.py migrate --noinput'

su -s /bin/bash archivematica -c 'cd /src && /command/s6-envdir /etc/ambox/envs/dashboard \
  /venv/bin/python src/archivematica/dashboard/manage.py install \
    --username="test" --password="test" --email="test@test.com" \
    --org-name="test" --org-id="test" --api-key="test" \
    --ss-url="http://127.0.0.1:8001" --ss-user="test" --ss-api-key="test" \
    --site-url="http://127.0.0.1"'

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
