#!/bin/bash

set -e

SOCKET=/run/mysqld/mysqld.sock

# Passwords come from Docker secrets, never from the environment
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
MYSQL_PASSWORD=$(cat /run/secrets/db_password)

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

# The Debian package pre-creates system tables in the image, so only
# initialise the data directory if they are really missing
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing data directory..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

# First start only (our database does not exist yet): create DB + users
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    echo "Starting temporary MariaDB server for setup..."
    mysqld --skip-networking --socket=$SOCKET --user=mysql &
    pid="$!"

    echo "Waiting for MariaDB to be ready..."
    until mysqladmin --socket=$SOCKET ping >/dev/null 2>&1; do
        sleep 1
    done

    echo "Running setup SQL..."
    mysql --socket=$SOCKET -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

    echo "Shutting down temporary MariaDB..."
    mysqladmin --socket=$SOCKET -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait "$pid" || true
else
    echo "Database already initialized, skipping setup."
fi

# Run MariaDB in the foreground as PID 1
echo "Starting MariaDB..."
exec mysqld --user=mysql --datadir=/var/lib/mysql --socket=$SOCKET
