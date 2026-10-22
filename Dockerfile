FROM php:7.4-apache-bullseye

# Debian bullseye 已經 EOL，deb.debian.org／security.debian.org 不再提供它的套件
# （索引還在但套件檔 404，或整個 suite 已經下架），所以套件來源一律改指 archive.debian.org。
# archive 的 Release 檔已經過了 Valid-Until，要關掉期限檢查，apt-get update 才不會拒絕。
RUN set -eux; \
	sed -i \
		-e 's#http://deb.debian.org/#http://archive.debian.org/#' \
		-e 's#http://security.debian.org/#http://archive.debian.org/#' \
		/etc/apt/sources.list; \
	echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

# PHP2Shell (CVE-2026-109618 / CVE-2026-109619, 2026-10-21, TG-245).
# The official php:7.4 image is no longer updated. The PHP security team published
# a source backport (php-src branch PHP-7.4-CVE-2026-109618-109619); this layer applies it
# to the 7.4.33 source and rebuilds PHP.
# Configure options are the ones the official image was built with (php-config),
# minus --with-pear so the install does not download from pear.php.net (the image's
# existing pear/pecl stay). /usr/src/php.tar.xz is repacked from the patched tree,
# so extensions built later with docker-php-ext-install (opcache etc.) use it too.
COPY patches/php-7.4-CVE-2026-109618-109619.patch /usr/src/
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS patch xz-utils ca-certificates curl \
		apache2-dev libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev \
		libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev; \
	export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
	docker-php-source extract; \
	cd /usr/src/php; \
	patch -p1 --forward --no-backup-if-mismatch < /usr/src/php-7.4-CVE-2026-109618-109619.patch; \
	opts="$(php-config --configure-options | sed -e 's/ --with-pear//' -e 's/ build_alias=[^ ]*//')"; \
	eval "./configure $opts"; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find /usr/local/bin /usr/local/sbin -type f -perm -0111 -exec sh -c 'file -b "$1" | grep -q ELF && strip --strip-all "$1"' _ '{}' ';'; \
	make clean; \
	rm -f .docker-extracted; \
	cd /usr/src; \
	rm -f php.tar.xz php.tar.xz.asc php-7.4-CVE-2026-109618-109619.patch; \
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
	php -r 'exit(PHP_VERSION === "7.4.33" ? 0 : 1);'

# mod_expires、mod_headers：Drupal 的 .htaccess 用它們給靜態檔加快取標頭，沒啟用的話瀏覽器每頁都重抓所有靜態檔。
RUN a2enmod expires headers

# 安裝 Sury 的 Apache 最新版本來源，解決 CVE-2024-38475/38476
RUN apt-get update && apt-get install -y apt-transport-https curl lsb-release ca-certificates gnupg && \
	curl -fsSL https://packages.sury.org/apache2/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-archive-keyring.gpg && \
	echo "deb [signed-by=/usr/share/keyrings/sury-archive-keyring.gpg] https://packages.sury.org/apache2 $(lsb_release -cs) main" > /etc/apt/sources.list.d/sury-apache.list

# 確保 Apache 最新版已安裝
RUN apt-get update && apt-get install -y apache2 && apache2 -v

# 啟用 rewrite 模組
RUN a2enmod rewrite

# 安裝 PHP 所需延伸模組
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
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
	libmagickwand-dev \
	; \
	docker-php-ext-configure gd \
	--with-freetype \
	--with-jpeg=/usr \
	--with-webp=/usr \
	--with-xpm=/usr \
	; \
	docker-php-ext-install -j"$(nproc)" \
	gd \
	opcache \
	pdo_mysql \
	pdo_pgsql \
	zip \
	bcmath \
	; \
	pecl install imagick-3.8.0 && docker-php-ext-enable imagick; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
	| awk '/=>/ { print $3 }' \
	| sort -u \
	| xargs -r dpkg-query -S \
	| cut -d: -f1 \
	| sort -u \
	| xargs -rt apt-mark manual; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# PHP 設定：啟用 opcache
RUN { \
	echo 'opcache.memory_consumption=128'; \
	echo 'opcache.interned_strings_buffer=8'; \
	echo 'opcache.max_accelerated_files=4000'; \
	echo 'opcache.revalidate_freq=60'; \
	echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# 安裝 Memcached 支援
RUN apt-get update && apt-get install -y libmemcached-dev zlib1g-dev \
	&& pecl install memcached-3.3.0 \
	&& docker-php-ext-enable memcached \
	&& rm -rf /var/lib/apt/lists/*

# 安裝 ssh, nano, supervisor, drush, git
RUN apt-get update && apt-get install -y openssh-server nano supervisor git \
	&& php -r "readfile('https://github.com/drush-ops/drush/releases/download/8.4.8/drush.phar');" > drush \
	&& chmod +x drush \
	&& mv drush /usr/local/bin/drush \
	&& drush init -y \
	&& rm -rf /var/lib/apt/lists/*

# 安裝 rsync 與 MySQL client
RUN apt-get update && apt-get install -y rsync default-mysql-client \
	&& rm -rf /var/lib/apt/lists/*

# 安裝 Composer
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

# 複製自訂設定檔與腳本
ADD conf/supervisord.conf /etc/supervisord.conf
ADD conf/apache2.conf /etc/apache2/apache2.conf
ADD conf/php.ini /usr/local/etc/php/
ADD scripts/start.sh /start.sh
RUN chmod 755 /start.sh

EXPOSE 80 443

CMD ["/start.sh"]
