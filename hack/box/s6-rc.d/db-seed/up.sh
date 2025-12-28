#!/bin/sh
set -e

SEED_DIR=${AM_DB_SEED_DIR:-/docker-seed}
MCP_DUMP=${AM_DB_SEED_MCP_DUMP:-$SEED_DIR/mcp.sql.gz}
SS_DUMP=${AM_DB_SEED_SS_DUMP:-$SEED_DIR/ss.sql.gz}
SEED_STAMP=${AM_DB_SEED_STAMP:-/var/lib/mysql/.am_db_seeded}
SEED_MODE=${AM_DB_SEED:-auto}

if [ "$SEED_MODE" = "0" ] || [ "$SEED_MODE" = "false" ]; then
  echo "db-seed: AM_DB_SEED disabled; skipping."
  exit 0
fi

if [ -f "$SEED_STAMP" ]; then
  echo "db-seed: seed stamp present; skipping."
  exit 0
fi

if [ ! -r "$MCP_DUMP" ] || [ ! -r "$SS_DUMP" ]; then
  echo "db-seed: dump(s) missing in $SEED_DIR; skipping."
  exit 0
fi

MYSQL_SOCKET=/var/run/mysqld/mysqld.sock
if [ ! -S "$MYSQL_SOCKET" ]; then
  MYSQL_SOCKET=/run/mysqld/mysqld.sock
fi

MYSQL_ADMIN="mysqladmin --protocol=socket --socket=$MYSQL_SOCKET -uroot"
MYSQL="mysql --protocol=socket --socket=$MYSQL_SOCKET -uroot"

for i in $(seq 1 60); do
  if $MYSQL_ADMIN ping --silent >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
if ! $MYSQL_ADMIN ping --silent >/dev/null 2>&1; then
  echo "db-seed: MySQL not ready; aborting."
  exit 1
fi

mcp_tables=$($MYSQL -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='MCP';")
ss_tables=$($MYSQL -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='SS';")

if [ "${mcp_tables:-0}" -gt 0 ] || [ "${ss_tables:-0}" -gt 0 ]; then
  echo "db-seed: database already initialized; skipping."
  exit 0
fi

echo "db-seed: importing MCP dump..."
{ echo "SET FOREIGN_KEY_CHECKS=0;"; gunzip -c "$MCP_DUMP"; echo "SET FOREIGN_KEY_CHECKS=1;"; } | $MYSQL MCP
echo "db-seed: importing SS dump..."
{ echo "SET FOREIGN_KEY_CHECKS=0;"; gunzip -c "$SS_DUMP"; echo "SET FOREIGN_KEY_CHECKS=1;"; } | $MYSQL SS

touch "$SEED_STAMP"
echo "db-seed: completed."
