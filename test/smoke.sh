#!/bin/bash
#
# Smoke test of the stack: one "laser up" per PHP version, and one per database
# profile.
#
# Stage "app", for every version it checks:
#
#   - nginx and php-fpm reach the RUNNING state, no nginx emergency in the log
#   - php-fpm runs its workers as the "laser" user
#   - the php.ini of the repository is the file that PHP loads
#   - a project answers over http with the expected PHP version
#   - the run writes nothing into config/nginx/http.d of the repository
#
# Stage "database", for every database profile (mysql, mariadb, postgres) and
# every version it checks:
#
#   - the command of the profile answers: laser mysql, laser psql
#   - the server is the one of the profile, not another one
#   - PHP of the app container reaches the server with PDO, with the host name
#     a project uses (db, mariadb, postgres)
#
# The test does not use port 80 of the host, because another web server (Valet,
# Herd) may hold it. The http check calls curl inside the app container.
#
# The test stops the stack at the end. The .env file and the directory of the
# test project return to their state before the run. The database volumes and
# the images stay.
#
# The test pulls the image of every version it starts, so a stale image of an
# older run cannot fail the test. SMOKE_PULL=0 uses the local images.
#
# Usage: test/smoke.sh [version ...]     default: 7.4 8.0 8.1 8.2 8.3 8.4 8.5
#        SMOKE_DB_PROFILES="mariadb" test/smoke.sh 8.4
#        SMOKE_PULL=0 test/smoke.sh 8.4

set -u

laser_dir=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
cd "$laser_dir" || exit 1
laser="$laser_dir/laser"
versions="${*:-7.4 8.0 8.1 8.2 8.3 8.4 8.5}"
db_profiles="${SMOKE_DB_PROFILES:-mysql mariadb postgres}"
# the test pulls the images of the version it starts, so a stale image of an
# older run cannot fail the test. SMOKE_PULL=0 keeps the local images.
pull_images="${SMOKE_PULL:-1}"
smoke_project="laser-smoke"
wait_seconds=60
db_wait_seconds=90

fails=0
failed_items=""

# md5sum on Linux, md5 on macOS
if command -v md5sum >/dev/null 2>&1; then
  md5_of() { md5sum "$@" | awk '{print $1}'; }
else
  md5_of() { md5 -q "$@"; }
fi

say() {
  echo "### $*"
}

check() {
  # check <description> <condition-result>
  if [ "$2" == "0" ]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1"
    fails=$((fails + 1))
  fi
}

cleanup() {
  rm -rf "$projects_dir/$smoke_project"
  if [ -n "${env_backup:-}" ]; then
    cp "$env_backup" .env
    rm -f "$env_backup"
  fi
}

# laser creates .env from env.example when it is absent
[ -f .env ] || "$laser" help >/dev/null 2>&1
env_backup=$(mktemp)
cp .env "$env_backup"

# shellcheck source=/dev/null
source ./env.example
# shellcheck source=/dev/null
source ./.env
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
projects_dir=$(cd "$PROJECTS_DIRECTORY" && pwd)
trap cleanup EXIT

mkdir -p "$projects_dir/$smoke_project/public"
cat >"$projects_dir/$smoke_project/public/index.php" <<'PHP'
<?php
header('Content-Type: text/plain');
$status = file_get_contents('/proc/self/status');
preg_match('/^Uid:\s+(\d+)\s+(\d+)/m', $status, $uid);
$ini = php_ini_loaded_file();
echo 'php=', PHP_VERSION, ' ini=', $ini, ' inimd5=', md5_file($ini), ' euid=', $uid[1], "\n";
PHP

echo "smoke test: versions [$versions], database profiles [$db_profiles]"
echo "the first run pulls the images of the database profiles"

