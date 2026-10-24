# Laser Stack

## Introduction

Laser Stack is local Laravel development stack powered by docker like Laravel
Sail and multi-project like Valet. Aims to be small and fast. It's opinionated:
it does not support everything under the sun but it's configurable, you can
customize the container to suit your needs.

It supports macOS, WSL2, WSLg (Windows) and Linux and it needs docker.

Laser has a shell script around docker-compose as an interface to it, it exposes
all docker-compose commands and extends it with it's own subcommands.

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

- Currently we support Laravel, Symfony, Wordpress and overridable
  per project nginx config, those are examples, additional drivers PR's are
  welcome.
- DNS resolution needs to be manually managed through `/etc/hosts`.

## Versions

The app container is a public image per PHP series,
`laserstack/app:<major.minor>`. Each image runs the newest patch of its series
on the newest Alpine release that packages it:

| image  | PHP    | Alpine | node      | npm     | yarn    | nginx  |
| ------ | ------ | ------ | --------- | ------- | ------- | ------ |
| `7.4`  | 7.4.33 | 3.15   | v16.20.2  | 8.1.3   | 1.22.17 | 1.20.2 |
| `8.0`  | 8.0.30 | 3.16   | v16.20.2  | 8.10.0  | 1.22.19 | 1.22.1 |
| `8.1`  | 8.1.34 | 3.19   | v20.15.1  | 10.2.5  | 1.22.19 | 1.24.0 |
| `8.2`  | 8.2.35 | 3.22   | v22.23.4  | 11.6.4  | 1.22.22 | 1.28.3 |
| `8.3`  | 8.3.36 | 3.24   | v24.22.1  | 11.12.1 | 1.22.22 | 1.30.6 |
| `8.4`  | 8.4.27 | 3.24   | v24.22.1  | 11.12.1 | 1.22.22 | 1.30.6 |
| `8.5`  | 8.5.12 | 3.24   | v24.22.1  | 11.12.1 | 1.22.22 | 1.30.6 |

Every image has composer v2.10.3. The tag `latest` is the newest series. The
images are built in
[laserstack_app](https://github.com/sdbruder/laserstack_app).

The additional containers come from `docker-compose.yml`:

- MySQL `mysql:8.0`
- MariaDB `mariadb:10.11`
- PostgreSQL `postgres:15.1-alpine`
- redis `redis:alpine`
- memcached `memcached:alpine`
- Elasticsearch `elasticsearch:7.14.2`

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
`redis` containers. Set `PHP_VERSION` to 7.4, 8.0, 8.1, 8.2, 8.3, 8.4 or 8.5,
and `PROFILES` to the containers you want to run.

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

## PROFILES setup

`PROFILES` define a comma separated list of additional containers you want to run. Available containers:

- mysql
- mariadb
- postgres
- redis
- memcached
- elasticsearch

The database container of the mysql profile answers to the name `db`, the
container of the mariadb profile to the name `mariadb` and to `db` as well.
Projects that use `db` as the database host thus work with both profiles. Do
not activate the mysql and the mariadb profile at the same time, both use port
3306.

The postgres container keeps its data in the `pgdata` volume and reads
`config/postgres/postgresql.conf`. The container of the mysql profile reads
`config/db`.

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
`laser scan` to allow Laser Stack to adjust it's nginx config.

Laravel and Wordpress are simple examples of support drivers. Additional drivers
submitted as pull request are welcomed.

## DNS resolution

Add `.<SUFFIX>` names in your `/etc/hosts` so Laser Stack can identify which
project you are trying to access. `SUFFIX` comes from `.env` and is `local` in
`env.example`. For example for `projecta` and `projectb` (directory names):

```
127.0.0.1  projecta.local
127.0.0.1  projectb.local
```

You can add a dnsmasq config to resolve every `*.local` to 127.0.0.1
automatically, but that's beyond the scope of this introduction.

## Smoke test

`test/smoke.sh` starts the stack once per PHP version and checks nginx,
php-fpm, the php.ini of the repository, an http request, the command of the
active database profile, and that the run writes nothing into
`config/nginx/http.d`. The http check runs inside the container, so a web
server on port 80 of the host, like Valet or Herd, does not disturb the test.

```
test/smoke.sh             # every version
test/smoke.sh 8.4 8.5     # only these versions
```

The test stops the stack at the end and leaves `.env` as it was.

## License

Laser Stack is open-sourced software licensed under [BSD license](LICENSE.md).

## Social network

Follow us on Twitter as @laserstack_sdb: https://twitter.com/laserstack_sdb
