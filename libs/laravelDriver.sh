#!/bin/bash
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

function laravel::identify() {
	local project_path=${1}
	# shellcheck disable=SC2012
	qty=$(ls -1 "$project_path/artisan" "$project_path/public/index.php" 2> /dev/null | wc -l)
	if [ "$qty" -eq 2 ]; then
		echo "ok"
	else
		echo "no"
	fi
}

function laravel::config() {
	local project_path=${1:-.}
	local project
	project=$(basename "$project_path")

	# laravel is the primary target of Laser Stack and has a single
	# multi-project nginx config, so usually there is no need for a specific
	# laravel config. If you want particular laravel configs please use this as
	# an example and create a laserstack_nginx.conf file in your project.

	if [ -f "$project_path/laserstack-nginx.conf" ]; then
		cat "$project_path/laserstack-nginx.conf" > "config/nginx/http.d/$project.conf"
	# else
		# cat > "config/nginx/$project.conf" << CONFIG_END
# server {
# 	listen 80;

# 	server_name $project.local *.$project.local;
# 	root /var/www/$project/public;

# 	index index.php index.html;

# 	location / {
# 		try_files \$uri \$uri/ /index.php?\$query_string;
# 	}

# 	location ~ \.php\$ {
# 		include fastcgi.conf;
# 		fastcgi_pass 127.0.0.1:9000;
# 		fastcgi_index index.php;
# 		fastcgi_split_path_info ^(.+.php)(/.+)\$;
# 		fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
# 	}
# }
# CONFIG_END
	fi
}
