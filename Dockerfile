FROM php:8.1-apache-buster

# Debian buster 已經 EOL，deb.debian.org／security.debian.org 不再提供它的套件
# （索引還在但套件檔 404，或整個 suite 已經下架），所以套件來源一律改指 archive.debian.org。
# archive 的 Release 檔已經過了 Valid-Until，要關掉期限檢查，apt-get update 才不會拒絕。
RUN set -eux; \
	sed -i \
		-e 's#http://deb.debian.org/#http://archive.debian.org/#' \
		-e 's#http://security.debian.org/#http://archive.debian.org/#' \
		/etc/apt/sources.list; \
	echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

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


# Install Memcached for php 8
RUN apt-get update && apt-get install -y libmemcached-dev zlib1g-dev \
		&& pecl install memcached-3.2.0 \
		&& docker-php-ext-enable memcached

# Install openssh && nano && supervisor && git && unzip
RUN apt-get update && apt-get install -y openssh-server nano supervisor git unzip

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync default-mysql-client

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
