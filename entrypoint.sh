#!/bin/bash
# Entry point for the Moodle 5.3 test container. Waits for PostgreSQL, then
# installs Moodle on first run. A copy of the generated config.php is kept in the
# persistent moodledata volume so recreating the container does not trigger a
# re-install against an already-populated database. The live config.php must be a
# real file (not a symlink) inside the web root: Moodle's config.php ends with
# require_once(__DIR__ . '/lib/setup.php'), and PHP resolves __DIR__ through a
# symlink to the volume, where there is no lib/ - so we copy, never link.
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

# Clear any stale symlink left by older versions of this script.
[ -L "${MOODLE_CONFIG}" ] && rm -f "${MOODLE_CONFIG}"

if [ -f "${PERSISTENT_CONFIG}" ]; then
    # Already installed - reuse the saved configuration as a real file.
    cp "${PERSISTENT_CONFIG}" "${MOODLE_CONFIG}"
    chown www-data:www-data "${MOODLE_CONFIG}"
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
    # Keep a copy in the persistent volume for future container recreations.
    cp "${MOODLE_CONFIG}" "${PERSISTENT_CONFIG}"
    chown www-data:www-data "${MOODLE_CONFIG}" "${PERSISTENT_CONFIG}"
    echo "Moodle installed. Log in as 'admin' with the password from MOODLE_ADMIN_PASS."
fi

# When Moodle sits behind an HTTPS-terminating reverse proxy (e.g. YunoHost's
# nginx), the container still speaks plain HTTP, so Moodle must be told the
# outside world is HTTPS or it redirect-loops. Set sslproxy once on the live
# config, then mirror it to the persistent copy.
if [ "${MOODLE_SSLPROXY:-false}" = "true" ] && ! grep -q 'sslproxy' "${MOODLE_CONFIG}"; then
    sed -i "/require_once/i \$CFG->sslproxy = true;" "${MOODLE_CONFIG}"
    cp "${MOODLE_CONFIG}" "${PERSISTENT_CONFIG}"
    echo "Enabled sslproxy for HTTPS reverse-proxy operation."
fi

# The image configures Apache to route clean URLs through Moodle's r.php, so
# tell Moodle the router is configured (Moodle 5.1+ admin health check).
if [ "${MOODLE_ROUTER:-true}" = "true" ] && ! grep -q 'routerconfigured' "${MOODLE_CONFIG}"; then
    sed -i "/require_once/i \$CFG->routerconfigured = true;" "${MOODLE_CONFIG}"
    cp "${MOODLE_CONFIG}" "${PERSISTENT_CONFIG}"
    echo "Marked Moodle router as configured."
fi

exec "$@"
