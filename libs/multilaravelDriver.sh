#!/bin/bash
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

function multilaravel::identify() {
	echo "no"
}

function multilaravel::config() {

	# this a single multi-project laravel nginx config which is the primary
	# target of Laser Stack. This will be executed every time we do not find
	# this particular multi-project config.

	if [ ! -f "config/nginx/http.d/multiProjectLaravel.conf" ]; then
		cat > "config/nginx/http.d/multiProjectLaravel.conf" <<'CONFIG_END'
server {
    listen 80 default_server;

    # this allows:
    # - yourproject.local
    # - anything.yourproject.local
    # - othersubdomain.anything.yourproject.local
    #
    # and all those urls will load:
    # ${PROJECTS_DIRECTORY}/yourproject/public

    server_name "~^([^.]*\.){0,}(?P<project>[^.]+)\.local$";
    root /var/www/$project/public;

    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi.conf;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_split_path_info ^(.+.php)(/.+)$;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
CONFIG_END
	fi
}
