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

	server_name $project.local *.$project.local;

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
	fi
}
