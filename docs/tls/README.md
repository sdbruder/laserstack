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

The certificate is renewed and republished by the project itself, so an install
never has to. `laser tls` fetches whatever is published here, caches it in
`config/tls/serve/`, and refreshes that copy when it is within a month of its
end of life; `laser tls --global` forces the fetch.

If the published copy ever looks absent or expired, `laser tls` falls back to a
certificate authority of the machine, and `laser trust` puts that authority in
the trust store of the platform. How the project renews and publishes this
certificate is deliberately not described here: it is the part that is nobody
else's business.
