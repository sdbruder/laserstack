# Working on Laser Stack

This is the documentation for the people who build and maintain Laser Stack:
what the pieces are, how to add a version, how to test it and how to cut a
release. The documentation for *using* the stack is in the
[README](README.md).

## Repository layout

```
docker-compose.yml    the app service and one service per database profile
docker-compose.https.yml  the overlay laser adds when HTTPS=on: port 443 and the certificate
tools/issue-global-certificate.sh  issues and publishes the certificate of *.localdev.it
.github/workflows/    the scheduled job that renews that certificate
laser                 the shell script around docker-compose, the user interface
public/index.php      the dashboard, served by the stack as one more project
env.example           the documented .env; laser copies it when .env is absent
config/               the config of every image version, mounted per service
  php<VV>/            php.ini, php-fpm.conf and php-fpm.d of one PHP series
  supervisord.<VV>/   supervisord.conf of one PHP series
  nginx/              nginx.conf and the vhosts of the app container
  my.cnf              the client config of a shell in the app container
  <engine>/<version>/ the config of one database version, one directory each
  tls/                written by laser tls and not tracked: the local CA and the certificate
docs/tls/             the published certificate of *.localdev.it, fetched by laser tls
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

The nightly workflow of
[laserstack_app](https://github.com/sdbruder/laserstack_app) rebuilds every
series that has a version directory: for each one it installs the series from
the Alpine release of that image, reads back the version it got, and publishes
two tags — the series (`8.4`) and the exact patch (`8.4.27`), for amd64 and
arm64. So patch releases of an existing series come by themselves, and only the
first image of a *new* series is work.

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
   for redis and `laser appexec curl -sS http://elasticsearch:9200` for
   elasticsearch. The app images have no `Memcached` class, so probe memcached
   with its protocol: `printf 'version\r\n' | nc 127.0.0.1 11211` on the host.

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
  repository, a project answers over http with the requested version, the
  dashboard of the checkout answers on `laserstack.<SUFFIX>`, lists the projects
  directory and reports the code the project answered with, and the run writes
  nothing into `config/nginx/http.d`;
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
runs that version against its own data volume, so the test never removes a volume
and the data of the other profiles survives the run.

The test stops the stack at the end and leaves `.env` as it was. The database
volumes stay, and the first run pulls the images of the database profiles.

