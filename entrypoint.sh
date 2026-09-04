#!/bin/bash
set -e

# Default values
DB_HOST="${DB_HOST:-mysql}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-ofcms}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-12345678}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-123456}"
APP_BASE="/usr/local/tomcat/webapps/ofcms-admin"
DB_CONFIG="${APP_BASE}/WEB-INF/classes/conf/db-config.properties"
DB_PROPS="${APP_BASE}/WEB-INF/classes/conf/db.properties"

echo "Waiting for MySQL at ${DB_HOST}:${DB_PORT}..."

# Wait for MySQL to be ready
max_retries=30
retry_count=0
while [ $retry_count -lt $max_retries ]; do
    if mysqladmin ping -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASS}" --silent 2>/dev/null; then
        echo "MySQL is ready!"
        break
    fi
    retry_count=$((retry_count + 1))
    echo "Retry ${retry_count}/${max_retries} - MySQL not ready yet..."
    sleep 2
done

if [ $retry_count -eq $max_retries ]; then
    echo "ERROR: MySQL is not ready after ${max_retries} retries"
    exit 1
fi

# Update db-config.properties with Docker MySQL host
if [ -f "${DB_CONFIG}" ]; then
    sed -i "s|jdbc:mysql://[^?]*|jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}|g" "${DB_CONFIG}"
    sed -i "s|^jdbc.username=.*|jdbc.username=${DB_USER}|g" "${DB_CONFIG}"
    sed -i "s|^jdbc.password=.*|jdbc.password=${DB_PASS}|g" "${DB_CONFIG}"
    echo "Database config updated: ${DB_HOST}:${DB_PORT}/${DB_NAME}"
else
    echo "WARNING: db-config.properties not found at ${DB_CONFIG}"
fi

# Create db.properties to mark app as installed (required by JFWebConfig)
if [ ! -f "${DB_PROPS}" ]; then
    cat > "${DB_PROPS}" <<PROPS
#dataSource config
jdbc.username=${DB_USER}
jdbc.password=${DB_PASS}
jdbc.url=jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}?useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
PROPS
    echo "Created db.properties (installation marker)"
fi

# Insert admin user if not exists
user_count=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASS}" -N -s -e \
    "SELECT COUNT(*) FROM ${DB_NAME}.of_sys_user WHERE login_name='${ADMIN_USER}'" 2>/dev/null)
if [ "${user_count}" = "0" ]; then
    # Generate SHA-256 hash of password (same as Shiro's Sha256Hash)
    pass_hash=$(echo -n "${ADMIN_PASS}" | sha256sum | awk '{print $1}')
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e \
        "INSERT INTO of_sys_user (user_id, user_sex, user_email, login_name, user_name, user_password, status)
         VALUES (1, '1', 'admin@ofcms.com', '${ADMIN_USER}', 'Administrator', '${pass_hash}', '1');" 2>/dev/null
    echo "Admin user '${ADMIN_USER}' created"
else
    echo "Admin user '${ADMIN_USER}' already exists"
fi

echo "Starting Tomcat..."
exec "$@"
