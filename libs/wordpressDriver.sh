#!/bin/bash

function wordpress::identify() {
	local project_path=${1}
	# shellcheck disable=SC2012
	qty=$(ls -1 "$project_path/wp-config.php" "$project_path/wp-config-sample.php" 2> /dev/null | wc -l)
	if [ "$qty" -gt 0 ]; then
		echo "ok"
	else
		echo "no"
	fi
}

# The HTTPS block of a WordPress project. With HTTPS=on the multi-project vhost
# serves the projects that have a public/index.php on 443, but a WordPress
# project is served from the root of the project, which that vhost cannot cover,
# so the driver writes the same vhost on 443, with the certificate laser tls
# leaves in config/tls/serve. A project that carries its own
# laserstack-nginx.conf keeps that file as it is: add a block like this one to it
# when it has to answer over https.
function wordpress::https_block() {
	local project_path=${1:-.}
	local project
	project=$(basename "$project_path")
	if [ "${HTTPS:-off}" != "on" ]; then
		return 0
	fi
	cat << CONFIG_END

server {
	listen 443 ssl;

	server_name $project.$SUFFIX *.$project.$SUFFIX;

	root /var/www/$project;

	ssl_certificate     /etc/nginx/tls/laserstack.pem;
	ssl_certificate_key /etc/nginx/tls/laserstack-key.pem;

	index index.php index.html;

	location / {
		try_files \$uri \$uri/ /index.php?\$query_string;
	}

	location ~ \.php\$ {
		include fastcgi.conf;
		fastcgi_pass 127.0.0.1:9000;
		fastcgi_index index.php;
		fastcgi_split_path_info ^(.+.php)(/.+)\$;
		fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	}
}
CONFIG_END
}

function wordpress::config() {
	local project_path=${1:-.}
	local project
	project=$(basename "$project_path")
	if [ -f "$project_path/laserstack-nginx.conf" ]; then
		cat "$project_path/laserstack-nginx.conf" > "config/nginx/http.d/$project.conf"
	else
		cat > "config/nginx/http.d/$project.conf" << CONFIG_END
server {
	listen 80;

	server_name $project.$SUFFIX *.$project.$SUFFIX;

	root /var/www/$project;

	index index.php index.html;

	location / {
		try_files \$uri \$uri/ /index.php?\$query_string;
	}

	location ~ \.php\$ {
		include fastcgi.conf;
		fastcgi_pass 127.0.0.1:9000;
		fastcgi_index index.php;
		fastcgi_split_path_info ^(.+.php)(/.+)\$;
		fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	}
}
CONFIG_END
		wordpress::https_block "$project_path" >> "config/nginx/http.d/$project.conf"
	fi
}
