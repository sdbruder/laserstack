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

Currently it uses the following versions of software:
- PHP v8.2.0RC7, v8.1.13, v8.0.26 or v7.4.33
- MySQL v8.0.31
- PostgreSQL v15.1
- node v16.17.1
- npm v8.10.0
- yarn v1.22.19
- composer v2.4.4
- redis v7.0.5
- elasticsearch v7.14.2

## Getting started

Clone Laser Stack in the same directory which you store your Laravel projects (`~/src` for example):
```
git clone https://github.com/sdbruder/laserstack.git
```
Copy env.example to .env:
```
cp env.example .env
```
Edit your .env to your liking. By default it's using php 8.1 (7.4, 8.0, 8.1 or 8.2RC7) and
mysql 8.0 (mysql or postgreSQL).

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
- postgres
- redis
- elasticsearch

### PROFILES Examples

- app and mysql: `PROFILES=mysql`
- postgres and redis: `PROFILES=postgres,redis`
- mysql, redis and elastic: `PROFILES=mysql,redis, elasticsearch`

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

Add `.local` names in your `/etc/hosts` so Laser Stack can identify which project
you are trying to access. For example for `projecta` and `projectb` (directory names):
```
127.0.0.1  projecta.local
127.0.0.1  projectb.local
```
You can add a dnsmasq config to resolve every `*.local` to 127.0.0.1
automatically, but that's beyond the scope of this introduction.

## License

 Laser Stack is open-sourced software licensed under [BSD license](LICENSE.md).
