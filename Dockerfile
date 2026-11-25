# php7.4-apache on Debian 13 (trixie), TG-4913.
#
# Why: the previous base (official php:7.4-apache-bullseye, frozen since 2022-11) can no
# longer be rebuilt: bullseye is EOL and packages.sury.org removed its bullseye Apache
# packages. There is no official php:7.4 image for trixie, so this image takes the
# official php:8.1-apache-trixie image for its Apache and docker-php tooling
# (docker-php-ext-*, docker-php-source, same /usr/local layout as before), removes
# PHP 8.1 and builds PHP 7.4.33 in its place.
#
# PHP source: the official php-7.4.33 tarball plus the patches Ondrej Sury ships in his
# php7.4 package for trixie (1:7.4.33-37+debsuryorg13.1+php+1, packages.sury.org/php):
# every security fix backported since 7.4 went EOL (including PHP2Shell,
# CVE-2026-109618 / CVE-2026-109619, and the 2026-11-19 batch: CVE-2026-129496
# timezone cache use-after-free, session, phar, SOAP, stream wrappers) and the fixes
# needed to build against trixie's libraries (OpenSSL 3, libxml2, ICU, GCC 14).
# The original debian.tar.xz is in patches/. Patches 0001-0046 are Debian packaging
# changes (paths, session.save_path default, system time zone database, phpinfo
# credits) and are not applied, so PHP behaves like the docker-php build it replaces.
FROM php:8.1-apache-trixie

ENV PHP_VERSION=7.4.33

# All base packages (Apache, glibc, nghttp2, OpenSSL…) upgraded to trixie's security archive: the official
# php:8.1-apache base is EOL and no longer rebuilt (TG-4953). Apache 2.4.71-1~deb13u1 or later, not pinned.
RUN set -eux; \
	apt-get update; \
	DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends; \
	rm -rf /var/lib/apt/lists/*; \
	dpkg --compare-versions "$(dpkg-query -W -f='${Version}' apache2-bin)" ge '2.4.71'; \
	apache2 -v

# Replace PHP 8.1 with PHP 7.4.33 + Sury's patches. Configure options are the ones the
# official php:7.4-apache image was built with (php-config --configure-options of the
# previous image), minus --with-pear: pear/pecl stay as installed in the base image.
COPY ["patches/php7.4_7.4.33-37+debsuryorg13.1+php+1.debian.tar.xz", "/usr/src/sury-debian.tar.xz"]
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS patch xz-utils ca-certificates curl \
		apache2-dev libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev \
		libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev; \
	a2dismod -f php; \
	rm -f /usr/lib/apache2/modules/libphp.so /etc/apache2/mods-available/php.load; \
	rm -rf /usr/local/lib/php/extensions /usr/local/lib/php/build /usr/local/include/php; \
	rm -f /usr/local/bin/php /usr/local/bin/php-config /usr/local/bin/phpize /usr/local/bin/phpdbg \
		/usr/local/bin/phar /usr/local/bin/phar.phar /usr/local/etc/php/conf.d/*; \
	curl -fsSL -o /usr/src/php.tar.xz "https://www.php.net/distributions/php-7.4.33.tar.xz"; \
	echo "924846abf93bc613815c55dd3f5809377813ac62a9ec4eb3778675b82a27b927 */usr/src/php.tar.xz" | sha256sum -c -; \
	echo "73e1cdc96d71cd2791fbf9540f4e241cfd3803a6e17259e870ac146086281b04 */usr/src/sury-debian.tar.xz" | sha256sum -c -; \
	rm -f /usr/src/php.tar.xz.asc; \
	export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
	docker-php-source extract; \
	cd /usr/src/php; \
	tar -xJf /usr/src/sury-debian.tar.xz -C /usr/src debian/patches; \
	n=0; \
	for p in $(cat /usr/src/debian/patches/series); do \
		num="${p%%-*}"; \
		[ "$num" -ge 47 ] || continue; \