redis, memcached and elasticsearch have no stage in the test: start the profile
and probe it by hand, see [Add a database version](#add-a-database-version).

A sweep over every supported server version is a loop around the test, driven by
the config directories, so no version list has to be kept in sync:

```
for dir in config/mysql/*/; do
  SMOKE_MYSQL_VERSION="$(basename "$dir")" SMOKE_DB_PROFILES=mysql test/smoke.sh 8.5 || break
done
for dir in config/mariadb/*/; do
  SMOKE_MARIADB_VERSION="$(basename "$dir")" SMOKE_DB_PROFILES=mariadb test/smoke.sh 8.5 || break
done
for dir in config/postgres/*/; do
  SMOKE_POSTGRES_VERSION="$(basename "$dir")" SMOKE_DB_PROFILES=postgres test/smoke.sh 8.5 || break
done
```

`|| break` stops at the first version that fails, and the test prints the names
of the failed checks with the report of that run.

Neither the sweep nor a single run starts from a clean stack: `laser down` stops
the containers of the profiles of the active `.env` only, so a container of
another profile that is still up keeps its host ports *and* its `db` alias, and
the app container then reaches that server instead of the one under test. Stop
your own stack (`laser down` with your `.env`) before a run with another profile,
and look at `laser ps` when a result looks wrong.

The test proves the PDO path of the app container. A check of a real framework
setup is a command in a project of the projects directory, the way the version
selection was checked against a Laravel 12 application:

```
laser appexec bash -c "cd /var/www/<project> && DB_CONNECTION=mysql DB_HOST=db \
  DB_PORT=3306 DB_DATABASE=laser DB_USERNAME=laser DB_PASSWORD=<password> \
  php artisan db:show"
```

Override every variable of that connection: Laravel merges the shell environment
over the `.env` of the project one variable at a time, so a variable that is not
overridden keeps the value of the project, and a cached configuration
(`bootstrap/cache/config.php`) ignores the overrides altogether.

## The dashboard

`public/index.php` is the dashboard, and it is also one of the projects the stack
serves: the multi-project vhost reaches it through `public/index.php`, so it needs
no vhost of its own, no container and no framework — one file and the standard
library of PHP. Its rules:

- it writes nothing, runs no command and prints no credential: a shell or a
  command in it would make it a remote control, not a status page;
- every card answers a question about *now*: the PHP of the container, the
  projects of the projects directory, the services of the active profiles, the
  version directories of `config/`;
- a tile is the link, the driver `laser scan` identifies (green), the code the
  front page of the project answered with (green from 200 to 399, red from 400
  up, grey `no answer` when nothing answered within a second) and the flags the
  driver does not already describe: `no public/` when no driver claims the project
  and it has no `public/` directory, `own vhost` when laserstack serves it through
  a vhost of its own;
- it asks each servable project for its front page: one HEAD request per project,
  in parallel with `curl_multi`, capped at 0.8 s, which is why the page reloads
  itself every thirty seconds by default and not every ten;
- the container resolves no `*.<SUFFIX>` name — the resolver of the suffix lives
  on the host — so the probe sends the request to the nginx of the container on
  `127.0.0.1` and the `Host` header picks the vhost, the way `test/smoke.sh`
  fetches the page;
- the probe sends `X-Laserstack-Probe: 1`, and a render that sees that header asks
  nobody. Keep that guard: the dashboard is one of the projects, so a probe of
  itself renders the page again, and without the header those renders fan out
  until php-fpm runs out of workers (the symptom is FastCGI hanging while static
  files still answer; `docker restart laserstack-app-1` clears it);
- `laser dashboard` opens the page in the browser of the machine.

A new laser subcommand is a function in `laser`, a line in `lasercommands()` and a
case in the dispatch at the end of the file, as `dashboard` shows. The user-facing
description lives in `README.md` (`## The dashboard`, `## Other frameworks
support`) and in `docs/features.html`.

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
- a change of the version of a database switches to the data volume of that
  version (`<project>_<engine>data_<version>`), so nothing else has to be reset;
- there is no validation layer. A path that the version does not have, an image
  tag that does not exist, or a variable in a config file that the server does
  not know all end as the raw docker or server error, and that error is the
  message to work from.

## TODO

Two abilities the stack does not have yet. Both need a plan that decides the
mechanism before any code.

### Several PHP versions and database servers at the same time

Laser Stack serves many projects from *one* stack: one `app` container of the
`PHP_VERSION` of `.env`, one server per database engine, one set of credentials.
Two projects that need different versions therefore cannot run at the same time,
and one stack per project is not the answer either.

Goal: as many PHP versions and database servers in parallel as the projects
need, and no more, with the smallest number of containers. Every container
serves all the projects that need the same thing: one app container per PHP
version, one container per database engine *and* version (mysql 8.0 next to
mysql 9.7, on different host ports), and each project states which of them it
uses.

Proposed direction for that work (a proposal, the plan still decides the
details):

- a `router`: one `nginx:alpine` that publishes port 80 and is the only
  container that does. Its config is generated, one server per project, and it
  sends `Host: <project>.<SUFFIX>` to the app container of the version of that
  project. It is the only new piece;
- `app<VV>`: one container per PHP version in use, the image of today
  (`laserstack/app:8.2`, `:8.5`) unchanged, with the same supervisord and the
  same vhost rendering. `laser` starts the versions the mapping asks for, so a
  version nobody needs never runs;
- the mapping project → versions: `.laserstack` in the project root, a
  `KEY=VALUE` file sourced like `.env` (`PHP_VERSION=8.4`, later
  `MYSQL_VERSION=9.7`), written by `laser use php 8.4` and read by `laser scan`.
  It resolves as that file, then `composer.json` (`require.php` as a floor),
  then the `PHP_VERSION` of the stack `.env`, so a setup without a mapping keeps
  behaving as today;
- the subcommands of a project (`artisan`, `php`, `composer`, `npm`, `shell`,
  `appexec`, `test`, `mysql`, `psql`) pick their container through a helper
  `appservice()` next to the existing `dbhost()`; `laser share` points at the
  router and `laser list` shows the version of every project;
- the databases follow the same shape: one service per engine and version, named
  by the mapping. A shared server needs isolation by database and user, so a
  project gets its own database and user (an idempotent provisioning step), and
  `db` stays the alias of the default.

Costs to accept and document: extensions, opcache and xdebug stay properties of a
version and not of a project; an idle version costs tens of megabytes; the
hostname inside a container stops being `laser`; and the number of containers is
one router plus one app per version in use plus the database services, whatever
the number of projects.

Prior art to read before the plan: VVV does this in one box with an nginx
upstream per site and a php-fpm pool per version; Valet and Herd put the version
per site on the host; ddev, Lando and Sail go the other way and give every
project its own set of containers.

The path to it, in this order:

1. the mapping file, `laser use php` and `appservice()`, with the mapping inert
   while there is one app container;
2. one `app<VV>` service per PHP version behind its profile, plus the router;
3. `laser scan` generates the router config, and `laser share` follows it;
4. per-project database and user provisioning, and the database versions in the
   mapping;
5. the smoke test over combinations of versions;
6. optionally, one `web` container with one php-fpm container per version
   instead of one nginx per version: the same number of containers, less work
   inside the containers, more work in the images.

Still to decide in the plan of that work:

- the name and the format of the mapping file, and whether the `composer.json`
  fallback is worth its surprises;
- the router: plain `nginx:alpine` with a generated config, or an image of this
  project that carries its template;
- whether an app container keeps a published port for direct access
  (`http://localhost:8082`) or only the router publishes one;
- what `hostname: laser` becomes, and what the tools that read it should do;
- the order against the DNS TODO: the router does not need that work to happen
  first, but the two together are what makes many projects on many versions
  comfortable.

### Local DNS for the project names

`<project>.<SUFFIX>` resolves through `/etc/hosts` entries that the user writes
and keeps, and `SUFFIX` is a setting of `.env`. That contradicts the idea that
`laser` owns the local stack, and it is the setup step users get wrong.

Goal: `laser` knows `SUFFIX` and every project of the projects directory, so it
should set the resolution up by itself on macOS, Linux and WSL2: install what it
needs, write the configuration, start it, and keep it in step with `laser scan`.

Decided: `dnsmasq`, for a suffix of the user's own. `.test` is the candidate
there; the default of `env.example`, `localdev.it`, needs no daemon at all.

- `dnsmasq` resolves the whole suffix as a wildcard, so every current and future
  project name works without a per-project step, which a generated block of
  `/etc/hosts` cannot do. It is what Valet and Herd do. On macOS it needs one
  file per suffix in `/etc/resolver/`, on Linux the resolver of the distribution
  (`systemd-resolved`, `NetworkManager`) or `/etc/resolv.conf`, and on WSL2 the
  path that the plan decides.
- `.test` is the TLD that RFC 6761 reserves for tests: it resolves nowhere on
  the internet and no client claims it, while `local` belongs to mDNS/Bonjour and
  fights `mDNSResponder` on macOS and Windows, and `.app` and `.dev` are real
  TLDs served over https. `SUFFIX` stays a setting; the default of `env.example`
  is `localdev.it`, which needs no daemon at all, so `.test` is the candidate for
  a user who wants a suffix of their own.

Worth saying before that plan: the domain `localdev.it` already gives this
without a daemon. Every name under it — any depth, IPv4 and IPv6 — resolves to
loopback for anyone, so `SUFFIX=localdev.it` needs none of the work below. It is
the default of `env.example` now, which reduces this item to a convenience: what
remains is for a user who wants a suffix of their own.

Still to decide in the plan of that work:

- the privileges: which step needs `sudo` (the package, the service, the
  resolver file), how to ask for it once, and what `laser` does when the user
  says no;
- the WSL2 path: the generated `/etc/hosts` of WSL, systemd inside WSL, or
  dnsmasq on the Windows side, and what happens on a WSL that starts without
  systemd;
- the fallback without a daemon: a generated block of `/etc/hosts` between
  markers, owned by `laser scan`, for the machines where a root service is not
  wanted;
- the footprint: what the stack leaves on the machine (the `dnsmasq` package,
  the service, `/etc/resolver/test`), how `laser` reports it and how it removes
  it again;
- `*.localhost` stays out of the mechanism: only some clients resolve it, so it
  can be an extra suffix for a user who wants no setup at all, never the default.
