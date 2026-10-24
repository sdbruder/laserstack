# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `config/php85` and `config/supervisord.8.5`, the config of the images of
  PHP 8.5.

### Changed

- `.gitignore` ignores only `.env` and the vhosts that laserstack and
  `laser scan` write into `config/nginx/http.d`. Before, it ignored the whole
  `config` directory while many files of it were tracked, so a new config file
  needed `git add -f`.
- The README lists the versions of the app images, the `mariadb` profile, the
  configurable suffix and the missing postgres client of the app images.

### Removed

- The legacy configs `config/php`, `config/supervisord.php8`,
  `config/supervisord.php81` and `config/supervisord.latest`. `PHP_VERSION`
  takes the numeric values of the public images.

### Fixed

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

## [0.8.0] 2024-05-11

### Added

- dns suffix now is configurable through .env
- config fixes
- fix php user to laser instead of nobody, this fixes files / directories ownership
- php 8.3 added
- memcached added

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

## Added

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
