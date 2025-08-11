FROM php:8.4-apache-bookworm

# install the PHP extensions we need
RUN set -eux; \
    \
    if command -v a2enmod; then \
        a2enmod rewrite; \
        a2enmod headers; \
        a2enmod expires; \
    fi; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    # Install build dependencies for standard extensions
    apt-get install -y --no-install-recommends \
        pkg-config \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libjpeg-dev \
        libpng-dev \
        libwebp-dev \
        libavif-dev \
        libxpm-dev \
        libpq-dev \
        libzip-dev \
        libsodium-dev \
        libldap2-dev \
        libxml2-dev \
    ; \
    \
    # Configure and install standard extensions
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg=/usr \
        --with-webp=/usr \
        --with-xpm=/usr \
        --with-avif \
    ; \
    docker-php-ext-install -j "$(nproc)" \
        gd \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        zip \
        bcmath \
        exif \
        sodium \
        ldap \
        soap \
    ; \
    \
    # Now, clean up the build dependencies for the extensions above
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=60'; \
    echo 'opcache.fast_shutdown=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Enable output_buffering
RUN echo 'output_buffering=4096' > /usr/local/etc/php/conf.d/output_buffering.ini

# Install Memcached in a self-contained block
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        pkg-config \
        libmemcached-dev \
        zlib1g-dev \
    ; \
    pecl install memcached; \
    docker-php-ext-enable memcached; \
    # Clean up the dependencies for this block specifically
    apt-get purge -y --auto-remove pkg-config libmemcached-dev zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*

# Install openssh && nano && supervisor && git && unzip
RUN apt-get update && apt-get install -y openssh-server nano supervisor git unzip

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync default-mysql-client

# Add a non-root user for apache server user
RUN useradd -ms /bin/bash myuser

# Install Composer In order to use compose
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

# Set the PATH to include ./vendor/bin
ENV PATH="./vendor/bin:${PATH}"

# ADD Configuration to the Container
ADD conf/supervisord.conf /etc/supervisord.conf
ADD conf/apache2.conf /etc/apache2/apache2.conf
ADD conf/php.ini /usr/local/etc/php/

# Add Scripts
ADD scripts/start.sh /start.sh
RUN chmod 755 /start.sh

EXPOSE 443 80

CMD ["/start.sh"]
