# php7.4-apache can no longer be built from scratch (TG-4913, 2026-11-19): Debian bullseye is
# EOL and packages.sury.org has removed its bullseye Apache packages (the index is still
# there, the .deb files return 404), so the "install Apache from Sury" step of the previous
# Dockerfile fails. The previous Dockerfile is in git: `git show 2cd2b87:Dockerfile`.
#
# Until this tag moves to a supported base, each rebuild starts from the last image that
# was built from scratch (2026-11-14, TG-4866: PHP 7.4.33 + PHP2Shell backport, Apache
# 2.4.69, Drush 8.5.0), pinned by digest, and only rebuilds PHP itself. Apache, the system
# packages, the PECL extensions and every config file stay byte-for-byte the same.
FROM hellosanta/php4drupal@sha256:a88d5287197233bf47646670cbc91ddfee5c72ddd0582262b6e892622b79dd04

# 2026-11-19 PHP security release (TG-4913): the fixes Ondrej Sury backported to php7.4
# (1:7.4.33-37+debsuryorg13.1+php+1) for the timezone cache use-after-free
# (CVE-2026-129496), session, phar, SOAP and stream wrapper issues. See the header of the
# patch file for the list.
#
# Same rebuild as the PHP2Shell layer of the previous Dockerfile: configure options from
# php-config (minus --with-pear), /usr/src/php.tar.xz repacked from the patched tree.
# Differences forced by the missing Sury packages:
# - the Sury source list is set aside while the build dependencies are installed, so apt
#   only looks at archive.debian.org;
# - the build dependencies are removed by name afterwards and the build fails unless the
#   package list (names, versions, states) is exactly what it was before: no system
#   package may be upgraded or removed by this layer;
# - apache2-dev / libapr1-dev / libaprutil1-dev cannot be installed (they want Debian's
#   Apache and APR, the image has Sury's), so their files are unpacked for the build and
#   removed again. The from-scratch build compiled mod_php against the same Debian headers.
COPY patches/php-7.4-security-20261119.patch /usr/src/
RUN set -eux; \
	dpkg-query -W -f '${Package} ${Version} ${db:Status-Abbrev}\n' | sort > /tmp/pkgs.before; \
	apt-mark showauto | sort > /tmp/auto.before; \
	mv /etc/apt/sources.list.d/sury-apache.list /tmp/sury-apache.list; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS patch xz-utils \
		libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev \
		libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev \
		libexpat1-dev libldap2-dev libsctp-dev uuid-dev; \
	mkdir /tmp/apdev; cd /tmp/apdev; \
	apt-get download apache2-dev libapr1-dev libaprutil1-dev; \
	for deb in *.deb; do \
		dpkg-deb --fsys-tarfile "$deb" | tar -t | grep -v '/$' | sed 's#^\./#/#' >> /tmp/apdev.files; \
		dpkg-deb -x "$deb" /; \
	done; \
	export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
	docker-php-source extract; \
	cd /usr/src/php; \
	patch -p1 --forward --no-backup-if-mismatch < /usr/src/php-7.4-security-20261119.patch; \
	opts="$(php-config --configure-options | sed -e 's/ --with-pear//' -e 's/ build_alias=[^ ]*//')"; \
	eval "./configure $opts"; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find /usr/local/bin /usr/local/sbin -type f -perm -0111 -exec sh -c 'file -b "$1" | grep -q ELF && strip --strip-all "$1"' _ '{}' ';'; \
	make clean; \
	rm -f .docker-extracted; \
	cd /usr/src; \
	rm -f php.tar.xz php.tar.xz.asc php-7.4-security-20261119.patch; \
	tar -cJf php.tar.xz php; \
	docker-php-source delete; \
	xargs -d '\n' rm -f < /tmp/apdev.files; \
	rm -rf /tmp/apdev /tmp/apdev.files; \
	dpkg-query -W -f '${Package}\n' | sort > /tmp/names.after; \
	cut -d' ' -f1 /tmp/pkgs.before | comm -13 - /tmp/names.after | xargs -r apt-get purge -y; \
	apt-mark showauto | sort | comm -13 /tmp/auto.before - | xargs -r apt-mark manual > /dev/null; \
	apt-mark showauto | sort | comm -23 /tmp/auto.before - | xargs -r apt-mark auto > /dev/null; \
	dpkg-query -W -f '${Package} ${Version} ${db:Status-Abbrev}\n' | sort | diff /tmp/pkgs.before -; \
	mv /tmp/sury-apache.list /etc/apt/sources.list.d/sury-apache.list; \
	rm -rf /var/lib/apt/lists/* /tmp/pkgs.before /tmp/auto.before /tmp/names.after; \
	php --version; \
	php -r 'exit(PHP_VERSION === "7.4.33" ? 0 : 1);'; \
	grep -aq 'public key found, but the signature does not use openssl' /usr/lib/apache2/modules/libphp7.so; \
	apache2 -v | grep -q 'Apache/2.4.69'; \
	apache2ctl -t
