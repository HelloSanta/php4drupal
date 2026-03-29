FROM php:7.4-apache-bullseye

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
	pecl install imagick && docker-php-ext-enable imagick; \
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
	echo 'opcache.memory_consumption=512'; \
	echo 'opcache.interned_strings_buffer=10'; \
	echo 'opcache.max_accelerated_files=10000'; \
	echo 'opcache.revalidate_freq=60'; \
	echo 'opcache.validate_timestamps=1'; \
	echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# 安裝 Memcached 支援
RUN apt-get update && apt-get install -y libmemcached-dev zlib1g-dev \
	&& pecl install memcached \
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
