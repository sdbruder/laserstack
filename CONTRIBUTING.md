# Working on Laser Stack

This is the documentation for the people who build and maintain Laser Stack:
what the pieces are, how to add a version, how to test it and how to cut a
release. The documentation for *using* the stack is in the
[README](README.md).

## Repository layout

```
docker-compose.yml    the app service and one service per database profile
laser                 the shell script around docker-compose, the user interface
env.example           the documented .env; laser copies it when .env is absent
config/               the config of every image version, mounted per service
  php<VV>/            php.ini, php-fpm.conf and php-fpm.d of one PHP series
  supervisord.<VV>/   supervisord.conf of one PHP series
  nginx/              nginx.conf and the vhosts of the app container
  my.cnf              the client config of a shell in the app container
  <engine>/<version>/ the config of one database version, one directory each
libs/                 the nginx config drivers behind `laser scan`
test/smoke.sh         the smoke test, one run per PHP and database version
docker/app/           the older local build context of the app image
opt/                  former compose fragments, unused
CHANGELOG.md          the release notes, newest first
```

## How the stack is put together

`docker-compose.yml` holds one `app` service and one service per database
engine, each behind its compose profile: `db` (mysql), `mariadb`, `postgres`,
`redis`, `memcached` and `elasticsearch`. The `app` service builds nothing, it
pulls the public image `laserstack/app:<PHP_VERSION>`; that image comes from the
[laserstack_app](https://github.com/sdbruder/laserstack_app) repository, which
builds every PHP series from its own Dockerfiles. Inside the container
supervisord runs nginx, which serves the projects, and php-fpm. The mariadb
service carries the network alias `db`, so the projects that point at `db` work
with the mysql profile and with the mariadb profile; port 3306 is what keeps the
two profiles apart.

Every version of every image has its own config directory, and
`docker-compose.yml` builds the image tag and the mount path from the same
variable, with the same inline default (`image: "mysql:${MYSQL_VERSION:-8.0}"`
and `./config/mysql/${MYSQL_VERSION:-8.0}`). PHP is the same rule with the
directory names of the images: `config/php<VV>` and `config/supervisord.<VV>`.

`laser` is the whole interface, and it is a wrapper around docker-compose:

- it copies `env.example` to `.env` when there is no `.env`, and sources it;
- it exports `PHPV` and `PHPALPINE` from `PHP_VERSION`, because the image names
  the php config directory `php8` for 8.0 and `php7` for 7.4;
- it turns `PROFILES` into `dc_params` (`--profile` per entry) and hands it to
  `dc()`, the single place that calls `docker-compose`, so every subcommand sees
  the profiles of `.env`;
- it dispatches its own subcommands, derives the project of the
  `artisan`/`php`/`shell`/`appexec` family from the current directory, and passes
  every other subcommand to `docker-compose` as it is.

`libs/sourcedrivers.sh` is the registry behind `laser scan`. It sources one file
per driver and walks them for every directory of the projects: `drivers::config`
asks each driver's `<name>::identify()` about the project, and the first one that
answers `ok` writes the nginx config of that project with `<name>::config()`.
`drivers::scan_projects` hashes the vhosts of the container before and after the
walk, so `laser scan` knows whether nginx needs a restart. The `generic`,
`wordpress`, `laravel` and `symfony` drivers are examples; `multilaravel` is not
a project driver, it only keeps the default vhost out of the scan, because
supervisord renders `config/nginx/http.d/multiProjectLaravel.conf.template` at
every nginx start and a second default server makes nginx fail. A new kind of
project is one more file in `libs/`, sourced there, and a pull request is
welcome.

## Add a PHP version

1. build and publish the series in
   [laserstack_app](https://github.com/sdbruder/laserstack_app) as
   `laserstack/app:<major.minor>`;
2. copy `config/php<VV>/` and `config/supervisord.<VV>/` from the newest series
   and adjust them to the image, for example its php.ini path and its fpm
   version;
3. add the version to the `PHP_VERSION` list of `env.example` and to the default
   list of `test/smoke.sh`;
4. add its row to the Versions table of the README: the php patch, Alpine, node,
   npm, yarn, nginx, phpunit and xdebug of that series. Read them from the
   image instead of guessing:

   ```
   docker run --rm --entrypoint sh laserstack/app:<major.minor> -c \
     'cat /etc/alpine-release; php -v | head -1; node -v; npm -v; yarn -v;
      nginx -v; phpunit --version; composer --version;
      php -r "echo phpversion(\"xdebug\");"'
   ```

5. run `test/smoke.sh <major.minor>`.

## Add a database version

1. create `config/<engine>/<version>/` and copy the config of the previous
   version into it, changing only what the new server needs. The file of each
   engine is `docker.cnf`, `mysql.cnf` and `mysqld.cnf` for mysql,
   `laserstack.cnf` for mariadb, `postgresql.conf`, `redis.conf` and
   `elasticsearch.yml`; memcached has no config file, its image takes flags;
2. add the version to the list in the `DATABASE VERSIONS` block of `env.example`
   and to the table in the README;
3. run the smoke test with the override, which starts that server and drops the
   volumes first:

   ```
   SMOKE_MYSQL_VERSION=9.7 SMOKE_DB_PROFILES=mysql test/smoke.sh 8.5
   SMOKE_MARIADB_VERSION=11.8 SMOKE_DB_PROFILES=mariadb test/smoke.sh 8.5
   SMOKE_POSTGRES_VERSION=18 SMOKE_DB_PROFILES=postgres test/smoke.sh 8.5
   ```

4. for redis, memcached and elasticsearch there is no smoke stage: start the
   profile and probe it, for example
   `laser appexec php -r '$r=new Redis();$r->connect("redis",6379);echo $r->ping();'`
   for redis, and `laser appexec curl -sS http://elasticsearch:9200` for
   elasticsearch.

Things the current list taught us, in case the new version behaves the same way:

- an option copied from the image's own config file can stop a newer server.
  `skip-host-cache` is in the `docker.cnf` of the mysql image and MySQL removed
  it in 8.3: the server exits with `unknown option '--skip-host-cache'`, and
  `host_cache_size = 0` is the documented replacement;
- the client binary is not the same in every version. The MariaDB images ship no
  `mysql` binary from 11.4 on, only `mariadb`, which is why `laser` picks the
  name of the client per profile;
- authentication moves with the major version. MySQL 8.0 creates its accounts
  with `mysql_native_password` (`default_authentication_plugin`), 8.4 only
  *enables* that plugin and creates `caching_sha2_password` accounts, and 9.0
  removed it. `caching_sha2_password` needs TLS or the RSA public-key exchange;
  PHP (mysqlnd) does the exchange over plain TCP by itself, the mysql client of
  the app image does not, which is why `laser mysql` runs the client of the
  database container over its unix socket;
- the data directory of an image can move and then refuse the old mount.
  postgres 18 stores its data in `/var/lib/postgresql/<major>/docker` by default
  and stops with a volume at `/var/lib/postgresql/data`, so the postgres service
  pins `PGDATA` to the older path;
- read the log and the state before drawing conclusions:
  `laser logs --tail 100 <service>` and `laser ps` say whether the container came
  up at all, and a server that answers on its socket is not yet ready for the
  network clients of the app container.

No validation is added for a version: an unlisted one gives the raw docker error
(`bind source path does not exist`), like every other misconfiguration of this
stack.

## The smoke test

`test/smoke.sh` starts the stack once per PHP version and once per database
profile. It checks:

- stage `app`, per version: nginx and php-fpm are RUNNING, no nginx emergency
  in the log, php-fpm runs the workers as `laser`, PHP loads the php.ini of the
  repository, a project answers over http with the requested version, and the
  run writes nothing into `config/nginx/http.d`;
- stage `database`, per database profile and version: `laser mysql` or
  `laser psql` answers with the server of the profile, and PHP of the app
  container reaches that server with PDO, under the host name a project uses
  (`db`, `mariadb`, `postgres`).

The http check runs inside the container, so a web server on port 80 of the
host, like Valet or Herd, does not disturb the test.

```
test/smoke.sh                                 # every version, every database profile
test/smoke.sh 8.4 8.5                         # only these versions
SMOKE_DB_PROFILES=mariadb test/smoke.sh 8.2   # one database profile
SMOKE_MYSQL_VERSION=9.7 SMOKE_DB_PROFILES=mysql test/smoke.sh 8.5
SMOKE_PULL=0 test/smoke.sh 8.4                # use the local images
```

The test pulls the image of every version it starts, so an old image of an
earlier run cannot fail the test. `SMOKE_PULL=0` keeps the local images. A run
with `SMOKE_MYSQL_VERSION`, `SMOKE_MARIADB_VERSION` or `SMOKE_POSTGRES_VERSION`
drops the volumes first, because a data volume belongs to the server version
that created it.

The test stops the stack at the end and leaves `.env` as it was. The database
volumes stay, and the first run pulls the images of the database profiles.

## Shell in this repository

- `laser` runs with `set -euo pipefail` and `IFS=$'\n\t '`; `test/smoke.sh` runs
  with `set -u` and counts its failures instead of exiting at the first one;
- call `docker-compose` through `dc()`, so the profiles of `.env` apply;
- comments say why a line is there; the code and the comments are in English;
- check a script before committing: `bash -n <script>`, and `shellcheck
  <script>` where it is installed;
- never edit a script while it runs. `bash` reads a script by byte offset, so an
  inserted or a deleted line shifts the offsets and the next read lands in the
  middle of a token; the symptom is a syntax error on a line whose text is
  correct. Write a new file, or wait;
- prove a change by running it: the smoke test for the stack, the command itself
  for the script.

Commits carry a lowercase imperative subject in one line and, in the body, what
changed and how it was verified.

## Release

- a change to the stack goes into the `## [Unreleased]` section of
  `CHANGELOG.md`, under `Added`, `Changed` or `Removed` (Keep a Changelog);
- a release renames that section to `## [X.Y.Z] YYYY-MM-DD`, commits it, and
  tags the commit with an annotated tag `git tag -a vX.Y.Z`;
- the date of the entry is the date of the tag, and the tag is the release. The
  app images have their own releases in laserstack_app, where `latest` is the
  newest released series;
- branches for work in progress are named `feature/<name>` and are merged into
  `master` when the smoke test passes.

## Debugging the stack

- `laser ps` and `laser logs --tail 100 <service>` show the state and the log of
  the containers of the active profiles;
- `laser appexec <command>` runs a command in the app container. The current
  directory decides the project, so run it from a project directory for a
  project and from the repository root for the container;
- `docker-compose --profile <profile> config` prints what compose makes of the
  files: the resolved image tags, the mount sources, the commands and the values
  of every `${VAR:-default}`;
- a change of the version of a database needs `laser down -v`, because the data
  volume belongs to the server version that created it;
- there is no validation layer. A path that the version does not have, an image
  tag that does not exist, or a variable in a config file that the server does
  not know all end as the raw docker or server error, and that error is the
  message to work from.
