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
#   - the dashboard of the checkout answers on laserstack.<SUFFIX> and lists the
#     projects directory
#   - the run writes nothing into config/nginx/http.d of the repository
#
# Stage "php", for every version it checks:
#
#   - two projects of two PHP versions answer at the same time: one from the app
#     container, one from a worker container of another version, both through the
#     one nginx the app container runs
#   - a project without a marker keeps the version of the app container
#   - the worker loads the php.ini of the repository, like the app container
#   - laser php of the project with the marker runs in the container of its
#     version, and laser scan rendered its vhost
#
# Stage "database", for every database profile (mysql, mariadb, postgres) and
# every version it checks:
#
#   - the command of the profile answers: laser mysql, laser psql
#   - the server is the one of the profile, not another one
#   - PHP of the app container reaches the server with PDO, with the host name
#     a project uses (db, mariadb, postgres)
#
# Stage "cache", for every cache profile (redis, memcached) and every version
# it checks:
#
#   - the client extension is in the app image (the Redis and Memcached classes)
#   - PHP of the app container writes a value through the server and reads it
#     back, which is what a Laravel cache store does
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
# Usage: test/smoke.sh [version ...]     default: 7.4 8.0 8.1 8.2 8.3 8.4 8.5 8.6
#        SMOKE_DB_PROFILES="mariadb" test/smoke.sh 8.4
#        SMOKE_MYSQL_VERSION=9.7 SMOKE_DB_PROFILES=mysql test/smoke.sh 8.5
#        SMOKE_MARIADB_VERSION=11.8 SMOKE_DB_PROFILES=mariadb test/smoke.sh 8.5
#        SMOKE_POSTGRES_VERSION=18 SMOKE_DB_PROFILES=postgres test/smoke.sh 8.5
#        SMOKE_CACHE_PROFILES=memcached test/smoke.sh 8.4
#        SMOKE_CACHE_PROFILES="" test/smoke.sh 8.4      (skip the cache stage)
#        SMOKE_PULL=0 test/smoke.sh 8.4
#        SMOKE_WORKER_VERSION=8.3 test/smoke.sh 8.5   (partner of the stage php)

set -u

laser_dir=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
cd "$laser_dir" || exit 1
laser="$laser_dir/laser"
versions="${*:-7.4 8.0 8.1 8.2 8.3 8.4 8.5 8.6}"
# an explicit empty value skips the whole stage, so a run can test one stage only
db_profiles="${SMOKE_DB_PROFILES-mysql mariadb postgres}"
# the server version to test per profile. An empty value keeps the version of
# the .env under test, and the compose default when that file has none.
smoke_mysql_version="${SMOKE_MYSQL_VERSION:-}"
smoke_mariadb_version="${SMOKE_MARIADB_VERSION:-}"
smoke_postgres_version="${SMOKE_POSTGRES_VERSION:-}"
# the cache profiles to test against the client extensions of the image. An
# explicit empty value skips the whole stage.
cache_profiles="${SMOKE_CACHE_PROFILES-redis memcached}"
# versions whose image has no client for the cache profiles, so there is
# nothing to test. 8.6 is a release candidate: Alpine has no package for the
# memcached extension and the pecl build does not compile against it.
cache_skip_versions="${SMOKE_CACHE_SKIP_VERSIONS-8.6}"
# the partner of the two-version stage. An empty value picks another series of
# the list: the one before the version under test, the one after it when there
# is none, so the partner is never the release candidate by accident.
worker_version="${SMOKE_WORKER_VERSION:-}"
worker_series="7.4 8.0 8.1 8.2 8.3 8.4 8.5 8.6"
worker_project="laser-smoke-worker"
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

setenv() {
  # setenv <name> <value>: write NAME=VALUE into the .env the test builds. The
  # line is replaced when the tested file has it, appended when it has not.
  if grep -q "^$1=" .env; then
    printf '%s\n' "$(sed "s/^$1=.*/$1=$2/" .env)" >.env
  else
    echo "$1=$2" >>.env
  fi
}

