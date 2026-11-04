# Laser Stack

## Introduction

Laser Stack is local Laravel development stack powered by docker like Laravel
Sail and multi-project like Valet. Aims to be small and fast. It's opinionated:
it does not support everything under the sun but it's configurable, you can
customize the container to suit your needs.

It supports macOS (Intel and Apple silicon), Linux, WSL2 and WSLg (Windows) and
it needs docker with compose v2.

Install it next to your projects with one line, or clone it yourself (see
[Getting started](#getting-started)):

```
curl -fsSL https://localdev.it/laserstack/install | bash
```

Laser has a shell script around docker-compose as an interface to it, it exposes
all docker-compose commands and extends it with its own subcommands.

This file is the user documentation: installing the stack, configuring it and
running it. For the project itself, its test and its releases, read
[CONTRIBUTING.md](CONTRIBUTING.md).

The website is <https://localdev.it/laserstack/>: the same material in a
browsable form, with the measured numbers of the stack and copy-paste examples.

## Inspiration

Laser was inspired by [Laravel Sail](https://laravel.com/docs/8.x/sail) small footprint and [Valet](https://laravel.com/docs/8.x/valet)
multi-project capabilities.

## Goals / Design decisions

Be as small, simple and fast as possible:

- do not try to protect you from docker: if you try something that needs the stack up while it's down you will get the raw docker-compose error.
- simple and single shell script (`laser`) serve as an interface
- low number of containers: `app`, `db` and you can configure if you want `redis` and `elasticsearch`.
- small containers: Almost all containers are Alpine Linux based
- simple build process, only a single container is built
- nginx-based http serving, faster than php-based solutions
- prebuilt public images for related services (database, redis and ngrok)

## Limitations

- Currently we support Laravel, Symfony, Wordpress and overridable per project
  nginx config. Those drivers are examples, and
  [CONTRIBUTING.md](CONTRIBUTING.md) describes how to add one.
- DNS resolution needs to be manually managed through `/etc/hosts`.
- The app images have no `memcached` PHP extension (`php -m`), so the
  `memcached` profile serves the server only: PHP and Laravel cannot use it as a
  cache or a session store.
- The `mysql` client of a shell in the app container (`laser shell`,
  `laser appexec mysql`) is the client of the image and authenticates with
  `config/my.cnf`. It works with the mariadb profile and with mysql `8.0`. The
  app images do not carry the `caching_sha2_password` plugin of that client, so
  it cannot authenticate an account of mysql `8.4`, `9.7` or `26.10`; use
  `laser mysql` there, the client of the database container.

## Versions

The app container is a public image per PHP series,
`laserstack/app:<major.minor>`. Each image runs the newest patch of its series
on the newest Alpine release that packages it:

| image  | PHP      | Alpine | node      | npm     | yarn    | nginx  | phpunit | xdebug       |
| ------ | -------- | ------ | --------- | ------- | ------- | ------ | ------- | ------------ |
| `7.4`  | 7.4.33   | 3.15   | v16.20.2  | 8.1.3   | 1.22.17 | 1.20.2 | 9.6.38  | 3.1.4        |
| `8.0`  | 8.0.30   | 3.16   | v16.20.2  | 8.10.0  | 1.22.19 | 1.22.1 | 9.6.38  | 3.1.6        |
| `8.1`  | 8.1.34   | 3.19   | v20.15.1  | 10.2.5  | 1.22.19 | 1.24.0 | 10.5.66 | 3.3.2        |
| `8.2`  | 8.2.35   | 3.22   | v22.23.4  | 11.6.4  | 1.22.22 | 1.28.3 | 11.5.57 | 3.4.6        |
| `8.3`  | 8.3.36   | 3.24   | v24.22.1  | 11.12.1 | 1.22.22 | 1.30.6 | 12.5.42 | 3.5.3        |
| `8.4`  | 8.4.27   | 3.24   | v24.22.1  | 11.12.1 | 1.22.22 | 1.30.6 | 13.4.5  | 3.5.3        |
| `8.5`  | 8.5.12   | 3.24   | v24.22.1  | 11.12.1 | 1.22.22 | 1.30.6 | 13.4.5  | 3.5.3        |
| `8.6`  | 8.6.0RC5 | edge   | v24.22.1  | 12.0.2  | 1.22.22 | 1.30.6 | 13.4.6  | 3.6.0alpha1  |

Every image has composer 2.11.1, the mysql client and the postgres client
(`psql`, `pg_dump`). `laser psql` uses the postgres client of the app container;
`laser mysql` runs in the database container, see the Versions table. Under
supervisord each image runs nginx (which serves the projects) and php-fpm. The
images are built from the Dockerfiles in
[laserstack_app](https://github.com/sdbruder/laserstack_app).

The tag `latest` is the newest released series, currently `8.5`. The `8.6`
series has no stable release yet (GA is planned for 19 November 2026), so its
image is a release candidate (PHP 8.6.0RC5, Alpine `edge`) and does not take
`latest`. Every other image runs on the newest Alpine release that packages its
series.

The additional containers come from `docker-compose.yml`. Each engine has one
version variable that selects the image tag and the config directory
`config/<engine>/<version>`:

| engine        | variable                | default                | other versions                    | config directory                                   |
| ------------- | ----------------------- | ---------------------- | --------------------------------- | -------------------------------------------------- |
| MySQL         | `MYSQL_VERSION`         | `mysql:8.0`            | `8.4`, `9.7`, `26.10`             | `config/mysql/<version>/`                          |
| MariaDB       | `MARIADB_VERSION`       | `mariadb:10.11`        | `11.4`, `11.8`, `12.3`, `13.0`    | `config/mariadb/<version>/laserstack.cnf`          |
| PostgreSQL    | `POSTGRES_VERSION`      | `postgres:15.1-alpine` | `16`, `17`, `18`                  | `config/postgres/<version>/`                       |
| redis         | `REDIS_VERSION`         | `redis:8.10-alpine`    | `8.8`, `8.6`, `8.4`, `8.2`, `7.4` | `config/redis/<version>/redis.conf`                |
| memcached     | `MEMCACHED_VERSION`     | `memcached:1.6-alpine` | none                              | none, the image has no config file                 |
| Elasticsearch | `ELASTICSEARCH_VERSION` | `elasticsearch:7.14.2` | `8.19.23`, `9.5.5`                | `config/elasticsearch/<version>/elasticsearch.yml` |

A data volume belongs to the server version that created it, so a version change
needs `laser down -v` (or the server upgrade of that engine) before `laser up`.
The accounts of MySQL `8.4`, `9.7` and `26.10` use `caching_sha2_password`
(MySQL 9.0 removed `mysql_native_password`), which is why `laser mysql` runs the
client of the database container, not the client of the app container. The
postgres service pins `PGDATA=/var/lib/postgresql/data`: the images from
postgres 18 store their data in `/var/lib/postgresql/<major>/docker` by default
and refuse to start when a volume sits at the older path.

## Getting started

Clone Laser Stack in the same directory which you store your Laravel projects (`~/src` for example):

```
git clone https://github.com/sdbruder/laserstack.git
```

Copy env.example to .env:

```
cp env.example .env
```

Edit your .env to your liking. `env.example` uses PHP 8.4 and the `mysql` and
`redis` containers. Set `PHP_VERSION` to 7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 or
8.6, and `PROFILES` to the containers you want to run.

The version of every database server is selectable with the variables
`MYSQL_VERSION`, `MARIADB_VERSION`, `POSTGRES_VERSION`, `REDIS_VERSION`,
`MEMCACHED_VERSION` and `ELASTICSEARCH_VERSION`. They are optional: without them
`docker-compose.yml` uses the defaults of the Versions table above.

Define also the usernames and passwords for mysql por postgresql and which
containers you want to run defining the `PROFILES` variable.

Setup an alias or add laserstack directory to your path:

```
# alias setup
alias laser=~/src/laserstack/laser
# or add ~/src/laserstack/laser to your $PATH in your ~/.bashrc or ~/.zshrc:
export PATH=$PATH:~/src/laserstack
```

Now you can start your dev stack:

```
laser up -d
```

And to get a shell in a particular project:

```
cd ../myproject
laser shell
```

To stop it:

```
laser stop
```

To look additional laser commands:

```
laser help
```

## Staying up to date

The app images are rebuilt every night in
[laserstack_app](https://github.com/sdbruder/laserstack_app): the tag of a PHP
series always carries the newest patch of that series, so a running stack can
take a patch release without changing anything else.

```
laser update --check    # fetch the code and the images, change nothing
laser update            # the same, then restart what changed
```

`laser update` fast-forwards the checkout (an edit of yours to a tracked file
stops that, on purpose), pulls the images of the active profiles, prints the PHP
version of the image next to the one the container runs, and restarts only the
containers whose image changed. A new PHP *series* is the one manual step: a
version directory in laserstack_app plus `config/php<VV>` and
`config/supervisord.<VV>` here, which
[CONTRIBUTING.md](CONTRIBUTING.md) describes.

## PROFILES setup

`PROFILES` define a comma separated list of additional containers you want to
run. The available profiles, each with the image `docker-compose.yml` pulls:

- mysql (`mysql:${MYSQL_VERSION}`, default `mysql:8.0`)
- mariadb (`mariadb:${MARIADB_VERSION}`, default `mariadb:10.11`)
- postgres (`postgres:${POSTGRES_VERSION}-alpine`, default `postgres:15.1-alpine`)
- redis (`redis:${REDIS_VERSION}-alpine`, default `redis:8.10-alpine`)
- memcached (`memcached:${MEMCACHED_VERSION}-alpine`, default `memcached:1.6-alpine`)
- elasticsearch (`elasticsearch:${ELASTICSEARCH_VERSION}`, default `elasticsearch:7.14.2`)

The database container of the mysql profile answers to the name `db`, the
container of the mariadb profile to the name `mariadb` and to `db` as well.
Projects that use `db` as the database host thus work with both profiles. Do
not activate the mysql and the mariadb profile at the same time, both use port
3306.

The postgres container keeps its data in the `pgdata` volume and reads the
config directory of its version, `config/postgres/<version>/`. The container of
the mysql profile reads `config/mysql/<version>/`, the container of the mariadb
profile reads `config/mariadb/<version>/laserstack.cnf`, redis reads
`config/redis/<version>/redis.conf` and elasticsearch
`config/elasticsearch/<version>/elasticsearch.yml`. memcached has no config
file, its image takes the settings as command flags.

### PROFILES Examples

- app and mysql: `PROFILES=mysql`
- app and mariadb: `PROFILES=mariadb`
- app and postgres: `PROFILES=postgres`
- postgres and redis: `PROFILES=postgres,redis`
- mysql, redis and elastic: `PROFILES=mysql,redis,elasticsearch`
- mysql and memcached: `PROFILES=mysql,memcached`

## Other frameworks support

Out of the box Laser Stack supports multiple Laravel projects. There is
additional drivers supporting Wordpress and particular nginx configs.

To configure a particular nginx config for a project, create a
`laserstack-nginx.conf` file in your project root directory and call
`laser scan`. Laser Stack will copy it as `YOURPROJECTDIRECTORY.conf`. in the app
your project will be in `/var/www/YOURPROJECTDIRECTORY`.

Every time you add or remove a non-Laravel project, you need to call
`laser scan` to allow Laser Stack to adjust its nginx config.

## DNS resolution

Nothing to do: `env.example` defaults `SUFFIX` to `localdev.it`, and every name
under that domain resolves to `127.0.0.1` and `::1` for anyone. So every project
of the projects directory answers as `projecta.localdev.it` on the machine that
runs the stack. No `/etc/hosts`, no dnsmasq, nothing installed. The notes behind
that domain are at <https://localdev.it/catch-all-dns.html>.

With a suffix of your own: add `.<SUFFIX>` names in your `/etc/hosts` so Laser
Stack can identify which project you are trying to access. `SUFFIX` comes from
`.env`. For example for `projecta` and `projectb` (directory names):

```
127.0.0.1  projecta.local
127.0.0.1  projectb.local
```

You can add a dnsmasq config to resolve every `*.local` to 127.0.0.1
automatically, but that's beyond the scope of this introduction.

## Contributing

The development documentation lives in [CONTRIBUTING.md](CONTRIBUTING.md): the
layout of the repository, how the stack is put together, how to add a PHP or a
database version, the smoke test, the release process and how to debug a
container.

## License

Laser Stack is open-sourced software licensed under [BSD license](LICENSE.md).

## Social network

Follow us on Twitter as @laserstack_sdb: https://twitter.com/laserstack_sdb
