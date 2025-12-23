#!/bin/sh
set -e
# Ubuntu's MySQL packages commonly configure root with unix_socket auth.
# Connecting over TCP to 127.0.0.1 as root will fail with "Access denied".
MYSQL_SOCKET=/var/run/mysqld/mysqld.sock
if [ ! -S "$MYSQL_SOCKET" ]; then
  MYSQL_SOCKET=/run/mysqld/mysqld.sock
fi

MYSQL_ADMIN="mysqladmin --protocol=socket --socket=$MYSQL_SOCKET -uroot"
MYSQL="mysql --protocol=socket --socket=$MYSQL_SOCKET -uroot"

# Wait for MySQL to accept socket connections
for i in $(seq 1 60); do
  if $MYSQL_ADMIN ping --silent >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

$MYSQL -e "CREATE DATABASE IF NOT EXISTS SS;"
$MYSQL -e "CREATE DATABASE IF NOT EXISTS MCP;"

$MYSQL -e "CREATE USER IF NOT EXISTS 'archivematica'@'%' IDENTIFIED BY 'demo';"
$MYSQL -e "GRANT ALL PRIVILEGES ON SS.* TO 'archivematica'@'%';"
$MYSQL -e "GRANT ALL PRIVILEGES ON MCP.* TO 'archivematica'@'%';"
$MYSQL -e "FLUSH PRIVILEGES;"
