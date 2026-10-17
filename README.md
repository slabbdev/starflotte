# starflotte

A fleet of [navette](https://github.com/slabbdev/navette) browsers running on
free GitHub Actions runners. You tell the fleet what to check by opening an
issue; the fleet checks it with 20 parallel scouts and posts one aggregated
report back on that issue.

20 concurrent jobs is exactly the free-plan cap for GitHub Actions, and on a
public repo the minutes are free.

## Launch a mission

1. Open an issue. The body is the mission: target URLs, one per line
   (first 20 URLs are picked up).
2. Label the issue `mission`. The fleet starts.

Or run it manually from the Actions tab: `workflow_dispatch` with an issue
number, or raw comma-separated `urls` for a smoke test (report lands in the
run summary instead of an issue).

## Task missions — ask the fleet to DO something

A mission issue can carry a json fenced block instead of a plain URL list.
Each object is one scout's task: an optional ordered `steps` list of navette
calls, and an `extract` JS expression whose result lands in the fleet report.

````
```json
[
  {
    "name": "RIPE whois IP",
    "url": "https://apps.db.ripe.net/db-web-ui/query",
    "steps": [
      {"type": {"selector": "#searchInput", "value": "140.82.121.4"}},
      {"evaluate": {"js": "(()=>{const b=[...document.querySelectorAll('button')].find(x=>x.innerText.trim()==='Search'); b.click(); return 1;})()"}},
      {"sleep": {"ms": 8000}}
    ],
    "extract": "document.body.innerText.split('Search results')[1]?.slice(0,900) || 'no results'"
  }
]
```
````

Steps are sent to the daemon verbatim as `{"route": {payload}}` — everything
the navette HTTP API accepts works (`type`, `click`, `key`, `hover`, `scroll`,
`evaluate`, `wait`). Timed pauses use the `sleep` pseudo-route (the daemon's
`/wait` is selector-only); 30 s cap per sleep. A task with no `steps` is just
a navigate + extract, which covers GET-param queries
(`crt.sh/?q=…`, `html.duckduckgo.com/html/?q=…`, Wayback snapshot URLs).

## What each scout does

Scout *k* takes target *k*. It boots the multi-arch `ghcr.io/slabbdev/navette`
image (WebKitGTK under Xvfb), drives the daemon over its HTTP API
(`/navigate` with markdown extraction), and classifies the result:

- **OK** — page loaded, title and markdown extract captured.
- **WALL** — an anti-bot page was detected (captcha / DataDome / Cloudflare
  patterns). No bypass is ever attempted: the wall is the result.
- **ERROR** — navigation failed.

Every scout uploads an artifact (`scout-N`) with its screenshot, the full
markdown extract and a machine `result-N.json`. A summary job downloads all
artifacts and posts ONE report table on the mission issue.

## Policies

- Read-only public pages. No logins, no account creation, no metric inflation.
- A captcha is a result, not a problem to solve: the scout reports WALL and stops.

## Known limits

- Runners egress from Azure datacenter IPs — sites with DataDome/Cloudflare
  (Leboncoin, Vinted…) will wall most runs. That is a feature here: the issue
  documents the wall.
- Scheduled runs are approximate (cron on Actions drifts) and workflows get
  disabled after 60 days of repo inactivity.
- Everything is ephemeral: no cookies, no sessions, no state between runs.

## Authenticated missions (Voie B — session cookies)

Anonymous runners see public pages only. To run authenticated passes, inject
session cookies from your own machine instead of typing passwords on a runner
(navette's `/login` flow needs an interactive keychain, and a login from a
datacenter IP invites captchas):

1. On your Mac, log into the site with a local navette, then save the jar:
   `POST /sessions/state {"session":"...","store":"DEVTO"}`
2. Extract it from the keychain (the jar never leaves the daemon over HTTP —
   the keychain is the exit door, and it's yours):
   `security find-generic-password -s navette -a DEVTO -w > devto.json`
3. Push it as a repo secret (one entry per site, wrappers or flat arrays):
   ```
   jq -n --slurpfile j devto.json '{"devto": $j[0]}' | gh secret set NAVETTE_STATES
   ```
4. Every scout now starts with that session loaded. Refresh the secret when
   the site expires the session.

Rules: dedicated automation accounts, never your primary ones. No interactive
2FA on runners (app passwords if the site allows). A captcha mid-run is a
reported result, never a bypass. Never put jars in issues, artifacts or plain
variables — secrets only.
