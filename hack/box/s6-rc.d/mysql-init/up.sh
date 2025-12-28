#!/bin/sh
set -e
# Ubuntu's MySQL packages commonly configure root with unix_socket auth.
# Connecting over TCP to 127.0.0.1 as root will fail with "Access denied".
MYSQL_SOCKET=/run/mysqld/mysqld.sock
MYSQL="mysql --protocol=socket --socket=$MYSQL_SOCKET -uroot"

# Wait for MySQL to accept socket connections
/usr/local/bin/wait-mysql.sh 60 0.5

$MYSQL -e "CREATE DATABASE IF NOT EXISTS SS;"
$MYSQL -e "CREATE DATABASE IF NOT EXISTS MCP;"

$MYSQL -e "CREATE USER IF NOT EXISTS 'archivematica'@'%' IDENTIFIED BY 'demo';"
$MYSQL -e "GRANT ALL PRIVILEGES ON SS.* TO 'archivematica'@'%';"
$MYSQL -e "GRANT ALL PRIVILEGES ON MCP.* TO 'archivematica'@'%';"
$MYSQL -e "FLUSH PRIVILEGES;"
