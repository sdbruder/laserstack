# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.13.1] 2026-11-05

### Added

- `SUFFIX=localdev.it` needs no local DNS at all: every name under that domain —
  any depth, IPv4 and IPv6 — resolves to `127.0.0.1` and `::1`, so every project
  of the projects directory answers as `projecta.localdev.it` on the machine that
  runs the stack, with no `/etc/hosts` and no dnsmasq. The docs, the README, the
  `env.example` comment and the installer's next steps say so — including that a
  suffix change needs `laser up -d` before `laser scan` — and
  `https://localdev.it/` redirects to the site.
- `laser update` and `laser update --check`: fast-forward the checkout, pull the
  newest images of the active profiles, print the PHP version of the app image
  next to the one the container runs, and restart only the containers whose image
  changed. It pairs with the nightly rebuild of the app images in laserstack_app,
  whose series tag (`laserstack/app:8.4`) always carries the newest patch of that
  series, so a patch release reaches a running stack with one command.
- `docs/install`, the one-line installer served by the site:
  `curl -fsSL https://localdev.it/laserstack/install | bash`. It checks bash,
  git and docker with compose v2, clones the stack next to the projects (or
  fast-forwards a checkout that is already there), writes `env.example` to
  `.env` when there is none, and prints the steps left. It touches nothing else
  on the machine: no system package, no shell profile, no daemon.
- The project website, `docs/` in the repository, published by GitHub Pages at
  <https://localdev.it/laserstack/>: an overview with the measured cost of
  the stack, the features, the numbers with the method to reproduce them, a
  documentation and an examples page, and the roadmap. Static HTML and one CSS
  file, no build step and no framework.

### Changed

- `env.example` defaults `SUFFIX` to `localdev.it`, so a fresh install serves
  every project as `projecta.localdev.it` with no `/etc/hosts` line, no dnsmasq
  and nothing installed. `laser share` and the wordpress driver use the
  configured suffix instead of the hard-coded `.test` and `.local` they had, and
  `laser new` opens `http://<project>.<SUFFIX>/` and writes an `/etc/hosts` line
  only for a suffix of the user's own. The examples that need a hosts line use
  `test`, the name RFC 6761 reserves, instead of the legacy `local`.
- The project is also called *the localdev.it stack*: the README, the site hero,
  the installer help and the GitHub description say so, tied to the domain of the
  default suffix.

## [0.13.0] 2026-11-04

### Added

- One version variable per database engine, `MYSQL_VERSION`,
  `MARIADB_VERSION`, `POSTGRES_VERSION`, `REDIS_VERSION`, `MEMCACHED_VERSION`
  and `ELASTICSEARCH_VERSION`, the same capacity the PHP version has. The
  variable selects the image tag and the config directory
  `config/<engine>/<version>/`, which holds one directory per supported version.
  The defaults stay `mysql:8.0`, `mariadb:10.11`, `postgres:15.1-alpine`,
  `redis:8.10-alpine`, `memcached:1.6-alpine` and `elasticsearch:7.14.2`, so an
  existing `.env` behaves as before.
- The versions `MYSQL_VERSION=8.4`, `9.7` and `26.10`, `MARIADB_VERSION=11.4`,
  `11.8`, `12.3` and `13.0`, `POSTGRES_VERSION=16`, `17` and `18`,
  `REDIS_VERSION=8.8`, `8.6`, `8.4`, `8.2` and `7.4`, and
  `ELASTICSEARCH_VERSION=8.19.23` and `9.5.5`. `test/smoke.sh` takes
  `SMOKE_MYSQL_VERSION`, `SMOKE_MARIADB_VERSION` and `SMOKE_POSTGRES_VERSION`
  for a run with one of them, and drops the volumes first, because a data volume
  belongs to the server version that created it.

### Changed