# 0196 only touches ext/enchant (not built) and needs the skipped 0039
		[ "$num" != 0196 ] || continue; \
		patch -p1 --forward --no-backup-if-mismatch < "/usr/src/debian/patches/$p" || echo "patch $p reported rejects"; \
		n=$((n+1)); \
	done; \
# NEWS is the only file allowed to have rejects (its entries depend on the skipped patches)
	test -z "$(find . -name '*.rej' ! -name 'NEWS.rej')"; \
	find . -name '*.rej' -delete; \
	test "$n" -eq 175; \
	./buildconf --force; \
	./configure --build=x86_64-linux-gnu --with-config-file-path=/usr/local/etc/php \
		--with-config-file-scan-dir=/usr/local/etc/php/conf.d --enable-option-checking=fatal \
		--with-mhash --with-pic --enable-ftp --enable-mbstring --enable-mysqlnd \
		--with-password-argon2 --with-sodium=shared --with-pdo-sqlite=/usr --with-sqlite3=/usr \
		--with-curl --with-iconv --with-openssl --with-readline --with-zlib --disable-phpdbg \
		--with-libdir=lib/x86_64-linux-gnu --disable-cgi --with-apxs2; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find /usr/local/bin /usr/local/sbin -type f -perm -0111 -exec sh -c 'file -b "$1" | grep -q ELF && strip --strip-all "$1"' _ '{}' ';'; \
	make clean; \
	rm -f .docker-extracted; \
	cd /usr/src; \
	rm -rf php.tar.xz php.tar.xz.asc sury-debian.tar.xz debian; \
	tar -cJf php.tar.xz php; \
	docker-php-source delete; \
	docker-php-ext-enable sodium; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	find /usr/local -type f -executable -exec ldd '{}' ';' 2> /dev/null \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u | xargs -r dpkg-query --search | awk -F: '!/^diversion / {print $1}' | sort -u | xargs -r apt-mark manual > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	php --version; \
	php -r 'exit(PHP_VERSION === "7.4.33" ? 0 : 1);'; \
	grep -aq 'public key found, but the signature does not use openssl' /usr/lib/apache2/modules/libphp7.so; \
	test -e /etc/apache2/mods-enabled/php7.load

# mod_expires、mod_headers：Drupal 的 .htaccess 用它們給靜態檔加快取標頭，沒啟用的話瀏覽器每頁都重抓所有靜態檔。
RUN a2enmod expires headers

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
	pecl install imagick-3.8.1 && docker-php-ext-enable imagick; \
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
	&& pecl install memcached-3.4.0 \
	&& docker-php-ext-enable memcached \
	&& rm -rf /var/lib/apt/lists/*

# 安裝 ssh, nano, supervisor, drush, git
RUN apt-get update && apt-get install -y openssh-server nano supervisor git \
	&& php -r "readfile('https://github.com/drush-ops/drush/releases/download/8.5.0/drush.phar');" > drush \
	&& chmod +x drush \
	&& mv drush /usr/local/bin/drush \
	&& drush init -y \
	&& rm -rf /var/lib/apt/lists/*

# 安裝 rsync 與 MySQL client
RUN apt-get update && apt-get install -y rsync default-mysql-client \
	&& rm -rf /var/lib/apt/lists/*

# trixie 的 default-mysql-client 是 MariaDB 11.8，預設要求 TLS；公司的 MySQL 沒有 TLS，
# drush sql-dump／備份會失敗。和 php8.1／8.3／8.4 分支一樣，四個指令都包 --ssl=0。
RUN set -eux; \
	for bin in mysqldump mysql mariadb-dump mariadb; do \
		real="/usr/bin/${bin}.upstream"; \
		mv "/usr/bin/${bin}" "${real}"; \
		printf '#!/bin/sh\nexec %s "$@" --ssl=0\n' "${real}" > "/usr/bin/${bin}"; \
		chmod +x "/usr/bin/${bin}"; \
	done; \
	printf '[client]\nssl=0\n' > /etc/mysql/conf.d/disable-ssl.cnf

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
