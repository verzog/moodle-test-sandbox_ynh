# Moodle 5.3 test image for local/experimental use only.
# Not part of the YunoHost package - see README.md in this folder.
FROM php:8.3-apache

# System libraries needed to build the PHP extensions Moodle requires.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        unzip \
        libpq-dev \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libicu-dev \
        libzip-dev \
        libxml2-dev \
        libldap2-dev \
        libonig-dev \
        libcurl4-openssl-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure ldap --with-libdir=lib/"$(uname -m)"-linux-gnu \
    && docker-php-ext-install -j"$(nproc)" \
        pgsql \
        pdo_pgsql \
        gd \
        intl \
        zip \
        soap \
        exif \
        opcache \
        ldap \
        mbstring \
        curl \
    && rm -rf /var/lib/apt/lists/*

# PHP settings (max_input_vars, memory_limit, upload sizes, execution time) are
# written at container start by entrypoint.sh from environment variables, so they
# can be tuned via .env without rebuilding the image.

# Pull the Moodle source for the chosen branch. While 5.3 is still in QA (stable
# is 5 October 2026) the code lives on Moodle's development branch "main"; switch
# this to MOODLE_503_STABLE once that branch is cut at release.
ARG MOODLE_BRANCH=main
# Set an explicit working directory before cloning. The legacy Docker build
# engine (used when the buildx plugin is absent) leaves a RUN step with no valid
# working directory, and git then aborts with "Unable to read current working
# directory". Sitting in an existing directory avoids that.
WORKDIR /var/www
RUN rm -rf /var/www/html \
    && git clone --branch "${MOODLE_BRANCH}" --depth 1 \
        https://github.com/moodle/moodle.git /var/www/html \
    && chown -R www-data:www-data /var/www/html

RUN a2enmod rewrite

# Moodle 5.1+ serves from the public/ subdirectory so the non-public code at the
# project root (and config.php) is not web-reachable. Point Apache's document
# root there; config.php stays at the project root, where the installer writes it
# and where public/config.php's stub loads it from.
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Install Composer and Moodle's runtime PHP dependencies. A git checkout (unlike
# a release ZIP) ships without the vendor/ directory, so the admin health check
# reports "Composer installed data not found" until these are installed.
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');" \
    && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
    && rm -f /tmp/composer-setup.php \
    && cd /var/www/html \
    && composer install --no-dev --no-interaction --no-progress --no-scripts \
    && chown -R www-data:www-data /var/www/html/vendor

# Configure Moodle's router (Moodle 5.1+): requests that don't resolve to a real
# file or directory (and aren't a *.php script) are sent to the router entry
# script r.php. Traditional *.php URLs and static files are served directly.
RUN printf '%s\n' \
        '<Directory /var/www/html/public>' \
        '    RewriteEngine On' \
        '    # Return a real 404 for internal paths that must not be web-served' \
        '    # (Moodle security "public/private paths" check). This runs before' \
        '    # the router catch-all so these never resolve to a 200 via r.php.' \
        '    RewriteRule "(^|/)(\.git|\.github|behat|node_modules|vendor)(/|$)" - [R=404,L]' \
        '    # Route clean URLs (not real files or *.php scripts) to the router.' \
        '    RewriteCond %{REQUEST_FILENAME} !-f' \
        '    RewriteCond %{REQUEST_FILENAME} !-d' \
        '    RewriteCond %{REQUEST_URI} !\.php(/|$)' \
        '    RewriteRule ^ r.php [QSA,L]' \
        '</Directory>' \
    > /etc/apache2/conf-available/moodle-router.conf \
    && a2enconf moodle-router

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
