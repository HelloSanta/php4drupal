FROM php:7.2-apache

MAINTAINER victor.yang@hellosanta.com.tw

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
		bcmath \
		soap \
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
RUN apt-get update && apt-get install -y openssh-server nano supervisor git && php -r "readfile('https://github.com/drush-ops/drush/releases/download/8.1.17/drush.phar');" > drush \
    && php drush core-status \
		&& chmod +x drush \
		&& mv drush /usr/local/bin \
		&& drush init -y

# Install mysql-clients && rsync. In order to sync database with the container
RUN apt-get install -y rsync default-mysql-client

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
