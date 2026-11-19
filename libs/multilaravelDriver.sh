#!/bin/bash

function multilaravel::identify() {
	echo "no"
}

function multilaravel::https_vhost() {
	# The https vhost of the stack is rendered by the container itself, next to
	# the http one: the nginx program of supervisord writes both into
	# /etc/nginx/sites-enabled and writes the https one only when the
	# certificate is mounted, which is what HTTPS=on does.
	#
	# So this directory carries no vhost of the stack, and a per-project vhost
	# here (config/nginx/http.d/<project>.conf, see libs/phpversionDriver.sh) is
	# the first match for its own names on 443 as well as on 80: nginx.conf
	# includes http.d before sites-enabled.
	#
	# A copy that an earlier version of the stack rendered here has to go: it
	# would be included before sites-enabled and shadow every per-project vhost.
	rm -f "config/nginx/http.d/multiProjectLaravelHttps.conf"
}

function multilaravel::config() {

	# The multi-project config is not a project config. Supervisord renders it
	# from config/nginx/http.d/multiProjectLaravel.conf.template at every nginx
	# start, into /etc/nginx/sites-enabled inside the container. A laser scan
	# must not write a second copy of this vhost: two default servers make
	# nginx fail with "a duplicate default server".

	:
	multilaravel::https_vhost
}
