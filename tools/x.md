# Posting on X as @laserstackphp

`tools/x` posts, replies and reads on X through
[twitter-cli](https://github.com/jackwener/twitter-cli), authenticated with the
session cookie of @laserstackphp.

The whole record of the account is one private text file, **`~/.laserstack-x`**,
mode 600:

| Line | Meaning |
|---|---|
| `handle` | `laserstackphp` |
| `email` | `laserstack@bruder.com.br`, a Workspace alias that delivers to the main inbox |
| `password` | written after signup |
| `totp_secret` | the two-factor seed, if the authenticator app shows it |
| `recovery_codes` | the one-time codes X prints when two-factor is turned on |
| `TWITTER_AUTH_TOKEN`, `TWITTER_CT0` | the session cookie; the only two lines `tools/x` reads |

Plain text is a stopgap, not the goal: a password manager is better. A
documented file on your own disk still beats a password nobody wrote down —
@laserstack_sdb was lost exactly that way. Two rules keep it useful: mode 600,
and a copy somewhere you control that is not a synced folder you do not own. It
holds the only copy of the password and of the two-factor seed.

## Do not deploy the site before the account exists

The site and the README already name @laserstackphp. Until the handle resolves,
the Community footer of every page links a 404 profile. Create the account
first, then redeploy the site.

## Why not the official API

X removed the free API tier on 2026-02-06. Access is pay per use, from prepaid
credits in the Developer Console:

| Action | Price |
|---|---|
| Post | $0.015 |
| Post with a link | $0.200 |
| Read one post | $0.005 |

The link surcharge is 13 times the price of a plain post, and most posts of this
project carry a link: 300 link posts a month cost $60. `twitter-cli` sends the
same GraphQL requests as the web app, with the cookie of the account, so a post
costs nothing.

## Risk

Automating a web session is against the X terms of service. X can rate-limit,
lock or suspend the account. That is why the project has its own handle: the
damage stops at @laserstackphp and never reaches the personal account.

Keep the account within human behavior: a few posts, no bulk follow or unfollow,
no direct messages, no bursts. An unverified account may create about 50 posts
and 200 replies a day, inside a 30-minute burst window that X does not publish.

The cookie is a password. `auth_token` gives full control of the account until
that session ends.

## Create the account, once

1. In Chrome, open the profile menu, choose **Add**, and make a profile named
   `laserstackphp`. Sign in to x.com as this account only, in that profile.
2. Write a long random password into `~/.laserstack-x` first, on an uncommented
   `password=` line. Copy it from there into the signup form, so the file is the
   source of truth from the first second.
3. Sign up at <https://x.com/i/flow/signup> with `laserstack@bruder.com.br`.
4. Click the verification link that arrives at the alias.
5. Two-factor: **Settings** → **Security and account access** → **Security** →
   **Two-factor authentication** → **Authentication app**. Do not choose SMS:
   the phone number is the part that goes stale. If the setup shows the seed,
   write it on `totp_secret=`.
6. **Settings** → **Two-factor authentication** → **Recovery code**. Write the
   codes on `recovery_codes=`.

## Store the cookie, once

1. In that browser, open <https://x.com>, then DevTools (⌥⌘I) → **Application** →
   **Cookies** → `https://x.com`.
2. Copy the values of `auth_token` and `ct0` into the two lines of
   `~/.laserstack-x`, after the `=` and nothing else. No quotes, no spaces.
3. Check both, then the account:

   ```sh
   grep -c '^TWITTER_.*=..' ~/.laserstack-x   # must print 2
   tools/x whoami                             # must print @laserstackphp
   ```

`tools/x` reads the file by name, not as a shell script, so a value may contain
`#`, quotes or spaces without breaking it.

## Install, once

```sh
uv tool install twitter-cli
```

Run `uv tool upgrade twitter-cli` when a request starts to fail: X changes the
web app often, and the tool follows it.

## Use

```sh
tools/x whoami                          # must print @laserstackphp
tools/x post "Laser Stack 2.0 is out"    # a post
tools/x post "text" -i docs/og.png       # with an image, up to four
tools/x reply <tweet-id> "text"
tools/x quote <tweet-id> "text"
tools/x delete <tweet-id>
tools/x feed --max 20                    # home timeline of that account
tools/x user-posts laserstackphp --max 20
tools/x search "laserstack" -t Latest
```

Add `--json` or `--yaml` for scripts. `twitter --help` lists every command;
`tools/x` passes all of them through.

`tools/x` takes the cookie from `TWITTER_AUTH_TOKEN` and `TWITTER_CT0` in the
environment when they are set, and from `~/.laserstack-x` otherwise. When
neither answers, it stops instead of letting `twitter-cli` extract the cookies
of whichever browser it finds.

## When it breaks

| Message | Cause | Fix |
|---|---|---|
| `Cookie expired or invalid (HTTP 401)` | the session ended | repeat **Store the cookie** |
| `Couldn't get KEY_BYTE indices`, or a transaction-id error | X changed its web app | `uv tool upgrade twitter-cli` |
| `no usable cookie in ~/.laserstack-x` | a line is empty, or the value has stray quotes | re-copy both values |
| a post gone out from the wrong account | never possible here: the cookie names the account | `tools/x whoami` |

## If the account is lost again

1. **Password**: <https://x.com/i/flow/password_reset>, enter `laserstackphp`,
   use the link that arrives at `laserstack@bruder.com.br`, then choose
   **Try another way / Use email instead** if login asks for a phone.
2. **Two-factor**: the seed and the recovery codes are in the file.
3. A live browser session still works while its cookie lives: copy `auth_token`
   and `ct0` and skip the reset entirely.
