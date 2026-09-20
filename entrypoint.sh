#!/bin/bash
# Entry point for the Moodle 5.3 test container. Installs Moodle on first run,
# applies any pending upgrade, then serves it AND runs the cron loop in the
# background of the same container - so cron always runs the exact same code and
# database as the web server and can never drift out of sync.
# A copy of the generated config.php is kept in the persistent moodledata volume
# so recreating a container does not trigger a re-install. The live config.php
# must be a real file (not a symlink) in the web root: Moodle's config.php ends
# with require_once(__DIR__ . '/lib/setup.php'), and PHP resolves __DIR__ through
# a symlink to the volume, where there is no lib/ - so we copy, never link.
set -euo pipefail

MOODLE_DATA=/var/www/moodledata
PERSISTENT_CONFIG="${MOODLE_DATA}/config.php"
MOODLE_CONFIG=/var/www/html/config.php

# Write PHP settings from the environment - the sandbox's equivalent of the
# YunoHost config panel's "PHP & performance" section. Change these in .env and
# restart to apply.
cat > /usr/local/etc/php/conf.d/moodle.ini <<PHPINI
max_input_vars = ${PHP_MAX_INPUT_VARS:-5000}
memory_limit = ${PHP_MEMORY_LIMIT:-256M}
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-300}
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-1G}
post_max_size = ${PHP_UPLOAD_MAX_FILESIZE:-1G}
zend.exception_ignore_args = On
PHPINI

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

# Tracking a moving branch (e.g. main) means a rebuild can pull code newer than
# the database, leaving an upgrade pending. Apply it automatically on the web
# role so the site (and cron) come up ready. A no-op when nothing is pending.
if [ "${MOODLE_AUTO_UPGRADE:-true}" = "true" ]; then
    echo "Applying any pending Moodle upgrade ..."
    runuser -u www-data -- php /var/www/html/admin/cli/upgrade.php \
        --non-interactive --allow-unstable || \
        echo "Upgrade step reported an issue; starting anyway."
fi

# Run Moodle cron in the background of this same container, as www-data, every
# CRON_INTERVAL minutes. Because it shares this container's code and database,
# it stays in lock-step with the web server and the applied upgrade above -
# no separate container to drift out of sync. Output goes to the container log.
(
    while true; do
        # --keep-alive=0 makes cron run once and exit immediately, instead of
        # spinning for ~60s checking for adhoc tasks. That keeps a true
        # CRON_INTERVAL cadence (so Moodle's "run every 1 min" check is happy)
        # and keeps the container log quiet.
        runuser -u www-data -- php /var/www/html/admin/cli/cron.php --keep-alive=0 || true
        sleep "${CRON_INTERVAL:-15}m"
    done
) &
echo "Started Moodle cron loop (every ${CRON_INTERVAL:-15} min)."

exec "$@"
