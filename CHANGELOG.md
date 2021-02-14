# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
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

## [0.0.2] 2021-01-31
### Added
- GNU libiconv preload to avoid Alpine Linux iconv issues

- Changelog added (following keep a changelog format)

### Fixed
- Laser stack now will WARN when called in a directory not hosted

## [0.0.1] 2021-01-29
### Added
- Initial release
