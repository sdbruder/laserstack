# Laser Stack

## Introduction

Laser Stack is local Laravel development stack powered by docker like Laravel
Sail and multi-project like Valet. Aims to be small and fast. It's opinionated:
it does not support everything under the sun but it's configurable, you can
customize the container to suit your needs.

It supports macOS, WSL2 (Windows) and Linux and it needs docker.

Laser has a shell script around docker-compose as an interface to it, it exposes
all docker-compose commands and extends it with it's own subcommands.

## Inspiration

Laser was inspired by [Laravel Sail](https://laravel.com/docs/8.x/sail) small footprint and [Valet](https://laravel.com/docs/8.x/valet)
multi-project capabilities.

## Goals / Design decisions

Be as small, simple and fast as possible:

- do not try to protect you from docker: if you try something that needs the stack up while it's down you will get the raw docker-compose error.
- simple and single shell script (`laser`) serve as an interface
- low number of containers: `app`, `db` and `redis`
- small containers: Almost all containers are Alpine Linux based
- simple build process, only a single container is built
- nginx-based http serving, faster than php-based solutions
- prebuilt public images for related services (database, redis and ngrok)

## Limitations

- Currently we only support only Laravel and Wordpress projects and overridable
  per project nginx config, those are examples, additional drivers PR's are
  welcome.
- DNS resolution needs to be manually managed through `/etc/hosts`.

## Versions

Currently it uses the following versions of software:
- PHP v8.0.2
- MySQL v8.0.22
- node v14.15.4
- npm v6.14.10
- composer v2.0.9
- redis v6.0.9
## Getting started

Clone Laser Stack in the same directory which you store your Laravel projects (`~/src` for example):
```
git clone https://github.com/sdbruder/laserstack.git
```
Copy env.example to .env:
```
cp env.example .env
```
Setup an alias or add laserstack directory to your path:
```
alias laser=~/src/laserstack/laser
# or add ~/src/laserstack/laser to your $PATH
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

## Other frameworks support

Out of the box Laser Stack supports multiple Laravel projects. There is
additional drivers supporting Wordpress and particular nginx configs.

To configure a particular nginx config for a project, create a
`.laserstack_nginx.conf` file in your project root directory and call
`laser scan`. Laser Stack will copy it as `YOURPROJECTDIR.conf`. in the app
your project will be in `/var/www/YOURPROJECTDIR`.

Every time you add or remove a non-Laravel project, you need to call
`laser scan` to allow Laser Stack to adjust it's nginx config.

Laravel and Wordpress are simple examples of support drivers. Additional drivers
submitted as pull request are welcomed.

## DNS resolution

Add `.test` names in your `/etc/hosts` so Laser Stack can identify which project you are trying to access. For example for `projecta` and `projectb` (directory names):
```
127.0.0.1  projecta.test
127.0.0.1  projectb.test
```
You can add a dnsmasq config to resolve every `*.test` to 127.0.0.1 automatically, but that's beyond the scope of this introduction.

## License

 Laser Stack is open-sourced software licensed under [BSD license](LICENSE.md).
