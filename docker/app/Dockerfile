FROM alpine:latest

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

RUN \
	apk update \
	&& apk upgrade \
	&& apk add \
		bash vim less curl git supervisor \
		nginx npm nodejs mysql-client gnu-libiconv \
		php8 php8-fpm php8-phar php8-fileinfo php8-tokenizer php8-dom \
		php8-simplexml php8-xml php8-xmlreader php8-xmlwriter php8-pdo_mysql \
		php8-mbstring php8-opcache php8-iconv php8-intl php8-gd php8-session \
		php8-pecl-redis \
	&& ln -s /usr/bin/php8 /usr/local/bin/php \
	&& rm -f /etc/nginx/conf.d/*

RUN \
	curl --location --output /usr/local/bin/phpunit \
		"https://phar.phpunit.de/phpunit.pha↪\r" \
	&& chmod +x /usr/local/bin/phpunit \
	&& curl --location --output /tmp/composer-setup.php \
		"https://getcomposer.org/installer" \
	&& php /tmp/composer-setup.php \
		--install-dir=/usr/local/bin --filename=composer --quiet \
	&& rm /tmp/composer-setup.php

RUN \
	mv /etc/profile.d/color_prompt /etc/profile.d/color_prompt.sh \
	&& echo laser > /etc/hostname \
	&& addgroup laser \
	&& adduser -D -s /bin/bash -h /var/www -G laser laser \
	&& passwd -d laser laser

COPY php.ini          /etc/php8/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 80

ENTRYPOINT ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
