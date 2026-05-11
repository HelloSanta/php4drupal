FROM php:8.4-apache-trixie

# Upgrade Apache (and bundled libs) to the latest version available in the
# configured apt repositories at build time. Ensures every freshly built image
# picks up the newest security/bugfix release on top of the base image.
RUN set -eux; \
	apt-get update; \
	apt-get install -y --only-upgrade --no-install-recommends \
		apache2 \
		apache2-bin \
		apache2-data \
		apache2-utils \
	; \
	rm -rf /var/lib/apt/lists/*

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
	apt-get install -y --no-install-recommends \
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
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg=/usr \
		--with-webp=/usr \
		--with-xpm=/usr \
		--with-avif \
	; \
	\
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
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r readlink -f \
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


# Install Memcached for php 8.
# pecl prompts on trixie default `libmemcached directory` to `[no]` when stdin
# is closed, which makes configure abort. Feed `/usr` for that prompt and
# accept defaults (empty newlines) for the remaining 8 prompts: zlib, fastlz,
# igbinary, msgpack, json, protocol, sasl, sessions.
# libssl-dev is required because libmemcached.pc declares Requires: libcrypto
# and pkg-config breaks resolving libmemcached without it.
RUN apt-get update && apt-get install -y libmemcached-dev libssl-dev zlib1g-dev \
		&& printf '/usr\n\n\n\n\n\n\n\n\n' | pecl install memcached \
		&& docker-php-ext-enable memcached

# Install openssh && nano && supervisor && git && unzip
RUN apt-get update && apt-get install -y openssh-server nano supervisor git unzip

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync default-mysql-client

# Disable SSL by default for the bundled MariaDB client.
# Trixie's default-mysql-client is MariaDB 11.8+, whose mysql / mysqldump enable
# `--ssl-verify-server-cert` and TLS-PREFERRED by default. Every Hello Santa
# Drupal stack runs an internal MySQL / Percona server without an SSL listener,
# so the new default breaks `drush sql-dump`, `mysqldump` backups, and any CI
# `Backup Process` job with "TLS/SSL error: SSL is required, but the server
# does not support it". Drop a system-wide client config so all invocations
# start with ssl off; individual call sites can still re-enable per-invocation
# via `--ssl=1` if a future server gains TLS support.
RUN printf '[client]\nssl=0\n' > /etc/mysql/conf.d/disable-ssl.cnf

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