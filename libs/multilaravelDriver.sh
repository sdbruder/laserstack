#!/bin/bash

function multilaravel::identify() {
	echo "no"
}

function multilaravel::https_vhost() {
	# The https vhost is not a project config either, and it exists only when
	# .env turns HTTPS on: off, the rendered file goes away, because nginx
	# refuses to start when a vhost points at a certificate that is not
	# mounted. The scan calls this inside the window it hashes, so turning
	# HTTPS on or off reports a configuration change and restarts nginx.
	local rendered="config/nginx/http.d/multiProjectLaravelHttps.conf"
	local template="config/nginx/http.d/multiProjectLaravelHttps.conf.template"
	if [ "${HTTPS:-off}" == "on" ]; then
		if [ -f "$template" ]; then
			sed "s/__SUFFIX__/${SUFFIX}/g" "$template" >"$rendered"
		fi
	else
		rm -f "$rendered"
	fi
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
