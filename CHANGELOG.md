# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
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
