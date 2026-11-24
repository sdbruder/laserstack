# Posting on X as @laserstack_sdb

`tools/x` posts, replies and reads on X through
[twitter-cli](https://github.com/jackwener/twitter-cli), authenticated with the
session cookie of @laserstack_sdb. It never uses the account of the browser.

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
lock or suspend the account. The account is dedicated to the project, so the
damage stops there, and the cookie file keeps the personal account out of it.

Keep the account within human behavior: no bulk follow or unfollow, no direct
messages, no bursts. An unverified account may create about 50 posts and 200
replies a day, inside a 30-minute burst window that X does not publish.

The cookie is a password. `auth_token` gives full control of the account until
that session ends. Keep the file at mode 600, and never commit it.

## Install, once

```sh
uv tool install twitter-cli
```

Run `uv tool upgrade twitter-cli` when a request starts to fail: X changes the
web app often, and the tool follows it.

## Cookies, once

1. In Chrome, open the profile menu, choose **Add**, and make a profile named
   `laserstack_sdb`. Sign in to x.com as @laserstack_sdb in that profile only.
   A separate profile keeps the cookie of the personal account apart; sign out
   of nothing.
2. In that profile open <https://x.com>, then DevTools (⌥⌘I) → **Application** →
   **Cookies** → `https://x.com`.
3. Copy the values of `auth_token` and `ct0`.
4. Write them to the cookie file:

   ```sh
   mkdir -p ~/.config/laserstack
   umask 077 && cat > ~/.config/laserstack/x.env <<'EOF'
   TWITTER_AUTH_TOKEN=...
   TWITTER_CT0=...
   EOF
   ```

5. Check the account:

   ```sh
   tools/x whoami          # must print @laserstack_sdb
   ```

If `tools/x whoami` prints another account, the cookie is wrong: delete the
file and repeat step 2.

## Use

```sh
tools/x whoami                          # who the cookie belongs to
tools/x post "Laser Stack 2.0 is out"    # a post
tools/x post "text" -i docs/og.png       # with an image, up to four
tools/x reply <tweet-id> "text"
tools/x quote <tweet-id> "text"
tools/x delete <tweet-id>
tools/x feed --max 20                    # home timeline of that account
tools/x user-posts laserstack_sdb --max 20
tools/x search "laserstack" -t Latest
```

Add `--json` or `--yaml` for scripts. `twitter --help` lists every command;
`tools/x` passes all of them through.

## When it breaks

| Message | Cause | Fix |
|---|---|---|
| `Cookie expired or invalid (HTTP 401)` | the session ended | repeat **Cookies**, steps 2 to 4 |
| `Couldn't get KEY_BYTE indices`, or a transaction-id error | X changed its web app | `uv tool upgrade twitter-cli` |
| `tools/x: no credentials at ...` | no cookie file | repeat **Cookies** |
| `tools/x: ... lacks TWITTER_AUTH_TOKEN or TWITTER_CT0` | half-written file | rewrite the file |

The last two errors are deliberate. With no cookie in the environment,
`twitter-cli` reads the cookies of the browser and would post as the personal
account, so the wrapper refuses instead.