- `laser mysql` runs the `mysql` client of the database container of the active
  profile over its unix socket, not the client of the app container. A client
  that ships with the server knows every authentication plugin of that server,
  and the socket is a secure transport for `caching_sha2_password`, the plugin
  that MySQL `8.4`, `9.7` and `26.10` use because MySQL 9.0 removed
  `mysql_native_password`. It also selects the name of the client per profile,
  `mariadb` for the mariadb one, whose images ship no `mysql` binary from 11.4
  on. That makes `laser mysql` work with every supported version; the client of
  the app image needs the `caching_sha2_password` plugin of
  `mariadb-connector-c`, which the images do not have, and the README states
  that limitation for a shell in the app container.
- The postgres service sets `PGDATA=/var/lib/postgresql/data`, the path of
  postgres 15 to 17 and of the entrypoint of the image. The images from
  postgres 18 changed their default to `/var/lib/postgresql/<major>/docker` and
  refuse to start when the data volume is at the older path.
- The config directory of the mysql profile is `config/mysql/8.0`,
  `config/postgres` is `config/postgres/15.1`, and every version directory
  carries its own copy of the config file. MariaDB, redis and elasticsearch have
  a config file of the repository now:
  `config/mariadb/<version>/laserstack.cnf`,
  `config/redis/<version>/redis.conf` and
  `config/elasticsearch/<version>/elasticsearch.yml`, the last one with
  `xpack.security.enabled: false`, which the images from elasticsearch 8 need.
- `config/mysql/<version>/docker.cnf` holds the authentication settings of the
  server version. On `8.0` the accounts use `mysql_native_password`
  (`default_authentication_plugin`). On `8.4` that option is gone and
  `mysql_native_password = ON` only *enables* the plugin, so its accounts use
  `caching_sha2_password`, the default of the server, like `9.7` and `26.10`,
  where the plugin does not exist at all. The host cache is off on every version
  through `host_cache_size = 0`, because MySQL removed `skip-host-cache` in 8.3
  and refuses to start with it.
- The documentation is split: `README.md` is the user documentation (installing,
  configuring and running the stack) and `CONTRIBUTING.md` is the development
  documentation (the repository layout, how the stack is put together, how to
  add a PHP or a database version, the smoke test, the release process and how
  to debug a container). The smoke test section moved out of the README
  unchanged, and the development documentation now shows how to run a sweep over
  every supported server version and where the manual probes of redis, memcached
  and elasticsearch are. The README also states that the app images carry no
  `memcached` PHP extension, so that profile serves the server only.

### Removed

- The `command:` line of the mysql and the mariadb service of
  `docker-compose.yml`. The option of the mysql one lives in the config
  directory of the version now, the option of the mariadb one was a
  compatibility no-op that the MariaDB image ignores.

## [0.12.0] 2026-11-04

### Added

- `config/php86` and `config/supervisord.8.6`, the config of the images of
  PHP 8.6. `PHP_VERSION=8.6` starts the new app image. PHP 8.6 has no stable
  release yet (GA is planned for 19 November 2026), so that image is a release
  candidate and does not take the `latest` tag, which stays on `8.5`.
- PHP 8.6 in the default version list of `test/smoke.sh`, and in the
  `PHP_VERSION` list of `env.example`.

### Changed

- The README lists the current versions of the app images: PHP 7.4.33, 8.0.30,
  8.1.34, 8.2.35, 8.3.36, 8.4.27, 8.5.12 and 8.6.0RC5, on Alpine 3.15, 3.16,
  3.19, 3.22, 3.24, 3.24, 3.24 and `edge`, plus node, npm, yarn, nginx,
  phpunit and xdebug of each series. Every image has composer 2.11.1. Before,
  the README listed composer 2.10.3 and stopped at PHP 8.5.
- The README `PROFILES` list names the image of each profile (`mysql:8.0`,
  `mariadb:10.11`, `postgres:15.1-alpine`, `redis:alpine`,
  `memcached:alpine`, `elasticsearch:7.14.2`).

