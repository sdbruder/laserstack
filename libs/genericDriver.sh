#!/bin/bash
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

function generic::identify() {
	local project_path=${1}
	# shellcheck disable=SC2012
	qty=$(ls -1 "$project_path/.laserstack_nginx.conf" 2> /dev/null | wc -l)
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
	if [ -f "$project_path/.laserstack_nginx.conf" ]; then
		cat "$project_path/.laserstack_nginx.conf" > "config/nginx/$project.conf"
	fi
}
