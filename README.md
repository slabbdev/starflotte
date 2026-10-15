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