## [0.11.1] 2026-10-24

### Added

- `test/smoke.sh` checks every database profile now, not only the profile of
  `.env`: `laser mysql` for mysql and mariadb, `laser psql` for postgres, and
  the PDO path of the app container to the server of the profile under the host
  name a project uses. `SMOKE_DB_PROFILES` limits the profiles. The test pulls
  the image of every version it starts, so an old image cannot fail it;
  `SMOKE_PULL=0` uses the local images.

### Changed

- The entry of 0.8.0 carries the date `2022-11-26` and the content of the tag
  `v0.8.0` (php 7.4 and 8.2, sqlite). Before, it carried the date `2024-05-11`
  and the bullets of 0.10.0 and 0.9.0, which have their own entries.

### Fixed

- The images of PHP 7.4 and 8.0 have `pdo_pgsql`. Without that driver a project
  could not reach the postgres profile from those two images, which the
  database stage of the smoke test showed. The image of 8.1 and newer had it.

## [0.11.0] 2026-10-24

### Added

- `config/php85` and `config/supervisord.8.5`, the config of the images of
  PHP 8.5.
- `test/smoke.sh`, a smoke test that starts the stack once per PHP version and
  checks php-fpm, the php.ini of the repository, an http request and the
  database command of the active profile.

### Changed

- `env.example` has the `MARIADB_*` variables of `docker-compose.yml` and the
  list of profiles has `mariadb`. Before, every docker compose command printed
  "variable is not set" for the four mariadb variables on a fresh clone.
- `.gitignore` ignores only `.env` and the vhosts that laserstack and
  `laser scan` write into `config/nginx/http.d`. Before, it ignored the whole
  `config` directory while many files of it were tracked, so a new config file
  needed `git add -f`.
- The README lists the versions of the app images, the `mariadb` profile and
  the configurable suffix. It no longer lists the missing postgres client of
  the app images, because the images have `psql` now.

### Removed

- The legacy configs `config/php`, `config/supervisord.php8`,
  `config/supervisord.php81` and `config/supervisord.latest`. `PHP_VERSION`
  takes the numeric values of the public images.

### Fixed

- The postgres profile keeps its data. Its volume is at
  `/var/lib/postgresql/data`, the data path of the postgres image, not at
  `/var/lib/mysql` of the mysql containers. Before, postgres ignored the
  volume and lost the database with the container.
- The postgres container reads `config/postgres/postgresql.conf`, mounted at
  `/etc/postgresql` and given to the server with
  `postgres -c config_file=…`. Before, laserstack mounted the directory at
  `/etc/mysql/conf.d`, a path only the mysql containers read.
- `laser psql` works. The app images install the postgres client now, which
  brings `psql` and `pg_dump`. Before, the command failed with "executable
  file not found in $PATH".
- The container of the mariadb profile answers to the name `db` too, the name
  of the service of the mysql profile. Projects that use `db` as the database
  host work with both profiles.
- `laser mysql` uses the database container of the active profile, `mariadb`
  for the mariadb profile and `db` for the mysql profile. Before, it always
  used `db` and thus failed with the mariadb profile.
- `laser mysql` and `laser psql` pass their arguments to the client. Before,
  they pasted the arguments into a `bash -c` string, so a query with a space
  or a semicolon failed. `laser psql` sets `PGPASSWORD` with `docker compose
  exec -e` now.
- The `mysql` client of the app container connects to `mariadb` again. That
  container has no TLS, and the client of the images of PHP 8.2 and newer
  requires TLS by default: "SSL is required, but the server does not support
  it". `config/my.cnf` turns TLS off for the client. Before, only an
  interactive shell had this setting, from the `~/.my.cnf` that
  `/root/.bashrc` writes.
- PHP 8.0 now mounts the config directory `/etc/php8` of its image. Before,
  laserstack mounted `/etc/php80`, a path the image does not use. Thus the
  php.ini and the php-fpm pool config of laserstack were inert and php-fpm
  ran as `nobody` instead of `laser`.
