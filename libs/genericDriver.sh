#!/bin/bash

function generic::identify() {
	local project_path=${1}
	# shellcheck disable=SC2012
	qty=$(ls -1 "$project_path/laserstack-nginx.conf" 2> /dev/null | wc -l)
	if [ "$qty" -gt 0 ]; then
		echo "ok"
	else
		echo "no"
	fi
}

function generic::config() {
	local project_path=${1:-.}
	local project
	project=$(basename "$project_path")
	if [ -f "$project_path/laserstack-nginx.conf" ]; then
		cat "$project_path/laserstack-nginx.conf" > "config/nginx/http.d/$project.conf"
	fi
}
