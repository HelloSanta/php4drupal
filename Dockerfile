FROM php:7.1-apache

# Debian buster 已經 EOL，deb.debian.org／security.debian.org 不再提供它的套件
# （索引還在但套件檔 404，或整個 suite 已經下架），所以套件來源一律改指 archive.debian.org。
# archive 的 Release 檔已經過了 Valid-Until，要關掉期限檢查，apt-get update 才不會拒絕。
RUN set -eux; \
	sed -i \
		-e 's#http://deb.debian.org/#http://archive.debian.org/#' \
		-e 's#http://security.debian.org/#http://archive.debian.org/#' \
		/etc/apt/sources.list; \
	echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

# PHP2Shell (CVE-2026-109618 / CVE-2026-109619, 2026-10-21, TG-245).
# PHP 7.1 is EOL and php-src has no official backport for it. The patch is the one
# Ondřej Surý ships in php7.1 (packages.sury.org, "Avoid state corruption via bailout",
# Arnaud Le Blanc's minimal mitigation for EOL versions); it applies cleanly to the
# official 7.1.33 source. The file starts with Sury's "backport ZSTR_MAX_LEN"
# (Remi Collet's cherry-pick from upstream), which the CVE patch needs.
# Same rebuild as the 7.4 / 8.1 branches: configure options
# from php-config (minus --with-pear and the trailing build_alias/CFLAGS part), and
# /usr/src/php.tar.xz is repacked so later docker-php-ext-install builds use it too.
COPY patches/php-7.1-CVE-2026-109618-109619.patch /usr/src/
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS patch xz-utils apache2-dev libcurl4-openssl-dev libedit-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev; \
	export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
	docker-php-source extract; \
	cd /usr/src/php; \
	patch -p1 --forward --no-backup-if-mismatch < /usr/src/php-7.1-CVE-2026-109618-109619.patch; \
	opts="$(php-config --configure-options | sed -e 's/ --with-pear//' -e 's/ build_alias=.*//')"; \
	eval "./configure $opts"; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find /usr/local/bin /usr/local/sbin -type f -perm -0111 -exec sh -c 'file -b "$1" | grep -q ELF && strip --strip-all "$1"' _ '{}' ';'; \
	make clean; \
	rm -f .docker-extracted; \
	cd /usr/src; \
	rm -f php.tar.xz php.tar.xz.asc php-7.1-CVE-2026-109618-109619.patch; \
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
	php -r 'exit(PHP_VERSION === "7.1.33" ? 0 : 1);'

# mod_expires、mod_headers：Drupal 的 .htaccess 用它們給靜態檔加快取標頭，沒啟用的話瀏覽器每頁都重抓所有靜態檔。
RUN a2enmod expires headers

# install the PHP extensions we need
RUN set -ex; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite headers; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libjpeg-dev \
		libpng-dev \
		libpq-dev \
		libbz2-dev \
		libxml2-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install -j "$(nproc)" \
		gd \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		zip \
		exif \
		bz2 \
		soap \
		bcmath \
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

# Install Memcached for php 7
RUN apt-get update && apt-get install -y libmemcached-dev zlib1g-dev \
		&& pecl install memcached-3.0.3 \
		&& docker-php-ext-enable memcached

# Install openssh && nano && supervisor && drush && git
RUN apt-get update && apt-get install -y openssh-server nano supervisor git && php -r "readfile('https://github.com/drush-ops/drush/releases/download/8.4.5/drush.phar');" > drush \
    && php drush core-status \
		&& chmod +x drush \
		&& mv drush /usr/local/bin \
		&& drush init -y

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync mariadb-client

# Install Composer In order to use compose
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# ADD Configuration to the Container
ADD conf/supervisord.conf /etc/supervisord.conf
ADD conf/apache2.conf /etc/apache2/apache2.conf
ADD conf/php.ini /usr/local/etc/php/

# Add Scripts
ADD scripts/start.sh /start.sh
RUN chmod 755 /start.sh


EXPOSE 443 80

CMD ["/start.sh"]
