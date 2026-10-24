#!/bin/bash

function multilaravel::identify() {
	echo "no"
}

function multilaravel::config() {

	# The multi-project config is not a project config. Supervisord renders it
	# from config/nginx/http.d/multiProjectLaravel.conf.template at every nginx
	# start, into /etc/nginx/sites-enabled inside the container. A laser scan
	# must not write a second copy of this vhost: two default servers make
	# nginx fail with "a duplicate default server".

	:
}
