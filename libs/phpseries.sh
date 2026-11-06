#!/bin/bash
# The names a PHP version has in this repository. Alpine and the image do not
# spell them the same way for the two oldest series:
#
#   version   config dir         package dir        service
#   7.4       config/php74       /etc/php7          php74
#   8.0       config/php8        /etc/php8          php80
#   8.5       config/php85       /etc/php85         php85
#
# The config dir and the package dir are the names the mounts of the stack use,
# the service is the name of the container that serves the version: the app
# container for the version of .env, a worker container for every other version
# a project asks for.

# the directory under config/, and the package directory of the image
function phpseries_dir() {
  case "${1:-}" in
  8.0) echo 8 ;;
  *) echo "${1:-}" | tr -d '.' ;;
  esac
}

# the package directory of the image: Alpine calls 7.4 "php7" and 8.0 "php8"
function phpalpine_dir() {
  case "${1:-}" in
  7.4) echo 7 ;;
  8.0) echo 8 ;;
  *) echo "${1:-}" | tr -d '.' ;;
  esac
}

# the name of the service that serves a version
function phpservice_name() {
  echo "php$(echo "${1:-}" | tr -d '.')"
}
