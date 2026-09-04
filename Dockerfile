FROM php:8.3-apache-trixie

# Upgrade Apache to the newest packaged build available for Debian 13 (trixie),
# pulling apache2 from trixie-proposed-updates when it carries a higher version
# than trixie / trixie-security.
#
# CVE-2026-49975 (mod_http2 HTTP/2 Bomb) is already fixed in trixie-security's
# 2.4.67-1~deb13u3 via DSA-6323-1 — but that is a backport that keeps the
# 2.4.67 version string. Vulnerability scanners that match on version string
# alone still flag 2.4.67 and demand apache2 >= 2.4.68, so we ship the real
# 2.4.68-1~deb13u1 Debian build that is staged in trixie-proposed-updates for
# the next trixie point release.
#
# The proposed-updates source is added only for this layer and removed before
# the layer ends, so no later apt layer sees it. No exact version is pinned:
# apt picks the highest available apache2 (priority 500), so this keeps working
# once 2.4.68 reaches trixie proper, and falls back to security's build if
# proposed-updates ever lacks apache2.
RUN set -eux; \
	echo 'deb http://deb.debian.org/debian trixie-proposed-updates main' \
		> /etc/apt/sources.list.d/proposed-updates.list; \
	apt-get update; \
	apt-get install -y --only-upgrade --no-install-recommends \
		apache2 \
		apache2-bin \
		apache2-data \
		apache2-utils \
	; \
	rm -f /etc/apt/sources.list.d/proposed-updates.list; \
	rm -rf /var/lib/apt/lists/*

# Upgrade OpenSSL to the trixie-security build (3.5.7-1~deb13u2, DSA-6465-1:
# CVE-2026-18798 / CVE-2026-63072 / CVE-2026-63076). No version pin, so every
# rebuild keeps tracking the newest security build from the default sources.
RUN set -eux; \
	apt-get update; \
	apt-get install -y --only-upgrade --no-install-recommends \
		libssl3t64 \
		openssl \
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
		libxpm-dev \
		libpq-dev \
		libzip-dev \
		libsodium-dev \
		libldap2-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg=/usr \
		--with-webp=/usr \
		--with-xpm=/usr \
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
# pecl prompts on bookworm default `libmemcached directory` to `[no]` when
# stdin is closed, which makes configure abort. Feed `/usr` for that prompt
# and accept defaults (empty newlines) for the remaining 8 prompts:
# zlib, fastlz, igbinary, msgpack, json, protocol, sasl, sessions.
RUN apt-get update && apt-get install -y libmemcached-dev libssl-dev zlib1g-dev \
		&& printf '/usr\n\n\n\n\n\n\n\n\n' | pecl install memcached \
		&& docker-php-ext-enable memcached

# Install openssh && nano && supervisor && git && unzip
RUN apt-get update && apt-get install -y openssh-server nano supervisor git unzip

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync default-mysql-client

# Disable SSL by default for the bundled MariaDB client.
#
# Trixie's default-mysql-client is MariaDB 11.8+, whose mysql / mysqldump enable
# `--ssl-verify-server-cert` and TLS-PREFERRED by default. Every Hello Santa
# Drupal stack runs an internal MySQL / Percona server without an SSL listener,
# so the new default breaks `drush sql-dump`, `mysqldump` backups, and any CI
# `Backup Process` job with "TLS/SSL error: SSL is required, but the server
# does not support it".
#
# A simple `/etc/mysql/conf.d/disable-ssl.cnf` is NOT enough — drush invokes
# `mysqldump --defaults-file=/tmp/drush_XXX` which explicitly bypasses all
# system config files. The only universal fix is to wrap the binaries so the
# `--ssl=0` flag is appended unconditionally. Appended (not prepended) because
# `mariadb-dump` requires `--defaults-file` as the very first arg.
RUN set -eux; \
	for bin in mysqldump mysql; do \
		real="/usr/bin/${bin}.upstream"; \
		mv "/usr/bin/${bin}" "${real}"; \
		printf '#!/bin/sh\nexec %s "$@" --ssl=0\n' "${real}" > "/usr/bin/${bin}"; \
		chmod +x "/usr/bin/${bin}"; \
	done; \
	printf '[client]\nssl=0\n' > /etc/mysql/conf.d/disable-ssl.cnf

# Add a non-root user for apache server user
RUN useradd -ms /bin/bash myuser

# Install Composer In order to use compose
# CVE-2026-45793 fixed in Composer 2.9.8 (May 2026). Pinning to 2.9 minor
# auto-tracks security patches without risking 3.x major bumps.
COPY --from=composer:2.9 /usr/bin/composer /usr/local/bin/

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
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
