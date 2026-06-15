# On-prem GitHub Org Backup — Setup Runbook

An off-cloud backup of the **entire `mycurelabs` GitHub organization** — code, wikis, issues, pull requests, releases, and metadata — onto a local host. This is the source-code analogue of the [Velero on-prem mirror](ONPREM_BACKUP_SETUP.md): where that mirrors production *data* off DO Spaces, this mirrors the org's *repositories* off GitHub, so a lost/compromised/deleted org or a GitHub outage doesn't mean lost source history.

The entire host-side setup is automated by [`scripts/github-backup-setup.sh`](../../scripts/github-backup-setup.sh). This document is the operator's runbook for invoking it.

Under the hood it wraps [`josegonzalez/python-github-backup`](https://github.com/josegonzalez/python-github-backup) (the `github-backup` tool) in a systemd timer, with a weekly `git fsck` integrity pass and Discord notifications — the same operational scaffolding as the data mirror.

---

## Scope

- **Hosts**: Debian/Ubuntu (apt-based) with sudo and **Python ≥ 3.10**.
- **Network**: outbound HTTPS to `api.github.com` and `github.com`.
- **Disk**: small. The org is ~2.3 GB of git today (106 repos); metadata JSON adds little. Budget a few GB with headroom.

What is captured per repo (incrementally, via `github-backup --all --private --attachments --bare`):

| Captured | Stored as |
|---|---|
| Code — all branches, tags, refs (`git clone --mirror`) | bare git repo at `repositories/<name>/repository/` |
| Wiki (if any) | bare git repo at `repositories/<name>/wiki/` |
| Issues + comments | JSON under `repositories/<name>/issues/` |
| Pull requests + comments + reviews + commits | JSON under `repositories/<name>/pulls/` |
| Release **metadata** (tags, notes) | under `repositories/<name>/releases/` |
| Labels, milestones, hooks, discussions | JSON under `repositories/<name>/` |
| Issue/PR comment attachments | under `.../attachments/` |

> **Why `--private` is mandatory:** github-backup's resource flags (and `--all`) **exclude private repos, forks, LFS, and attachments** by default. Most `mycurelabs` repos are private, so the runner always passes `--private --attachments`. Without `--private` the backup would silently capture almost nothing.
>
> **Release binary assets are excluded by default.** The runner enumerates resources explicitly and includes `--releases` (metadata) but **not** `--assets` (the uploaded binaries/build artifacts). Those can be many GB for a single repo — enough to blow past the run timeout and balloon disk use — and aren't source. Pass `--include-assets` to include them (and raise `--run-timeout` accordingly). LFS objects and forks are likewise opt-in (`--include-lfs`, `--include-forks`).

---

## 1. The secret you need before running

A **dedicated classic Personal Access Token (PAT)** — not your interactive `gh` login, and not a fine-grained token (fine-grained tokens can't download attachments from private repos).

Create it at **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token**, with scopes:

- `repo` (full — required to clone private repos)
- `read:org` (enumerate org repos)
- `read:discussion` (back up discussions)

Have an org owner authorize the token for the `mycurelabs` org if SSO is enforced. Save it to the password manager under `mycure / github / onprem-backup-pat`. The host should hold its own copy so the backup works even if the password manager is unreachable.

---

## 2. Run the script

```sh
sudo \
  GITHUB_TOKEN="<the classic PAT>" \
  DISCORD_WEBHOOK_URL="<ops webhook, optional>" \
  scripts/github-backup-setup.sh [flags]
```

The token only exists in the shell environment of this one invocation. The script writes it to a root-owned file (`/etc/mycure-github-backup/token`) and unsets it. Don't re-export it outside this command.

### Common invocations

**This machine (default org, daily at 02:00 UTC, Discord on):**

```sh
sudo GITHUB_TOKEN=… DISCORD_WEBHOOK_URL=… scripts/github-backup-setup.sh
```

**Also pull Git LFS objects and forks:**

```sh
sudo GITHUB_TOKEN=… scripts/github-backup-setup.sh --include-lfs --include-forks
```

**A different org / target dir / schedule:**

```sh
sudo GITHUB_TOKEN=… scripts/github-backup-setup.sh \
  --org=dentalemon \
  --backup-dir=/srv/backups/dentalemon-github \
  --timer-on-calendar="*-*-* 03:30:00 UTC"
```

### Full flag reference

`scripts/github-backup-setup.sh --help` prints the canonical list. Highlights:

| Flag | Default | Notes |
|---|---|---|
| `--org=NAME` | `mycurelabs` | GitHub organization to back up. |
| `--backup-dir=PATH` | `/var/backups/mycure-github` | Backup target directory. |
| `--service-user=USER` | `mycure-ghbackup` | System user that runs the backup. |
| `--timer-on-calendar=S` | `*-*-* 02:00:00 UTC` | systemd OnCalendar for the daily backup. |
| `--verify-timer-on-calendar=S` | `Sun *-*-* 04:00:00 UTC` | systemd OnCalendar for the weekly verify. |
| `--github-backup-version=VER` | pinned in script | `github-backup` PyPI version (installed into a dedicated venv). |
| `--include-lfs` | off | Also pull Git LFS objects (installs `git-lfs`; slower). |
| `--include-forks` | off | Also back up forked repos. |
| `--throttle-limit=N` / `--throttle-pause=SEC` | `5000` / `0.72` | github-backup API rate-limit controls. |
| `--notify-on=MODE` | `both` | `both` / `failure-only` / `success-only` / `off`. |
| `--include-assets` | off | Also download release **binary** assets (can be many GB; metadata kept regardless). |
| `--run-timeout=DUR` | `12h` | systemd `TimeoutStartSec` for a backup run; a wedged run is killed after this. |
| `--progress-interval=DUR` | `30min` | Heartbeat cadence while a backup runs (e.g. `30min`, `1h`); `0`/`off` disables progress pings. |
| `--discord-webhook-url=URL` | (env var) | Same as `DISCORD_WEBHOOK_URL`; stored at `/etc/mycure-github-backup/discord-webhook.url`. |

Before enabling the timers, the script does a credential dry-run against `https://api.github.com/orgs/<org>` and fails fast with a clear message on `401` (bad/expired token), `403` (missing scope / rate-limited), or `404` (wrong org / token can't see it).

### Optional: Discord notifications

Identical model to the data mirror. If `DISCORD_WEBHOOK_URL` is set (or `--discord-webhook-url`), the script installs `/usr/local/sbin/mycure-github-backup-notify` and wires `start`/`success`/`failure` (and `verify-*`) into the units, plus a one-shot `test` ping at the end of setup. Each embed includes host FQDN, run duration, **repo count**, and total backup size. Disable without removing the URL via `--notify-on=off`.

**Progress heartbeats.** The initial full backup is long-running (hours). To avoid a multi-hour silence between `start` and `success`/`failure`, the script also installs `mycure-github-backup-progress.service` + `.timer`, which post a recurring blue "in progress" embed (elapsed, repos so far, size, current repo) every `--progress-interval` (default **30 min**). The timer is permanently enabled and ticks on a fixed cadence, but the service **guards on the backup unit's state** and sends a webhook only while a backup is actually `active`/`activating` — so no pings while idle. (It is intentionally *not* started/stopped by the backup unit, which runs as the unprivileged `mycure-ghbackup` user and can't control systemd timers.) The verify pass is short and gets no heartbeat. Disable with `--progress-interval=0` (start/success/failure pings are unaffected).

---

## 3. Verify

After the script reports success:

```sh
# Timers armed and waiting:
systemctl status mycure-github-backup.timer mycure-github-backup-verify.timer

# Trigger the first backup now instead of waiting for 02:00 UTC:
sudo systemctl start mycure-github-backup.service

# Tail it live:
sudo journalctl --namespace=mycure-github-backup -u mycure-github-backup.service -f

# After it finishes, ~106 repos should be on disk:
find /var/backups/mycure-github -type d -name repository -prune | wc -l
sudo du -sh /var/backups/mycure-github
```

Spot-check that a known **private** repo came down as a bare mirror:

```sh
git --git-dir=/var/backups/mycure-github/repositories/monobase-mycure/repository \
  rev-parse --is-bare-repository      # -> true
git --git-dir=/var/backups/mycure-github/repositories/monobase-mycure/repository \
  for-each-ref --format='%(refname)' | head
```

### Weekly integrity verification

The setup also installs `mycure-github-backup-verify.service` and `.timer` (default **Sunday 04:00 UTC**). It runs `/usr/local/sbin/mycure-github-backup-verify`, which:

1. Runs `git fsck --full --strict` on every bare repo **and** wiki under the backup dir — catches on-disk corruption / bit-rot / truncated objects.
2. Compares the current repo count against the count recorded by the last successful backup (`/etc/mycure-github-backup/repo-count.baseline`) — catches a silent drop (deleted/renamed org, token scope loss, partial run).

It exits non-zero on any corruption or count drop, which fires `OnFailure=mycure-github-backup-verify-failure.service` → red Discord embed. Trigger manually:

```sh
sudo systemctl start mycure-github-backup-verify.service
sudo journalctl --namespace=mycure-github-backup -u mycure-github-backup-verify.service -f
```

Logs go to a dedicated `mycure-github-backup` journald namespace with size caps (`500M`, `4 week`), owned by `/etc/systemd/journald@mycure-github-backup.conf`.

---

## 4. What lands on the host

| Path | Mode | Owner | Purpose |
|---|---|---|---|
| `/opt/mycure-github-backup/venv/` | 0755 | root | Pinned `github-backup` Python venv. |
| `/etc/mycure-github-backup/token` | 0640 | root:mycure-ghbackup | The GitHub PAT. |
| `/etc/mycure-github-backup/discord-webhook.url` | 0640 | root:mycure-ghbackup | Discord webhook (only when set). |
| `/etc/mycure-github-backup/repo-count.baseline` | 0644 | mycure-ghbackup | Repo count from the last successful backup. |
| `/usr/local/sbin/mycure-github-backup-run` | 0755 | root | Backup runner (invokes `github-backup`). |
| `/usr/local/sbin/mycure-github-backup-verify` | 0755 | root | Weekly `git fsck` + count check. |
| `/usr/local/sbin/mycure-github-backup-notify` | 0755 | root | Discord notifier. |
| `/etc/systemd/system/mycure-github-backup.{service,timer}` | 0644 | root | Daily backup units. |
| `/etc/systemd/system/mycure-github-backup-failure.service` | 0644 | root | OnFailure → notifier. |
| `/etc/systemd/system/mycure-github-backup-verify.{service,timer}` | 0644 | root | Weekly verify units. |
| `/etc/systemd/system/mycure-github-backup-verify-failure.service` | 0644 | root | OnFailure → notifier. |
| `/etc/systemd/system/mycure-github-backup-progress.{service,timer}` | 0644 | root | Progress heartbeat (only when progress enabled). |
| `/etc/systemd/journald@mycure-github-backup.conf` | 0644 | root | Bounded journal namespace. |
| `/var/backups/mycure-github/` | 0750 | mycure-ghbackup | Backup target. |

---

## 5. Operations

### Re-run after changing flags

The script is idempotent. Re-running reconciles cleanly:

```sh
# Switch to a different schedule and turn off success pings:
sudo GITHUB_TOKEN=… scripts/github-backup-setup.sh \
  --timer-on-calendar="*-*-* 01:00:00 UTC" --notify-on=failure-only
```

### Rotate the PAT

1. Create a new classic PAT (step 1).
2. Re-run the script with the new `GITHUB_TOKEN` in env.
3. Revoke the old token in GitHub settings.

### Teardown

```sh
sudo systemctl disable --now mycure-github-backup.timer mycure-github-backup.service \
                              mycure-github-backup-verify.timer mycure-github-backup-verify.service
sudo systemctl stop mycure-github-backup-progress.timer 2>/dev/null || true
sudo rm -rf /etc/mycure-github-backup \
            /etc/systemd/system/mycure-github-backup.* \
            /etc/systemd/system/mycure-github-backup-verify.* \
            /etc/systemd/system/mycure-github-backup-progress.* \
            /etc/systemd/journald@mycure-github-backup.conf \
            /usr/local/sbin/mycure-github-backup-run \
            /usr/local/sbin/mycure-github-backup-verify \
            /usr/local/sbin/mycure-github-backup-notify \
            /opt/mycure-github-backup
sudo systemctl daemon-reload
sudo systemctl reset-failed "systemd-journald@mycure-github-backup.service" 2>/dev/null || true
sudo userdel mycure-ghbackup 2>/dev/null || true
# /var/backups/mycure-github/ contents are left alone — decide separately whether to wipe.
```

---

## 6. Restore

The backed-up repos are ordinary bare git mirrors, so restoring code to a new (or recreated) GitHub remote is a one-liner per repo:

```sh
# Recreate the empty repo on GitHub first (gh repo create mycurelabs/<name> --private),
# then push every ref and tag from the local mirror:
git --git-dir=/var/backups/mycure-github/repositories/<name>/repository \
  push --mirror git@github.com:mycurelabs/<name>.git
```

Bulk-restore by looping over `repositories/*/repository`. Wikis restore the same way against `<name>.wiki.git`.

**Metadata caveat:** issues, PRs, and releases are preserved as JSON, not as a directly-restorable format. GitHub's API has no "import with original numbers/timestamps/authors" — re-creating them via the API produces new issue/PR numbers and current timestamps. The JSON is a faithful archival record (read it, audit it, script a best-effort re-import), but treat the **git history as the authoritative, losslessly-restorable** part and the metadata as reference.

---

## 7. Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| Setup fails "GitHub returned 401" | Token invalid/expired | Recreate the classic PAT (step 1), re-run. |
| Setup fails "GitHub returned 403" | Missing scope or rate-limited | Ensure `repo` + `read:org`; if SSO-enforced, authorize the token for the org. |
| Setup fails "GitHub returned 404 for org" | Wrong `--org`, or token can't see it | Check the org name; confirm `read:org`. |
| Backup runs but repo count is ~0 | `--private` not applied (old/edited runner) | Re-run the setup script; the runner always passes `--private`. |
| `github-backup: command not found` style errors | venv didn't build (Python < 3.10) | Confirm `python3 --version` ≥ 3.10. |
| Backup result `timeout`; never completes; size balloons | A repo with huge release **binary assets** (or LFS) is eating the run | Assets are excluded by default — re-run setup so the runner drops `--assets`; reclaim space with `find <backup-dir>/repositories -mindepth 2 -maxdepth 2 -type d -name releases -exec rm -rf {} +` (metadata re-fetches). Raise `--run-timeout` only if you genuinely need `--include-assets`. |
| `repo-count.baseline` empty | No backup has completed end-to-end yet | The baseline is written only at the end of a successful run; fix whatever aborts the run (often the timeout/assets row above). |
| Verify fails with `CORRUPT:` lines | On-disk git corruption / bit-rot | Re-run the backup service to re-fetch; if persistent, investigate disk health. |
| Verify fails with "repo count dropped" | Repos removed/renamed upstream, or a partial run | Confirm intentional; otherwise check the last backup's logs. |

---

## Related

- [BACKUP_DR.md](BACKUP_DR.md) — overall backup strategy (data tiers + this source-code backup).
- [ONPREM_BACKUP_SETUP.md](ONPREM_BACKUP_SETUP.md) — the data-mirror analogue this is modeled on.
- [`scripts/github-backup-setup.sh`](../../scripts/github-backup-setup.sh) — the installer.
- [`josegonzalez/python-github-backup`](https://github.com/josegonzalez/python-github-backup) — the underlying tool.
