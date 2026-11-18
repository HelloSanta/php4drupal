FROM php:8.1-apache-trixie

# TG-4887：base 從 buster（Apache 2.4.38、已 EOL）換成官方 php:8.1-apache 現在的 base（Debian 13 trixie）。
# Apache 升到 trixie 安全來源的最新版（2.4.71-1~deb13u1 起）；不鎖版本，之後重建會跟著安全來源走。
RUN set -eux; \
	apt-get update; \
	apt-get install -y --only-upgrade --no-install-recommends \
		apache2 apache2-bin apache2-data apache2-utils libssl3t64 openssl; \
	rm -rf /var/lib/apt/lists/*; \
	dpkg --compare-versions "$(dpkg-query -W -f='${Version}' apache2-bin)" ge '2.4.71'; \
	apache2 -v

# PHP2Shell (CVE-2026-109618 / CVE-2026-109619, 2026-10-21, TG-245).
# The official php:8.1-apache image is the unpatched 8.1.34. This layer rebuilds
# PHP 8.1.34 plus the PHP security team's source backport
# (php-src branch PHP-8.1-CVE-2026-109618-109619).
# Configure options are the ones the official image was built with (php-config),
# minus --with-pear so the install does not download from pear.php.net (the image's
# existing pear/pecl stay). /usr/src/php.tar.xz is repacked from the patched tree,
# so extensions built later with docker-php-ext-install (opcache etc.) use it too.
COPY patches/php-8.1-CVE-2026-109618-109619.patch /usr/src/
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS patch xz-utils ca-certificates curl \
		apache2-dev libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev \
		libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev; \
	curl -fsSL -o /usr/src/php.tar.xz "https://www.php.net/distributions/php-8.1.34.tar.xz"; \
	echo "ffa9e0982e82eeaea848f57687b425ed173aa278fe563001310ae2638db5c251 *php.tar.xz" | (cd /usr/src && sha256sum -c -); \
	rm -f /usr/src/php.tar.xz.asc; \
	export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
	docker-php-source extract; \
	cd /usr/src/php; \
	patch -p1 --forward --no-backup-if-mismatch < /usr/src/php-8.1-CVE-2026-109618-109619.patch; \
	opts="$(php-config --configure-options | sed -e 's/ --with-pear//' -e 's/ build_alias=[^ ]*//')"; \
	eval "./configure $opts"; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find /usr/local/bin /usr/local/sbin -type f -perm -0111 -exec sh -c 'file -b "$1" | grep -q ELF && strip --strip-all "$1"' _ '{}' ';'; \
	make clean; \
	rm -f .docker-extracted; \
	cd /usr/src; \
	rm -f php.tar.xz php.tar.xz.asc php-8.1-CVE-2026-109618-109619.patch; \
	tar -cJf php.tar.xz php; \
	docker-php-source delete; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	find /usr/local -type f -executable -exec ldd '{}' ';' 2> /dev/null \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u | xargs -r dpkg-query --search | cut -d: -f1 | sort -u | xargs -r apt-mark manual > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	php --version; \
	php -r 'exit(PHP_VERSION === "8.1.34" ? 0 : 1);'

# mod_expires、mod_headers：Drupal 的 .htaccess 用它們給靜態檔加快取標頭，沒啟用的話瀏覽器每頁都重抓所有靜態檔。
RUN a2enmod expires headers

# install the PHP extensions we need
RUN set -eux; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
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
		libldap-dev \
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


# Install Memcached for php 8 (pinned; 3.4.0 is the latest pecl release, 2026-11)
RUN apt-get update && apt-get install -y libmemcached-dev zlib1g-dev \
		&& printf '/usr\n\n\n\n\n\n\n\n\n' | pecl install memcached-3.4.0 \
		&& docker-php-ext-enable memcached

# Install openssh && nano && supervisor && git && unzip
RUN apt-get update && apt-get install -y openssh-server nano supervisor git unzip

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync default-mysql-client

# trixie 的 default-mysql-client 是 MariaDB 11.8，預設要求 TLS；公司的 MySQL 沒有 TLS，
# drush sql-dump／備份會失敗。和 php8.3／8.4 分支一樣，四個指令都包 --ssl=0（TG-4887）。
RUN set -eux; \
	for bin in mysqldump mysql mariadb-dump mariadb; do \
		real="/usr/bin/${bin}.upstream"; \
		mv "/usr/bin/${bin}" "${real}"; \
		printf '#!/bin/sh\nexec %s "$@" --ssl=0\n' "${real}" > "/usr/bin/${bin}"; \
		chmod +x "/usr/bin/${bin}"; \
	done; \
	printf '[client]\nssl=0\n' > /etc/mysql/conf.d/disable-ssl.cnf

# Install Composer In order to use compose
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

# Install drush launcher
RUN php -r "readfile('https://github.com/drush-ops/drush-launcher/releases/latest/download/drush.phar');" > drush \
	&& chmod +x drush \
	&& mv drush /usr/local/bin/drush

# ADD Configuration to the Container
ADD conf/supervisord.conf /etc/supervisord.conf
ADD conf/apache2.conf /etc/apache2/apache2.conf
ADD conf/php.ini /usr/local/etc/php/

# Add Scripts
ADD scripts/start.sh /start.sh
RUN chmod 755 /start.sh


EXPOSE 443 80

CMD ["/start.sh"]