say "stage app"
for version in $versions; do
  say "PHP $version"
  fails_before=$fails
  sed "s/^PHP_VERSION=.*/PHP_VERSION=$version/" "$env_backup" >.env
  httpd_before=$(ls config/nginx/http.d)

  "$laser" stop >/dev/null 2>&1
  [ "$pull_images" == "1" ] && { "$laser" pull >/dev/null 2>&1 || echo "  --   the pull failed, the local images are used"; }
  "$laser" up >/dev/null 2>&1

  state=""
  for _ in $(seq "$wait_seconds"); do
    state=$("$laser" appexec supervisorctl status 2>/dev/null | grep -cE '^(nginx|php-fpm)\s+RUNNING')
    [ "$state" == "2" ] && break
    sleep 1
  done
  check "nginx and php-fpm are RUNNING" "$([ "$state" == "2" ] && echo 0 || echo 1)"

  log=$("$laser" logs --tail 200 app 2>&1)
  check "no nginx emergency in the log" "$(echo "$log" | grep -qi emerg && echo 1 || echo 0)"

  php_version=$("$laser" appexec php -r 'echo PHP_VERSION;' 2>/dev/null)
  check "PHP is $version (found ${php_version:-nothing})" \
    "$(echo "$php_version" | grep -qE "^$version\.[0-9]" && echo 0 || echo 1)"

  # busybox ps prints "PID USER TIME COMMAND", the user is the second column
  pool_user=$("$laser" appexec sh -c 'ps aux | grep -F php-fpm | grep -v grep' 2>/dev/null | awk '{print $2}' | grep -c '^laser$')
  check "php-fpm workers run as laser" "$([ "${pool_user:-0}" -gt 0 ] && echo 0 || echo 1)"

  body=$("$laser" appexec curl -sS -m 10 -H "Host: $smoke_project.$SUFFIX" http://127.0.0.1/ 2>/dev/null)
  check "the project answers with PHP $version ($body)" \
    "$(echo "$body" | grep -q "php=$version\." && echo 0 || echo 1)"

  ini_md5=$(echo "$body" | sed -n 's/.*inimd5=\([0-9a-f]*\).*/\1/p')
  ini_known=$(md5_of config/php*/php.ini 2>/dev/null | grep -c "^$ini_md5$")
  check "PHP loads a php.ini of the repository ($ini_md5)" \
    "$([ -n "$ini_md5" ] && [ "${ini_known:-0}" -gt 0 ] && echo 0 || echo 1)"

  euid=$(echo "$body" | sed -n 's/.*euid=\([0-9]*\).*/\1/p')
  check "the request runs as the laser user (euid $euid)" "$([ "${euid:-0}" == "1000" ] && echo 0 || echo 1)"

  check "the run wrote nothing into config/nginx/http.d" \
    "$([ "$httpd_before" == "$(ls config/nginx/http.d)" ] && echo 0 || echo 1)"

  [ "$fails" -gt "$fails_before" ] && failed_items="$failed_items app:$version"
  "$laser" stop >/dev/null 2>&1
done

# pdo <description> <dsn> <user> <password> <query>
pdo() {
  local out
  out=$("$laser" appexec php -r "\$p=new PDO('$2','$3','$4');echo \$p->query(\"$5\")->fetchColumn();" 2>&1 | tr '\n' ' ' | tr -s ' ')
  check "$1 (${out:0:120})" "$(echo "$out" | grep -qE '^[0-9]+\.' && echo 0 || echo 1)"
}

# dbcheck <profile> <version>
dbcheck() {
  local profile="$1" version="$2" host user pass dbname out

  case "$profile" in
  mysql)
    host=db user="${DB_USERNAME:-root}" pass="${DB_PASSWORD:-root}" dbname="${DB_DATABASE:-}"
    ;;
  mariadb)
    host=mariadb user="${MARIADB_USER:-root}" pass="${MARIADB_PASSWORD:-root}" dbname="${MARIADB_DATABASE:-}"
    ;;
  postgres)
    host=postgres user="$POSTGRES_USER" pass="$POSTGRES_PASSWORD" dbname="$POSTGRES_DB"
    ;;
  esac

  for _ in $(seq "$db_wait_seconds"); do
    case "$profile" in
    postgres) out=$("$laser" psql -c 'select version();' 2>/dev/null | grep 'PostgreSQL') ;;
    *) out=$("$laser" mysql -e 'select version();' 2>/dev/null | tail -1) ;;
    esac
    [ -n "$out" ] && break
    sleep 1
  done

  case "$profile" in
  postgres)
    check "laser psql answers ($out)" "$(echo "$out" | grep -q PostgreSQL && echo 0 || echo 1)"
    ;;
  mysql)
    check "laser mysql answers with mysql ($out)" \
      "$(echo "$out" | grep -qE '^[0-9]+\.[0-9]+' && ! echo "$out" | grep -q MariaDB && echo 0 || echo 1)"
    ;;
  mariadb)
    check "laser mysql answers with mariadb ($out)" "$(echo "$out" | grep -q MariaDB && echo 0 || echo 1)"
    ;;
  esac

  if [ "$profile" == "postgres" ]; then
    pdo "PHP reaches postgres as $user" "pgsql:host=$host;dbname=$dbname" "$user" "$pass" \
      "select current_setting('server_version')"
  else
    pdo "PHP reaches $host as $user" "mysql:host=$host;dbname=$dbname" "$user" "$pass" "select version()"
    # the mariadb profile answers to "db" as well, the name projects use
    [ "$profile" == "mariadb" ] && pdo "PHP reaches mariadb by the name db" \
      "mysql:host=db;dbname=$dbname" "$user" "$pass" "select version()"
  fi
}

say "stage database"
for profile in $db_profiles; do
  say "database $profile"
  "$laser" down >/dev/null 2>&1
  for version in $versions; do
    fails_before=$fails
    echo "  -- PHP $version, profile $profile"
    sed -e "s/^PHP_VERSION=.*/PHP_VERSION=$version/" -e "s/^PROFILES=.*/PROFILES=$profile/" "$env_backup" >.env
    [ "$pull_images" == "1" ] && { "$laser" pull >/dev/null 2>&1 || echo "  --   the pull failed, the local images are used"; }
    "$laser" up >/dev/null 2>&1
    dbcheck "$profile" "$version"
    [ "$fails" -gt "$fails_before" ] && failed_items="$failed_items $profile:$version"
    "$laser" stop >/dev/null 2>&1
  done
  "$laser" down >/dev/null 2>&1
done

say "result"
if [ "$fails" -eq 0 ]; then
  echo "all checks passed"
else
  echo "$fails check(s) failed on:$failed_items"
fi
[ "$fails" -eq 0 ]
