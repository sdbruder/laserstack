#!/bin/bash
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

# thanks https://stackoverflow.com/questions/3349105/
sail_dir=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
cd "$sail_dir" || exit

# source .env file to get MYSQL info
if [ -f ./.env ]; then
    source ./.env
fi

function nih() {
    echo "Still not implemented"
}

function dc() {
    docker-compose "$@"
}

function lasercommands() {
    sep="${1:-SEP}"
    if [ "$sep" != "NOSEP" ] ; then
        echo "  -----------------------------------------------------"
    fi
    echo "  artisan            Execute composer commands"
    echo "  composer           Execute composer"
    echo "  dockerhelp         List docker-compose and laser commands"
    echo "  help               List laser commands"
    echo "  mysql              Execute mysql"
    echo "  node               Execute node"
    echo "  npm                Execute npm"
    echo "  npx                Execute npx"
    echo "  php                Execute php commands in your app container"
    echo "  tinker             Execute php artisan tinker"
    echo "  test               Execute php artisan test"
    echo "  share              Share externally your laser stack"
    echo "  shell              Shell in the app container"
    echo "  yarn               Execute yarn"
}

function help() {
    echo "Manage a local docker stack to run multiple laravel projects."
    echo ""
    echo "Usage:"
    echo "  laser [COMMAND] [ARGS...]"
    echo ""
    echo "Commands:"
    lasercommands NOSEP
    echo "  *                  Any other command goes to docker-compose"
    echo ""
    echo "Some useful docker-compose commands (dockerhelp to full list)"
    echo "  up [-d]            Create and start containers"
    echo "  stop               Stop containers"
    echo "  logs               View output from containers"
    echo "  ps                 List containers"
}

function dockerhelp() {
    dc help
    lasercommands
}

function artisan() {
    dc exec app php artisan "$@"
}

function composer() {
    dc exec app composer "$@"
}

function mysql() {
    dc exec app bash -c "mysql MYSQL_PWD=${DB_PASSWORD} mysql -u ${DB_USER} ${DB_DATABASE}" "$@"
}

function node() {
    dc exec app node "$@"
}

function npm() {
    dc exec app npm "$@"
}

function npx() {
    dc exec app npx "$@"
}

function php() {
    dc exec app php "$@"
}

function tinker() {
    dc exec app bash -c 'mysql MYSQL_PWD=${DB_PASSWORD} mysql -u ${DB_USER} ${DB_DATABASE}' "$@"
}

function test() {
    dc exec app php artisan test "$@"
}

function share() {
    docker run \
        --init beyondcodegmbh/expose-server share http://host.docker.internal:"$APP_PORT" \
    --server-port=8080 "$@"
    # --server-host=laravel-sail.site \
}

function shell() {
    dc exec app bash "$@"
}

function yarn() {
    dc exec app yarn "$@"
}

set +e
subcommand="${1:-help}"; shift
set -e

case "$subcommand" in
    help)
        help
        ;;
    dockerhelp)
        dockerhelp
        ;;
    artisan)
        artisan "$@"
        ;;
    composer)
        composer "$@"
        ;;
    mysql)
        mysql "$@"
        ;;
    node)
        node "$@"
        ;;
    npm)
        npm "$@"
        ;;
    npx)
        npx "$@"
        ;;
    php)
        php "$@"
        ;;
    tinker)
        tinker "$@"
        ;;
    test)
        test "$@"
        ;;
    share)
        share "$@"
        ;;
    shell)
        shell "$@"
        ;;
    yarn)
        yarn "$@"
        ;;
    *)
        dc "$subcommand" "$@" || lasercommands
        ;;
esac
