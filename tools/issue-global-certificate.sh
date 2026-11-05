#!/bin/bash
#
# Issue and publish the wildcard certificate of *.localdev.it: the one every
# Laser Stack install downloads, so that https works with a certificate that
# every browser already trusts and no machine has to trust anything.
#
# The private key of this certificate is public by design, the way the ones of
# local-ip.co and traefik.me are: the stack terminates TLS on the machine of the
# user, so the key has to be on that machine. That is also why the certificate
# carries only the catch-all name: it is the one name that covers every project
# of every user, and no project name of any user ever reaches a certificate
# transparency log. Note that *.localdev.it also covers www.localdev.it, the
# site; if that matters, serve the site from the apex and redirect www in DNS.
#
# Requirements:
#   - lego (https://github.com/go-acme/lego): one binary, DNS-01, which is the
#     only challenge that can issue a wildcard. certbot with its gcloud plugin
#     does the same job if you prefer it.
#   - a service account of the Cloud DNS zone of localdev.it with the role
#     roles/dns.admin, and the path of its JSON in GCE_SERVICE_ACCOUNT_FILE.
#
# Usage:
#   LEGO_EMAIL=you@example.com GCE_SERVICE_ACCOUNT_FILE=/path/sa.json \
#     ./tools/issue-global-certificate.sh            # renews when 30 days are left
#   ... --commit                                     # and publishes it
#
# Weekly from cron, on the machine that holds the credentials:
#   17 4 * * 1 cd /path/to/laserstack && LEGO_EMAIL=you@example.com \
#     GCE_SERVICE_ACCOUNT_FILE=/path/sa.json ./tools/issue-global-certificate.sh --commit
#
# Every install picks the new certificate up on its next laser tls, which also
# runs when the cached one is about to expire.
#
set -euo pipefail

laser_dir=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
cd "$laser_dir"

domain="localdev.it"
target="docs/tls"
: "${LEGO_EMAIL:?set LEGO_EMAIL to the address the certificate authority contacts}"
: "${GCE_SERVICE_ACCOUNT_FILE:?set GCE_SERVICE_ACCOUNT_FILE to the JSON of the DNS service account}"

if ! command -v lego >/dev/null 2>&1; then
  echo "lego is not installed: https://github.com/go-acme/lego#install" >&2
  exit 1
fi

mkdir -p "$target" config/tls/lego
lego --email "$LEGO_EMAIL" --dns gcloud --accept-tos \
  --path "$laser_dir/config/tls/lego" \
  --domains "*.$domain" \
  renew --days 30 ||
  lego --email "$LEGO_EMAIL" --dns gcloud --accept-tos \
    --path "$laser_dir/config/tls/lego" \
    --domains "*.$domain" run

install -m 644 "config/tls/lego/certificates/_.$domain.crt" "$target/fullchain.pem"
install -m 644 "config/tls/lego/certificates/_.$domain.key" "$target/privkey.pem"
echo "published: $target/fullchain.pem $target/privkey.pem"
openssl x509 -in "$target/fullchain.pem" -noout -subject -enddate -ext subjectAltName

if [ "${1:-}" == "--commit" ]; then
  git add "$target/fullchain.pem" "$target/privkey.pem"
  git commit -m "publish the wildcard certificate of *.$domain" || echo "nothing to commit"
  git push
fi
