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

# PHP settings Moodle expects (max_input_vars is the common gotcha).
RUN { \
        echo 'max_input_vars = 5000'; \
        echo 'memory_limit = 256M'; \
        echo 'upload_max_filesize = 100M'; \
        echo 'post_max_size = 100M'; \
    } > /usr/local/etc/php/conf.d/moodle.ini

# Pull the Moodle source for the chosen branch. MOODLE_503_STABLE is the 5.3
# branch; while 5.3 is still in QA the branch tracks the release candidate and
# upgrades cleanly to stable once it is tagged on 5 October 2026.
ARG MOODLE_BRANCH=MOODLE_503_STABLE
RUN rm -rf /var/www/html \
    && git clone --branch "${MOODLE_BRANCH}" --depth 1 \
        https://github.com/moodle/moodle.git /var/www/html \
    && chown -R www-data:www-data /var/www/html

RUN a2enmod rewrite

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