cleanup() {
  rm -rf "$projects_dir/$smoke_project" "$projects_dir/$worker_project"
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

# the second project of the two-version stage: the same front page, and the
# marker that sends it to a worker container is written per iteration
mkdir -p "$projects_dir/$worker_project/public"
cp "$projects_dir/$smoke_project/public/index.php" "$projects_dir/$worker_project/public/index.php"

echo "smoke test: versions [$versions], database profiles [$db_profiles], cache profiles [${cache_profiles:-none}]"
echo "the first run pulls the images of the profiles"

say "stage app"
for version in $versions; do
  say "PHP $version"
  fails_before=$fails
  sed "s/^PHP_VERSION=.*/PHP_VERSION=$version/" "$env_backup" >.env
  # the app container reads SUFFIX at creation and the vhosts are rendered from
  # it, so the built .env always carries the value the test works with
  setenv SUFFIX "$SUFFIX"
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

  # the checkout is one of the projects, so the catch-all vhost serves the
  # dashboard without a vhost of its own
  # the first render can ask a project before its php-fpm worker answers, and the
  # tile then says grey: a page that reloads itself every 30 s gets three tries,
  # which is a fair question for the code its front page answers with
  dashboard=""
  for _ in $(seq 3); do
    dashboard=$("$laser" appexec curl -sS -m 10 -H "Host: laserstack.$SUFFIX" http://127.0.0.1/ 2>/dev/null)
    echo "$dashboard" | grep -q 'the front page answers 200' && break
    sleep 2
  done
  check "the dashboard of the checkout answers" \
    "$(echo "$dashboard" | grep -q '<title>Laser Stack</title>' && echo 0 || echo 1)"
  check "the dashboard lists the projects directory ($smoke_project)" \
    "$(echo "$dashboard" | grep -q "$smoke_project" && echo 0 || echo 1)"
  # the tile of the project carries the code its front page answered with, which
  # exercises the probe: the dashboard asks every servable project for its front
  # page in the same render
  check "the dashboard reports the code of the project ($smoke_project)" \
    "$(echo "$dashboard" | grep -q 'the front page answers 200' && echo 0 || echo 1)"

  # https is on by default: the same project answers on 443 with a certificate
  # the container trusts. A certificate of the machine itself (an own suffix, or
  # a stack that provisioned one without the network) needs -k, and the line
  # says which of the two it got.
  https_body=$("$laser" appexec curl -sS -m 10 --resolve "$smoke_project.$SUFFIX:443:127.0.0.1" "https://$smoke_project.$SUFFIX/" 2>/dev/null)
  if echo "$https_body" | grep -q "php=$version\."; then
    check "the project answers over https with a trusted certificate" 0
  else
    https_body=$("$laser" appexec curl -ksS -m 10 --resolve "$smoke_project.$SUFFIX:443:127.0.0.1" "https://$smoke_project.$SUFFIX/" 2>/dev/null)
    check "the project answers over https (certificate not trusted here: the CA of the machine)" \
      "$(echo "$https_body" | grep -q "php=$version\." && echo 0 || echo 1)"
  fi

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

say "stage php"
for version in $versions; do
  # the partner: the version before this one in the series, the one after it
  # when there is none. SMOKE_WORKER_VERSION names it outright.
  partner="$worker_version"
  if [ -z "$partner" ]; then
    previous=""
    for candidate in $worker_series; do
      [ "$candidate" == "$version" ] && break
      previous="$candidate"
    done
    [ -z "$previous" ] && previous=$(echo "$worker_series" | awk -v v="$version" '{for (i = 1; i <= NF; i++) if ($i != v) {print $i; exit}}')
    partner="$previous"
  fi
  worker="php$(echo "$partner" | tr -d '.')"
  say "PHP $version with a worker of $partner"
  fails_before=$fails
  sed -e "s/^PHP_VERSION=.*/PHP_VERSION=$version/" -e "s/^PROFILES=.*/PROFILES=$worker/" "$env_backup" >.env
  setenv SUFFIX "$SUFFIX"
  printf 'PHP_VERSION=%s\n' "$partner" >"$projects_dir/$worker_project/.laserstack"
  [ "$pull_images" == "1" ] && { "$laser" pull >/dev/null 2>&1 || echo "  --   the pull failed, the local images are used"; }
  "$laser" up >/dev/null 2>&1
  "$laser" scan >/dev/null 2>&1

  # both answers come through the one nginx of the app container: the project
  # without a marker from its own php-fpm, the other one from the worker
  app_body=$("$laser" appexec curl -sS -m 10 -H "Host: $smoke_project.$SUFFIX" http://127.0.0.1/ 2>/dev/null)
  check "the project without a marker answers with PHP $version ($app_body)" \
    "$(echo "$app_body" | grep -q "php=$version\." && echo 0 || echo 1)"

  worker_body=""
  for _ in $(seq "$wait_seconds"); do
    worker_body=$("$laser" appexec curl -sS -m 10 -H "Host: $worker_project.$SUFFIX" http://127.0.0.1/ 2>/dev/null)
    echo "$worker_body" | grep -q "php=$partner\." && break
    sleep 1
  done
  check "the project with .laserstack answers with PHP $partner ($worker_body)" \
    "$(echo "$worker_body" | grep -q "php=$partner\." && echo 0 || echo 1)"

  # the worker mounts the php.ini of the version as well, which is what makes a
  # project behave the same in either container
  worker_ini_md5=$(echo "$worker_body" | sed -n 's/.*inimd5=\([0-9a-f]*\).*/\1/p')
  worker_ini_known=$(md5_of config/php*/php.ini 2>/dev/null | grep -c "^$worker_ini_md5$")
  check "PHP of the worker loads a php.ini of the repository ($worker_ini_md5)" \
    "$([ -n "$worker_ini_md5" ] && [ "${worker_ini_known:-0}" -gt 0 ] && echo 0 || echo 1)"

  # laser php follows the project you are in
  cli_version=$( (cd "$projects_dir/$worker_project" && "$laser" php -r 'echo PHP_VERSION;') 2>/dev/null)
  check "laser php of the marker project runs PHP $partner (found ${cli_version:-nothing})" \
    "$(echo "$cli_version" | grep -qE "^$partner\.[0-9]" && echo 0 || echo 1)"

  check "laser scan rendered the vhost of the marker project" \
    "$([ -f "config/nginx/http.d/$worker_project.conf" ] && echo 0 || echo 1)"

  [ "$fails" -gt "$fails_before" ] && failed_items="$failed_items php:$version+$partner"
  # the marker leaves with the stage, and the scan removes its vhost again
  rm -f "$projects_dir/$worker_project/.laserstack"
  "$laser" scan >/dev/null 2>&1
  check "the vhost of the marker project is gone again" \
    "$([ ! -f "config/nginx/http.d/$worker_project.conf" ] && echo 0 || echo 1)"
  "$laser" stop >/dev/null 2>&1
done
"$laser" down >/dev/null 2>&1

# pdo <description> <fsn> <user> <password> <query>
pdo() {
  local out=""
  # the entrypoint of a fresh volume starts a temporary server, stops it and
  # starts the real one, so the first connection of the app container can land
  # in the gap between the two
  for _ in $(seq "$db_wait_seconds"); do
    out=$("$laser" appexec php -r "\$p=new PDO('$2','$3','$4');echo \$p->query(\"$5\")->fetchColumn();" 2>&1 | tr '\n' ' ' | tr -s ' ')
    if echo "$out" | grep -qE '^[0-9]+\.'; then
      break
    fi
    sleep 1
  done
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
    case "$profile" in
    mysql) db_var=MYSQL_VERSION db_ver="${smoke_mysql_version:-${MYSQL_VERSION:-8.0}}" ;;
    mariadb) db_var=MARIADB_VERSION db_ver="${smoke_mariadb_version:-${MARIADB_VERSION:-10.11}}" ;;
    postgres) db_var=POSTGRES_VERSION db_ver="${smoke_postgres_version:-${POSTGRES_VERSION:-15.1}}" ;;
    esac
    echo "  -- PHP $version, profile $profile, $db_var=$db_ver"
    sed -e "s/^PHP_VERSION=.*/PHP_VERSION=$version/" -e "s/^PROFILES=.*/PROFILES=$profile/" "$env_backup" >.env
    setenv SUFFIX "$SUFFIX"
    setenv "$db_var" "$db_ver"
    # the data volume of a database carries its version in the name, so a run
    # with another version gets its own data directory: this test never has to
    # remove a volume, which would destroy the data of the other profiles
    [ "$pull_images" == "1" ] && { "$laser" pull >/dev/null 2>&1 || echo "  --   the pull failed, the local images are used"; }
    "$laser" up >/dev/null 2>&1
    dbcheck "$profile" "$version"
    [ "$fails" -gt "$fails_before" ] && failed_items="$failed_items $profile:$version"
    "$laser" stop >/dev/null 2>&1
  done
  "$laser" down >/dev/null 2>&1
done

# cachecheck <profile>: the extension of the image talks to the server, which
# is the whole point of the profile: a Laravel cache store needs the class.
cachecheck() {
  local profile="$1" out=""

  case "$profile" in
  redis)
    for _ in $(seq "$db_wait_seconds"); do
      out=$("$laser" appexec php -r "\$r=new Redis();\$r->connect('redis',6379);\$r->set('laser','smoke');echo \$r->get('laser');" 2>&1 | tr '\n' ' ' | tr -s ' ')
      [ "$out" == "smoke" ] && break
      sleep 1
    done
    check "PHP of the image reaches redis with the Redis class (${out:0:120})" \
      "$([ "$out" == "smoke" ] && echo 0 || echo 1)"
    ;;
  memcached)
    for _ in $(seq "$db_wait_seconds"); do
      out=$("$laser" appexec php -r "\$m=new Memcached();\$m->addServer('memcached',11211);\$m->set('laser','smoke',30);echo \$m->get('laser');" 2>&1 | tr '\n' ' ' | tr -s ' ')
      [ "$out" == "smoke" ] && break
      sleep 1
    done
    check "PHP of the image reaches memcached with the Memcached class (${out:0:120})" \
      "$([ "$out" == "smoke" ] && echo 0 || echo 1)"
    ;;
  *) echo "  --   $profile is not a cache profile of the test" ;;
  esac
}

say "stage cache"
for profile in $cache_profiles; do
  say "cache $profile"
  "$laser" down >/dev/null 2>&1
  for version in $versions; do
    case " $cache_skip_versions " in
    *" $version "*)
      echo "  -- PHP $version, profile $profile: skipped, the image has no client for it"
      continue
      ;;
    esac
    fails_before=$fails
    echo "  -- PHP $version, profile $profile"
    sed -e "s/^PHP_VERSION=.*/PHP_VERSION=$version/" -e "s/^PROFILES=.*/PROFILES=$profile/" "$env_backup" >.env
    setenv SUFFIX "$SUFFIX"
    [ "$pull_images" == "1" ] && { "$laser" pull >/dev/null 2>&1 || echo "  --   the pull failed, the local images are used"; }
    "$laser" up >/dev/null 2>&1
    cachecheck "$profile"
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
