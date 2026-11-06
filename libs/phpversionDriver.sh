#!/bin/bash

# The vhost of a project that asks for a PHP version other than the one of the
# app container. `laser scan` renders it into config/nginx/http.d, which is
# mounted into the app container, and removes it again when the marker goes
# away: without a marker the multi-project vhost serves the project, as it
# always did, from the php-fpm of the app container.
#
# The marker is a file of the project, so it is read and never sourced: a
# project file must not be able to run code during a scan.

function phpversion::marker() {
  # phpversion::marker <project path>: the PHP version the project asks for,
  # empty when it asks for none
  awk -F= '/^PHP_VERSION=/{print $2}' "${1:-.}/.laserstack" 2>/dev/null || true
}

function phpversion::config() {
  local project_path=${1:-.} project version upstream rendered https_rendered
  project=$(basename "$project_path")
  rendered="config/nginx/http.d/$project.conf"
  https_rendered="config/nginx/http.d/$project-https.conf"
  version=$(phpversion::marker "$project_path")
  # no marker, or the version of the stack itself: the multi-project vhost of
  # the app container serves the project, and a file of an earlier marker goes
  # away again. Only a file this driver wrote is removed: the directory belongs
  # to the scan, not to this driver alone, and the vhost of another driver sits
  # in the same place.
  if [ -z "$version" ] || [ "$version" == "$PHP_VERSION" ]; then
    phpversion::remove "$rendered" "$https_rendered"
    return 0
  fi

  # a project that ships its own nginx config decides the upstream itself, that
  # is the documented override. The marker is not ignored: it selects the
  # container of laser php, laser artisan and the like.
  if [ -f "$project_path/laserstack-nginx.conf" ]; then
    echoerr "SCAN: $project ships laserstack-nginx.conf and asks for PHP $version: its nginx config decides the upstream, the marker selects the container of the CLI commands"
    phpversion::remove "$rendered" "$https_rendered"
    return 0
  fi

  if [ ! -d "config/php$(phpseries_dir "$version")" ]; then
    echoerr "SCAN: $project asks for PHP $version, which has no config directory: its requests fail with an unknown upstream"
  fi
  case ",${PROFILES:-}," in
  *",$(phpservice_name "$version"),"*) ;;
  *)
    echoerr "SCAN: $project asks for PHP $version: add $(phpservice_name "$version") to PROFILES in .env, or its requests fail with an unknown upstream"
    ;;
  esac

  upstream="$(phpservice_name "$version"):9000"
  sed -e "s/__PROJECT__/$project/g" \
    -e "s/__SUFFIX__/${SUFFIX:-localdev.it}/g" \
    -e "s/__UPSTREAM__/$upstream/g" \
    "config/nginx/http.d/phpVersionVhost.conf.template" |
    phpversion::stamp "$project" >"$rendered"
  if [ "${HTTPS:-off}" == "on" ]; then
    sed -e "s/__PROJECT__/$project/g" \
      -e "s/__SUFFIX__/${SUFFIX:-localdev.it}/g" \
      -e "s/__UPSTREAM__/$upstream/g" \
      "config/nginx/http.d/phpVersionVhostHttps.conf.template" |
      phpversion::stamp "$project" >"$https_rendered"
  else
    phpversion::remove "$https_rendered"
  fi
}

# The first line of every file this driver renders. The scan writes *for* a
# project, it does not own the directory: the vhost of another driver, or one a
# user wrote here by hand, is never touched.
phpversion_stamp='# rendered by laser scan for '

function phpversion::stamp() {
  printf '%s%s: do not edit, the .laserstack of the project decides\n' "$phpversion_stamp" "$1"
  cat
}

# phpversion::remove <file>...: remove the ones this driver wrote. A file is
# ours when its first line is the stamp.
function phpversion::remove() {
  local file first
  for file in "$@"; do
    [ -f "$file" ] || continue
    read -r first <"$file" || true
    case "${first:-}" in
    "$phpversion_stamp"*) rm -f "$file" ;;
    esac
  done
  return 0
}

function phpversion::forget() {
  # phpversion::forget <projects directory>: the vhosts this driver rendered for
  # projects that are not there any more
  local projects_dir=${1:-.} file first project
  for file in config/nginx/http.d/*.conf; do
    [ -f "$file" ] || continue
    read -r first <"$file" || true
    case "${first:-}" in
    "$phpversion_stamp"*) ;;
    *) continue ;;
    esac
    project=${first#"$phpversion_stamp"}
    project=${project%%:*}
    if [ ! -d "$projects_dir/$project" ]; then
      echoerr "SCAN: $project is gone, its vhost goes with it"
      rm -f "$file"
    fi
  done
  return 0
}
