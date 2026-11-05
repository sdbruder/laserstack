# The published certificate of `*.localdev.it`

`fullchain.pem` and `privkey.pem` here are the certificate that every Laser Stack
install serves when `HTTPS=on` and the suffix is the default one
(`localdev.it`). They are fetched from
<https://localdev.it/laserstack/tls/> by `laser tls`, cached in
`config/tls/serve/`, and refreshed when the cached copy is within a month of its
end of life.

## The key here is public on purpose

The stack terminates TLS on the machine of the user, so the key has to be on that
machine, and a key that every user has is a key that everyone has. This is the
model of `local-ip.co` and `traefik.me`, and it is why the certificate carries
only the catch-all name: no project name of any user ever reaches a certificate
transparency log.

Two consequences worth knowing before you use it:

- **Anyone can answer as `*.localdev.it`** with a valid certificate. The name
  proves nothing about who is answering. In practice it resolves to `127.0.0.1`,
  so the answer comes from the machine itself, but do not treat a green padlock
  on these names as proof of anything.
- **`*.localdev.it` also covers `www.localdev.it`**, the site. If that matters,
  serve the site from the apex and redirect `www` in DNS.

## Renewing

`.github/workflows/publish-certificate.yml` renews it every Monday and publishes
the result: it installs lego, hands the credential of the provider that writes
the challenge record to `tools/issue-global-certificate.sh --commit`, and fails
the run when the certificate ends up within two weeks of its expiry, so a broken
renewal sends the mail a failed run sends. It also caches the store of the
account and the certificate, so a run renews only when 30 days are left instead
of issuing a new certificate every week. Start it by hand from the Actions tab
when you want it now, and tick `use_this_ref` there to test a change of the
script from a branch before it reaches the default branch.

The provider is the one the zone can be written through, and each one reads its
own credential. The run says so and stops while the credential is missing:

| setting | what it is |
|---|---|
| variable `LEGO_DNS` | optional: `gcloud` (the default) for a zone on Cloud DNS, `cloudflare` for a zone behind Cloudflare |
| secret `CF_DNS_API_TOKEN` | cloudflare: an API token with `Zone.DNS:Edit` on the zone |
| secret `CLOUD_DNS_SERVICE_ACCOUNT` | gcloud: the JSON of a service account of the zone with `roles/dns.admin` |
| variable `LETSENCRYPT_EMAIL` | the address the certificate authority contacts |
| variable `CLOUD_DNS_PROJECT` | gcloud, optional: the project of the zone, read from the service account when unset |
| variable `LEGO_RESOLVERS` | optional: the resolver the propagation check asks, `1.1.1.1:53` by default |
| variable `LEGO_VERSION` | optional, a lego release tag: the latest release is used when unset |

The zone of `localdev.it` is on Cloudflare, so the weekly run needs no manual
step. A registrar with no DNS API cannot be renewed from a workflow at all:
issue that certificate by hand, the script prints the record to add and waits
for an enter.

Without the workflow, `tools/issue-global-certificate.sh --commit` does the same
job by hand; put it in cron if you prefer. Each install refreshes its copy on the
next `laser tls`, and `laser tls --global` forces it.