- Supervisord renders the multi-project vhost into `/etc/nginx/sites-enabled`
  inside the container, not into the mounted `config/nginx/http.d`. Before,
  every `laser up` wrote a generated vhost into the config directory of the
  host. That file also stayed active and added a second default server.
- `multilaravel::config` does not write a vhost anymore. It wrote a second
  default server into the config directory of the host as well.
- The app image has `/etc/nginx/http.d/nginx-site.conf` with
  `listen 80 default_server`. The compose mount replaces the whole vhost
  directory of the image. Thus the multi-project vhost of laserstack is the
  only default server.
- `config/supervisord.8.2` now renders the multi-project vhost from the
  template, like all other versions. Before, 8.2 did not serve wildcard
  `*.<SUFFIX>` hosts.
- A vhost for a single project must not use `default_server` next to the
  multi-project vhost. Both cannot be the default server.

## [0.10.0] 2024-05-11

### Added

- the dns suffix is configurable in `.env`
- one config directory per PHP version, and php runs as the user who owns the
  mounted directories instead of nobody
- php 8.3

### Fixed

- config fixes

## [0.9.0] 2022-12-10

### Added

- memcached, as a profile

### Changed

- the twitter account is in the README

## [0.8.0] 2022-11-26

### Added

- php 7.4 and 8.2, with their config
- sqlite support

## [0.7.0] 2022-11-12

### Added

- postgresql 15.1 added
- PROFILES now allow a list of additional containers you want running.

## [0.6.0] 2022-11-11

### Fixed

- 8.1 configs are fixed
- laser scan now identifies custom, wordpress and laravel & symfony (based on the multiProject config).
- laser mysql now uses the root user to allow database management (create, drop, etc)
- std nginx config fixed to not fail on a cold startup
- updated env.example

## [0.5.2] 2021-12-04

### Fixed

- broken nginx config fixed
- supervisor now needs a particular config for each php version

## [0.5.1] 2021-12-04

### Fixed

- README.md update

## [0.5.0] 2021-12-04

### Added

- php version is now also configurable in `.env`. Current possible values are `php8`, `php81` and `latest` which points to `php8` for now.

- `db`, `redis` and `elasticsearch` now are optional, the only container which is always executed is app (which runs nginx and php-fpm). To control which optional container are used change `OPTS` in `.env` file.

- additional php extensions added, namely, php8-curl, php8-ctype and php8-zip

- stats - top-like docker stats added to laser

- .my.cnf is now built from environment variables in .bashrc

- supervisord has editable config on config/supervisord/supervisord.conf,
  now mounted.

### Changed

- app container is now downloaded by default. You can still build yourself if
  you want, just uncomment the build part for app container on
  docker-compose.yml file.

- Updated dockerfile for app image

## [0.1.0] 2021-02-15

### Fixed

- Typo fix on CHANGELOG itself. duh.

- Typo in Dockerfile, `laser build` is now fixed.

- laser mysql now accepts parameters so you can call `laser mysql yourdatabase`

- fixed supervisor install, now supervisorctl works correctly.

### Changed

- DB_USER environment variable renamed to DB_USERNAME to be consistent with
  default Laravel environment. Breaking change, update your local .env file.

### Added

- multiple subdomains are now allowed per project supporting multi-tenant
  Laravel apps.

- sudo now is installed in app

- laser shell script now has subcommand appexec which allows you to call any
  binary in the container

- Added support for wordpress, particular laravel nginx configs and a generic
  overridable config per project. Check README.md for details.

## [0.0.2] 2021-01-31

### Added

- GNU libiconv preload to avoid Alpine Linux iconv issues

- Changelog added (following keep a changelog format)

### Fixed

- Laser stack now will WARN when called in a directory not hosted

## [0.0.1] 2021-01-29

### Added

- Initial release
