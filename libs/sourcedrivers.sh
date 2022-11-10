#!/bin/bash

# shellcheck disable=SC1091
source libs/genericDriver.sh
# shellcheck disable=SC1091
source libs/laravelDriver.sh
# shellcheck disable=SC1091
source libs/wordpressDriver.sh
# shellcheck disable=SC1091
source libs/multilaravelDriver.sh


function echoerr() {
    echo "$@" 1>&2; 
}

function drivers::config_hash() {
    dc exec app sh -c "md5sum /etc/nginx/http.d/* 2>/dev/null | md5sum"
}

function drivers::config() {
    local project_dir=${1}
    for driver in generic wordpress laravel ; do
        driverIdentify="${driver}::identify"
        driverConfig="${driver}::config"
        id=$("$driverIdentify" "$project_dir")
        if [ "$id" == "ok" ] ; then
            echoerr "SCAN: $project_dir identified as $driver."
            $driverConfig "$project_dir"
            break
        fi
    done
}

function drivers::scan_projects() {
    local projects_dir=${1}
    local hash_pre
    local hash_pos

    hash_pre=$(drivers::config_hash)
    for project in "$projects_dir"/* ; do
        drivers::config "$project"
    done
    # guarantee that the multi-project laravel config is there
    multilaravel::config

    hash_pos=$(drivers::config_hash)
    if [ "$hash_pre" == "$hash_pos" ] ; then
        echo 0
    else
        echo 1
    fi
}
