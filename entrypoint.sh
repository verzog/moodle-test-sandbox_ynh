#!/bin/bash
# Entry point for the Moodle 5.3 test container. Waits for PostgreSQL, then
# installs Moodle on first run. The generated config.php is kept in the
# persistent moodledata volume and symlinked back in, so recreating the
# container does not trigger a re-install against an already-populated database.
set -euo pipefail

MOODLE_DATA=/var/www/moodledata
PERSISTENT_CONFIG="${MOODLE_DATA}/config.php"
MOODLE_CONFIG=/var/www/html/config.php

mkdir -p "${MOODLE_DATA}"
chown -R www-data:www-data "${MOODLE_DATA}"

# Wait until PostgreSQL is accepting connections.
echo "Waiting for PostgreSQL at ${DB_HOST}:5432 ..."
until php -r "exit(@pg_connect('host=${DB_HOST} port=5432 dbname=${DB_NAME} user=${DB_USER} password=${DB_PASS}') ? 0 : 1);" 2>/dev/null; do
    sleep 2
done
echo "PostgreSQL is up."

if [ -f "${PERSISTENT_CONFIG}" ]; then
    # Already installed - reuse the saved configuration.
    ln -sf "${PERSISTENT_CONFIG}" "${MOODLE_CONFIG}"
    echo "Existing Moodle configuration found; skipping install."
else
    echo "Installing Moodle ..."
    php /var/www/html/admin/cli/install.php \
        --wwwroot="${MOODLE_WWWROOT}" \
        --dataroot="${MOODLE_DATA}" \
        --dbtype=pgsql \
        --dbhost="${DB_HOST}" \
        --dbname="${DB_NAME}" \
        --dbuser="${DB_USER}" \
        --dbpass="${DB_PASS}" \
        --fullname="Moodle 5.3 Test" \
        --shortname="moodle53" \
        --adminuser=admin \
        --adminpass="${MOODLE_ADMIN_PASS}" \
        --adminemail="admin@example.com" \
        --non-interactive \
        --agree-license \
        --allow-unstable
    # Move the freshly written config.php into the persistent volume and link it.
    mv "${MOODLE_CONFIG}" "${PERSISTENT_CONFIG}"
    ln -sf "${PERSISTENT_CONFIG}" "${MOODLE_CONFIG}"
    chown -h www-data:www-data "${MOODLE_CONFIG}"
    chown www-data:www-data "${PERSISTENT_CONFIG}"
    echo "Moodle installed. Log in as 'admin' with the password from MOODLE_ADMIN_PASS."
fi

# When Moodle sits behind an HTTPS-terminating reverse proxy (e.g. YunoHost's
# nginx), the container still speaks plain HTTP, so Moodle must be told the
# outside world is HTTPS or it redirect-loops. Set sslproxy once, idempotently.
if [ "${MOODLE_SSLPROXY:-false}" = "true" ] && ! grep -q 'sslproxy' "${PERSISTENT_CONFIG}"; then
    sed -i "/require_once/i \$CFG->sslproxy = true;" "${PERSISTENT_CONFIG}"
    echo "Enabled sslproxy for HTTPS reverse-proxy operation."
fi

exec "$@"
