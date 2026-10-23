FROM php:5.6-apache

# stretch 自己的簽章金鑰已經過期（apt 回 EXPKEYSIG）。archive.debian.org 上 stretch 的 Release
# 另外有新一代的金鑰簽名，把對應的公鑰放進來就能驗證：
# - stretch：Debian Archive Automatic Signing Key (11/bullseye)
#   1F89983E0081FDE018F3CC9673A4F27B8DD47936，2029-01-15 到期
# - stretch/updates：Debian Security Archive Automatic Signing Key (10/buster)
#   5E61B217265DA9807A23C5FF4DFAB270CAA96DFA，2027-04-12 到期，到期後 stretch 就又建不起來
# 兩把都取自 debian-archive-keyring 2023.3+deb12u2（後者在 debian-archive-removed-keys.gpg）。
ADD conf/apt-keys/ /etc/apt/trusted.gpg.d/

# Debian stretch 已經 EOL，deb.debian.org／security.debian.org 不再提供它的套件
# （索引還在但套件檔 404，或整個 suite 已經下架），所以套件來源一律改指 archive.debian.org。
# archive 的 Release 檔已經過了 Valid-Until，要關掉期限檢查，apt-get update 才不會拒絕。
RUN set -eux; \
	sed -i \
		-e 's#http://deb.debian.org/#http://archive.debian.org/#' \
		-e 's#http://security.debian.org/#http://archive.debian.org/#' \
		/etc/apt/sources.list; \
	sed -i '/stretch-updates/d' /etc/apt/sources.list; \
	echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

# PHP2Shell (CVE-2026-109618 / CVE-2026-109619, 2026-10-21, TG-245).
# PHP 5.6 is EOL and php-src has no official backport for it. The patch is the one
# Ondřej Surý ships in php5.6 (packages.sury.org, "Avoid state corruption via bailout",
# Arnaud Le Blanc's minimal mitigation for EOL versions); it applies cleanly to the
# official 5.6.40 source. The 7.4 patch also adds the max_multipart_body_parts
# limit; for 5.6 Sury ships that as the CVE-2023-0662 backport, so its two patches
# ("Fix repeated warning for file uploads limit exceeding", "Introduce
# max_multipart_body_parts INI") follow in the same file.
# Same rebuild as the 7.4 / 8.1 branches: configure options
# from php-config (minus --with-pear and the trailing build_alias/CFLAGS part), and
# /usr/src/php.tar.xz is repacked so later docker-php-ext-install builds use it too.
COPY patches/php-5.6-CVE-2026-109618-109619.patch /usr/src/
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS patch xz-utils apache2-dev libcurl4-openssl-dev libedit-dev libssl1.0-dev libxml2-dev zlib1g-dev; \
	export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
	docker-php-source extract; \
	cd /usr/src/php; \
	patch -p1 --forward --no-backup-if-mismatch < /usr/src/php-5.6-CVE-2026-109618-109619.patch; \
	opts="$(php-config --configure-options | sed -e 's/ --with-pear//' -e 's/ build_alias=.*//')"; \
	eval "./configure $opts"; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find /usr/local/bin /usr/local/sbin -type f -perm -0111 -exec sh -c 'file -b "$1" | grep -q ELF && strip --strip-all "$1"' _ '{}' ';'; \
	make clean; \
	rm -f .docker-extracted; \
	cd /usr/src; \
	rm -f php.tar.xz php.tar.xz.asc php-5.6-CVE-2026-109618-109619.patch; \
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
	php -r 'exit(PHP_VERSION === "5.6.40" ? 0 : 1);'

# mod_expires、mod_headers：Drupal 的 .htaccess 用它們給靜態檔加快取標頭，沒啟用的話瀏覽器每頁都重抓所有靜態檔。
RUN a2enmod expires headers

# install the PHP extensions we need
RUN set -ex; \
	\
	if command -v a2enmod; then \
	a2enmod rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
	libjpeg-dev \
	libpng-dev \
	libpq-dev \
	libfreetype6-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr --with-freetype-dir=/usr/include/; \
	docker-php-ext-install -j "$(nproc)" \
	gd \
	opcache \
	pdo_mysql \
	pdo_pgsql \
	zip \
	exif \
	mysqli \
	mysql \
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

# Install Memcached for php 5.6
RUN apt-get update && apt-get install -y libmemcached-dev zlib1g-dev \
		&& pecl install memcached-2.2.0 \
		&& docker-php-ext-enable memcached

# Install php-imagick
RUN apt-get update && apt-get install -y \
    libmagickwand-dev --no-install-recommends \
    	&& pecl install imagick-3.7.0 \
		&& docker-php-ext-enable imagick

# Install openssh && nano && supervisor && drush && git
RUN apt-get update && apt-get install -y openssh-server nano supervisor git && php -r "readfile('https://github.com/drush-ops/drush/releases/download/8.1.16/drush.phar');" > drush \
	&& php drush core-status \
	&& chmod +x drush \
	&& mv drush /usr/local/bin \
	&& drush init -y

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync mysql-client mysql-server

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
