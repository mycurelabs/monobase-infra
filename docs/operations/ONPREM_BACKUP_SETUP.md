# On-prem Velero Backup Mirror — Setup Runbook

This is the tier-4 of the [backup strategy](BACKUP_DR.md): a pull-only mirror of the cluster's Velero bucket onto an off-cloud host. It survives a DO sgp1 outage and a primary backup repo compromise. Restore procedure is documented in [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md).

The entire host-side setup is automated by [`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh). This document is the operator's runbook for invoking it correctly.

---

## Scope

- **Hosts**: Debian/Ubuntu (apt-based) with sudo.
- **Network**: outbound HTTPS to `sgp1.digitaloceanspaces.com`.
- **Disk**: enough for ~30 days of Kopia-deduplicated mirror. Estimate 80–200 GB at steady state today; grows with production data churn.

The script does everything except create the read-only DO Spaces key and store it in your password manager.

---

## 1. Secrets you need before running

### 1a. DO Spaces read-only access key

A separate, narrow-scope access key. Do NOT reuse the cluster's `velero-credentials` (which is read-write). Two ways to create it:

**Via `doctl` (preferred, scriptable):**

```sh
# doctl is already authenticated on workstations that have it.
doctl spaces keys create mycure-onprem-mirror-readonly \
  --grants "bucket=mycure-doks-velero-backups;permission=read"
```

Capture both halves from the output, save to your password manager under
`mycure / velero / onprem-mirror-readonly-spaces-key`.

**Via the DO web console:** Spaces → Access Keys → Create New → "Limited access" → grant **read** on the `mycure-doks-velero-backups` bucket only. Save both halves to the password manager.

### 1b. Kopia repository password

The Velero data-mover repo is Kopia-encrypted. Without this password, the mirrored bytes are useless. Source of truth:

```sh
gcloud secrets versions access latest --secret=monobase-velero-repo-password
```

This is the same password used by the cluster Secret `velero-repo-credentials`. Copy it to your password manager too — the on-prem host should be usable even if GCP itself is unreachable.

---

## 2. Run the script

The script needs three secrets via env and a couple of flags. Pick the encryption mode appropriate to the host (see decision table below).

```sh
sudo \
  SPACES_ACCESS_KEY="<from 1a>" \
  SPACES_SECRET_KEY="<from 1a>" \
  KOPIA_PASSWORD="<from 1b>" \
  scripts/onprem-backup-setup.sh \
    --encryption=<MODE> \
    [other flags as needed]
```

The secrets only exist in the shell environment of this one invocation. The script writes them into root-owned files (`/etc/rclone/rclone.conf`, `/etc/mycure-backup/kopia.password`) and unsets them. Don't re-export them outside this command.

### Encryption mode decision table

| Host class | Mode | Justification |
|---|---|---|
| Operator dev workstation | `--encryption=none` | Device is under the operator's physical control; Velero blobs are already Kopia-encrypted at rest; full-disk encryption is the operator's separate concern. |
| Always-on server with spare disk | `--encryption=luks-partition --luks-device=/dev/sdX --yes-wipe-device` | Cleanest. Real partition, no loop-device overhead. WARNING: wipes the named device. |
| Server with only a single shared disk | `--encryption=luks-file --luks-file-size=150G` | Sparse-file container, no repartitioning needed. Slight I/O overhead, fine for nightly bulk sync. |

### Common invocations

**This device (operator workstation):**

```sh
sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
  scripts/onprem-backup-setup.sh --encryption=none
```

**A new dedicated server, identifying the spare drive first:**

```sh
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE     # find an unmounted, no-FSTYPE disk
sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
  scripts/onprem-backup-setup.sh \
  --encryption=luks-partition \
  --luks-device=/dev/sdb \
  --yes-wipe-device
```

**A VM with no spare block device:**

```sh
sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
  scripts/onprem-backup-setup.sh \
  --encryption=luks-file \
  --luks-file-size=150G
```

### Full flag reference

`scripts/onprem-backup-setup.sh --help` prints the canonical list. Highlights:

| Flag | Default | Notes |
|---|---|---|
| `--backup-dir=PATH` | `/var/backups/mycure` | Mirror target. With LUKS modes, this becomes a mountpoint. |
| `--bucket=NAME` | `mycure-doks-velero-backups` | DO Spaces bucket. |
| `--region=REGION` | `sgp1` | DO Spaces region. |
| `--max-age=DURATION` | off | rclone `--max-age`. **Leave off for Kopia repos** — it filters objects by age from *both* the copy and the delete pass, so it neither reliably reclaims space nor keeps a restorable mirror (fresh snapshots dedup against older packs it would skip). Bound size with `--namespaces` + source TTL instead. |
| `--namespaces=LIST` | all | Mirror only these namespaces' Kopia repos (comma/space separated) plus all backup metadata; everything else is excluded. A Kopia repo is atomic per namespace, so this keeps each mirrored repo fully restore-consistent. This is how the on-prem disk is bounded. |
| `--bsl-prefix=PREFIX` | `infrastructure` | BackupStorageLocation prefix inside the bucket; used to build the `--namespaces` path filters. |
| `--service-user=USER` | `mycure-backup` | System user that runs the mirror. |
| `--timer-on-calendar=S` | `*-*-* 02:30:00 UTC` | systemd OnCalendar for the mirror. |
| `--wal-mirror` | off | Also mirror the PITR **WAL** catalog (`wal/<ns>/`) via two separate units — `mycure-wal-mirror` (per-minute, add-only `copy`) + `mycure-wal-reconcile` (daily `sync` with 30-day deletion **quarantine**) — independent of the twice-daily Kopia mirror. Requires `--namespaces`. See [WAL-archive mirror](#wal-archive-mirror-pitr-second-copy) below. |
| `--wal-timer-on-calendar=S` | `*:*:00` | systemd OnCalendar for the WAL mirror. Default = every minute (WAL lands in Spaces every `archive_timeout`, 60s in prod). |
| `--kopia-version=VER` | pinned in script | Kopia static binary release. |
| `--notify-on=MODE` | `both` | `both` / `failure-only` / `success-only` / `off`. Controls Discord notifications. |
| `--discord-webhook-url=URL` | (env var) | Same as `DISCORD_WEBHOOK_URL`. Stored at `/etc/mycure-backup/discord-webhook.url`. |

---

### Optional: Discord notifications

If `DISCORD_WEBHOOK_URL` is set in env (or passed via `--discord-webhook-url`), the script installs a notifier at `/usr/local/sbin/mycure-backup-notify` and wires it into the systemd unit:

- **Start** (any `--notify-on` mode except `off`): fires before `ExecStart` via `ExecStartPre=`. Reassures operators that a long-running mirror is in progress, not hung. Failure of the start notifier is ignored (`-` prefix) so a webhook outage never blocks the actual backup.
- **Success** (`--notify-on=both` or `success-only`): fires after `ExecStart` succeeds via `ExecStartPost=`.
- **Failure** (`--notify-on=both` or `failure-only`): fires via a sibling `mycure-backup-mirror-failure.service` triggered by `OnFailure=`.
- **Setup test** (always, when a webhook is configured): one-shot `test` notification sent at the end of the setup script so operators can confirm the channel is wired up before the first scheduled run.

The webhook URL is stored at `/etc/mycure-backup/discord-webhook.url` (mode 0640, readable by the service user). Rotate by re-running the script with the new URL, or clear by passing an empty `DISCORD_WEBHOOK_URL=""`.

Each notification includes host FQDN, run duration, and the size of `/var/backups/mycure/spaces/`. If `jq` is installed on the host, payloads use proper JSON escaping; otherwise a portable `sed`-based fallback is used.

To disable entirely without removing the URL, pass `--notify-on=off`. To send a manual notification:

```sh
sudo /usr/local/sbin/mycure-backup-notify test "running adhoc check"
```

## 3. Verify

After the script reports success:

```sh
# Timer is armed and waiting:
systemctl status mycure-backup-mirror.timer

# Credentials work end-to-end (read-only):
sudo -u mycure-backup rclone --config /etc/rclone/rclone.conf size \
  spaces:mycure-doks-velero-backups

# Trigger the first run now instead of waiting for 02:30 UTC:
sudo systemctl start mycure-backup-mirror.service

# Tail the run live (rclone --stats 5m output, one line per 5 min):
sudo journalctl --namespace=mycure-backup -u mycure-backup-mirror.service -f

# After the first run, local size should approximate the remote size:
sudo du -sh /var/backups/mycure/spaces/
```

The unit's logs go to a dedicated `mycure-backup` journal namespace with explicit size caps (default `500M`, `4 week` retention) so they can't bloat the global journal. Per-unit caps are owned by `/etc/systemd/journald@mycure-backup.conf` — tune `SystemMaxUse=` there if you want a different ceiling. Logs from the OnFailure helper share the same namespace, so one `journalctl --namespace=mycure-backup` query covers the full lifecycle of a run.

### Weekly integrity verification

The setup also installs `mycure-backup-verify.service` and `.timer`. The timer fires by default at **Sunday 03:00 UTC**, runs `/usr/local/sbin/mycure-backup-verify`, which does **two passes**:

1. `rclone sync` against the upstream Spaces bucket — closes any "mirror lag" gap (files updated upstream between the nightly mirror at 02:30 and this verify run) so the check below has a fair baseline.
2. `rclone check --checksum --combined` — compares hashes for every object between upstream and the (now freshly-synced) local mirror. The combined report is parsed:
   - `=` identical (expected)
   - `-` remote-only (should be ~0 post-sync; small numbers tolerable for objects written *during* the verify itself)
   - `+` local-only (extra local files; tolerated, doesn't fail)
   - `*` size/hash differ (**fails**, real corruption)
   - `!` I/O error (**fails**)

The script exits non-zero on `*` or `!`, which triggers `OnFailure=mycure-backup-verify-failure.service` → Discord red embed.

Catches:

- silent bit-rot on the local disk
- mirror desync (interrupted `rclone sync` runs, partial transfers)
- accidental local modifications

**What it does NOT catch**: Kopia repo *internal* corruption (broken chains of references, encrypted blob inconsistencies from Kopia's POV). The Kopia layout used by Velero's data-mover (S3-backend, flat blob namespace) is not directly readable via `kopia connect filesystem` (see [kopia/kopia#2065](https://github.com/kopia/kopia/issues/2065)), and the rclone-serve-s3 shim that *would* expose it to Kopia stalls on large repos with HDD-backed mirrors. Deeper structural validation lives in the quarterly drill in [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md), where the operator round-trips a real restore.

If DO Spaces is unreachable during a verify run, the sync fails fast and the OnFailure handler fires a red Discord embed — exactly the alert behaviour you want, since the cloud being unreachable is one of the scenarios this mirror exists for.

Trigger manually:

```sh
sudo systemctl start mycure-backup-verify.service
sudo journalctl --namespace=mycure-backup -u mycure-backup-verify.service -f
```

Disable the weekly run without uninstalling:

```sh
sudo systemctl disable --now mycure-backup-verify.timer
```

Once at least one Velero backup has been mirrored, validate that the Kopia repo can be opened from on-prem with the password the script stored:

```sh
sudo kopia repository connect filesystem \
  --path=/var/backups/mycure/spaces/kopia \
  --password="$(sudo cat /etc/mycure-backup/kopia.password)"
sudo kopia snapshot list
```

Both commands should succeed.

---

## 4. What lands on the host

| Path | Mode | Owner | Purpose |
|---|---|---|---|
| `/usr/bin/rclone` | apt-managed | root | Mirror client. |
| `/usr/local/bin/kopia` | 0755 | root | Restore tool (also for verification). |
| `/etc/rclone/rclone.conf` | 0640 | root:mycure-backup | S3 endpoint + read-only key. |
| `/etc/mycure-backup/kopia.password` | 0400 | root | Kopia repo password. |
| `/etc/mycure-backup/luks.key` | 0400 | root | LUKS keyfile (only LUKS modes). |
| `/etc/mycure-backup/discord-webhook.url` | 0640 | root:mycure-backup | Discord webhook URL (only when `DISCORD_WEBHOOK_URL` is set). |
| `/usr/local/sbin/mycure-backup-notify` | 0755 | root | Notifier helper (always installed). |
| `/etc/systemd/system/mycure-backup-mirror.{service,timer}` | 0644 | root | Mirror units. |
| `/etc/systemd/system/mycure-backup-mirror-failure.service` | 0644 | root | OnFailure handler that calls the notifier (only when `--notify-on` covers failure). |
| `/etc/systemd/system/mycure-backup-verify.{service,timer}` | 0644 | root | Weekly Kopia integrity check. |
| `/etc/systemd/system/mycure-backup-verify-failure.service` | 0644 | root | OnFailure handler for the verify run. |
| `/etc/systemd/system/mycure-wal-mirror.{service,timer}` | 0644 | root | Per-minute add-only WAL `copy` (only with `--wal-mirror`). |
| `/etc/systemd/system/mycure-wal-mirror-failure.service` | 0644 | root | OnFailure handler for the WAL mirror; rate-limited to 3 pings/hour. |
| `/etc/systemd/system/mycure-wal-reconcile.{service,timer}` | 0644 | root | Daily WAL `sync` + deletion quarantine (only with `--wal-mirror`). |
| `/etc/systemd/system/mycure-wal-reconcile-failure.service` | 0644 | root | OnFailure handler for the daily reconcile. |
| `/usr/local/sbin/mycure-wal-reconcile` | 0755 | root | Helper: dated-quarantine `rclone sync` + prune quarantine >30d. |
| `/usr/local/sbin/mycure-backup-verify` | 0755 | root | Helper: connect to local Kopia repo + run content verify. |
| `/etc/systemd/system/mycure-backup-volume.service` | 0644 | root | LUKS open+mount at boot (only LUKS modes). |
| `/etc/systemd/journald@mycure-backup.conf` | 0644 | root | Per-unit journal namespace config (size-capped). |
| `/var/backups/mycure/` | 0750 | mycure-backup | Mirror target (mountpoint in LUKS modes). |

---

## 5. Operations

### Re-run after changing flags

The script is idempotent. Re-running with different flags reconfigures cleanly.

> **Bounded subset (current prod config):** the `hel.niflheim` box's 1.8T disk is
> mounted at `/mnt/storage` (the root FS is only ~110G), and it cannot hold the
> full 30-day repo. It mirrors **only the `mycure-production` namespace** (plus all
> backup metadata) — always pass `--namespaces` on re-run or the mirror
> re-downloads the `monitoring` + `velero` Kopia repos (~316G) and re-fills the
> disk. The exact invocation in use:
>
> ```sh
> sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
>   scripts/onprem-backup-setup.sh \
>     --namespaces=mycure-production \
>     --backup-dir=/mnt/storage/mycure \
>     --timer-on-calendar="*-*-* 03,15:00:00 Asia/Manila" \
>     --wal-mirror
> ```
>
> (`--wal-mirror` adds the separate per-minute WAL/PITR copy — see the
> [WAL-archive mirror](#wal-archive-mirror-pitr-second-copy) section. Drop it for
> the Kopia mirror only.)
>
> **Timer — twice daily, 3h after each source backup.** The `production-daily`
> schedule runs at **00:00 & 12:00 PHT**
> (`values/clusters/mycure-doks-main/argocd/infrastructure.yaml` →
> `velero.schedules.production.daily.schedule: "CRON_TZ=Asia/Manila 0 0,12 * * *"`).
> The mirror fires at **03:00 & 15:00 PHT** — a 3h margin so each data-mover
> backup (pg is ~188G; a run can exceed 2h) has completed before the mirror pulls
> it. If a run ever overruns the margin, that snapshot is simply picked up by the
> next mirror run; twice-daily keeps the newest snapshot on-prem within ~12h.
>
> Retention (how many days) is a **source-side** setting — it's the Velero
> schedule TTL (same file → `velero.schedules.*.retention`), not an on-prem flag.
> The on-prem mirror faithfully holds whatever Spaces holds for the namespaces it
> mirrors; it cannot keep fewer *days* than the cloud without an independent Kopia
> repo.
>
> **Scope: this Kopia mirror is Velero only** — `--namespaces` builds the rclone
> filter as `--include "infrastructure/backups/**"` +
> `--include "infrastructure/kopia/mycure-production/**"` + `--exclude "**"`. The
> wal-g PITR catalog lives at `wal/mycure-production/` — a **sibling** of
> `infrastructure/` in the same bucket — so base backups and WAL segments are
> **excluded** from *this* mirror. They are covered by the **separate**
> `--wal-mirror` unit (see [WAL-archive mirror](#wal-archive-mirror-pitr-second-copy)
> below), not by widening this filter — keeping the two on independent cadences.
>
> **systemd version:** a named-timezone `OnCalendar` suffix (`Asia/Manila`) needs
> **systemd ≥ 252**; older systemd accepts only a `UTC` suffix (which is why the
> script's default uses one). niflheim runs 255, so it's fine — relevant only when
> copy-pasting this onto an older box.

### WAL-archive mirror (PITR second copy)

`--wal-mirror` adds a second, near-live copy of the PostgreSQL **WAL catalog**
(base backups + WAL segments) that powers point-in-time recovery. Without it the
on-prem host holds only the twice-daily Velero backup (~12h old); if DO Spaces is
lost you can restore to that, but **not** PITR. It installs **two** systemd units,
separate from the Kopia mirror:

- **Why separate from the Kopia mirror.** That mirror is a heavy twice-daily
  `rclone sync` of the ~188 GB repo (8h timeout). WAL is the opposite — tiny
  segments arriving every ~60s (`archive_timeout=60`). Different cadence, size, and
  failure isolation. Both aim rclone directly at `wal/<ns>/`, and the Kopia mirror's
  `--exclude "**"` never touches `wal/` — disjoint subtrees (why `--wal-mirror`
  requires `--namespaces`).
- **`mycure-wal-mirror` — every minute, add-only.**
  `rclone copy --max-age 6h --no-traverse spaces:<bucket>/wal/<ns>/ → <backup-dir>/spaces/wal/<ns>/`.
  `copy` **never deletes**. `--max-age` bounds the *transfer* set to recent objects
  and `--no-traverse` skips the destination walk — so the run only transfers new WAL.
  Enumeration of the *source* prefix still scales with the archive (~5.5k objects
  today → ~53k at plateau), but that's cheap LIST pagination (seconds);
  `TimeoutStartSec=300s` caps a hang. Steady-state lag ≈ `archive_timeout` + latency
  (~1-2 min) — **but `--max-age` is relative to *now***, so if the per-minute unit is
  down > 6h, objects that aged out of the window during the outage are only recovered
  by the next daily reconcile: real RPO after a long stall is up to ~24h, not 1-2 min
  (the damped failure notifier tells you it stalled). systemd skips a tick whose
  service is still active, so runs coalesce, never stack.
- **`mycure-wal-reconcile` — daily, air-gapped prune.** `rclone sync …
  --backup-dir=<backup-dir>/spaces/wal-deleted/<date>/<ns>` (default 04:00 PHT).
  Catches anything older than the copy's `--max-age` window **and** applies the
  cloud's (base-aware, wal-g-driven) prunes — but **quarantines** the removals into
  a dated dir instead of unlinking them. See the next point.
- **This is a backup, not a replica — it survives deletion.** A plain per-minute
  `rclone sync` would replicate a cloud-side *deletion* on-prem within ~60s: a
  mis-scoped `wal-g delete`, a leaked key, a bucket lifecycle rule, or the
  `pg_upgrade` retention footgun ([wal-g #636](https://github.com/wal-g/wal-g/issues/636),
  which deletes the **newest** bases) would destroy the second copy exactly when
  it's needed — and the **2026-08-28 incident was data *loss*, not an outage**.
  Here the per-minute path can't delete at all, and the daily reconcile
  **quarantines** deletions for **30 days** (`WAL_QUARANTINE_DAYS`) under
  `wal-deleted/<date>/`, pruned by *quarantine* age (dir mtime), not object age.
  That independent on-prem retention is the air gap.
- **First install seeds synchronously.** The initial pull is the whole retained
  catalog (~81 GiB today, see Disk), too big for a per-minute run — so the script
  runs one blocking `rclone copy` to completion *before* arming the timers. The
  first `--wal-mirror` run takes a while; re-runs are fast no-ops.
- **Notifications.** Failure-only. The per-minute unit is rate-limited to 3
  pings/hour (`StartLimitBurst=3` / `StartLimitIntervalSec=1h`) — a per-minute
  *success* webhook would be 1440 msgs/day, and a sustained outage would otherwise
  fire 60/hour; the daily reconcile just alerts on failure.
- **Disk.** Bounded by source retention **plus the 30-day quarantine**: the mirror
  holds what the cloud `wal/<ns>/` holds (WAL kept until the oldest base backup ages
  out — `walg.backup.retainFull=4` weekly ≈ 4-5 weeks) plus up to 30 days of
  quarantined deletions under `wal-deleted/`. Measured 2026-09-01 (**source of
  record: PITR-RESTORE.md cost section, #401**): seeds at **~81 GiB today** for
  `mycure-production` (2 of 4 eventual weekly bases + WAL; matches the niflheim seed
  of 81 GiB / 5,471 objects), grows **~2.33 GB/day compressed** (~29 GiB/day raw,
  ~13× compression) **plus one ~37.5 GiB base/week until the *live* set plateaus at
  ~210 GiB** (4 bases ~150 GiB + ~4 wks WAL ~61 GiB). **Quarantine adds ~225 GiB**:
  at plateau the cloud's deletion rate equals its ingest (~7.5 GiB/day = 211 GiB per
  4-week cycle), held `WAL_QUARANTINE_DAYS=30` → ~225 GiB under `wal-deleted/`.
  **Budget ~435 GiB total** (210 live + 225 quarantine), not today's 81 GiB — still
  fits niflheim's 1.8T `/mnt/storage` with room (drop to a 7-day quarantine ≈ 53 GiB
  if you'd rather hold the footprint). Confirm `df -h <backup-dir>` headroom on top of
  the Kopia repo.

> **Restoring PITR from the on-prem WAL copy** (cloud unreachable) is a separate
> drill — point wal-g at the local files (`WALG_FILE_PREFIX`) or re-serve the
> prefix. This runbook only guarantees the *bytes* are on-prem; see
> [PITR-RESTORE.md](PITR-RESTORE.md). On-prem WAL *freshness* is not yet
> Prometheus-monitored.

### Rotate the Spaces access key

1. Create a new key (step 1a).
2. Re-run the script with the new key in env.
3. Delete the old key in the DO console.

### Rotate the Kopia password

The Kopia password is owned by the cluster, not this host. Rotate via the cluster's `velero-repo-credentials` first (see [BACKUP_DR.md](BACKUP_DR.md)), then re-run the script with the new `KOPIA_PASSWORD` to update the on-prem copy.

### Teardown

```sh
sudo systemctl disable --now mycure-backup-mirror.timer mycure-backup-mirror.service \
                              mycure-backup-verify.timer mycure-backup-verify.service
sudo systemctl disable --now mycure-wal-mirror.timer mycure-wal-mirror.service 2>/dev/null || true
sudo systemctl disable --now mycure-wal-reconcile.timer mycure-wal-reconcile.service 2>/dev/null || true
sudo systemctl disable --now mycure-backup-volume.service 2>/dev/null || true
sudo umount /var/backups/mycure 2>/dev/null || true
sudo cryptsetup close mycure-backup 2>/dev/null || true
sudo kopia repository disconnect 2>/dev/null || true
sudo rm -rf /etc/mycure-backup /etc/rclone/rclone.conf \
            /etc/systemd/system/mycure-backup-mirror.* \
            /etc/systemd/system/mycure-backup-verify.* \
            /etc/systemd/system/mycure-wal-mirror.* \
            /etc/systemd/system/mycure-wal-reconcile.* \
            /etc/systemd/system/mycure-backup-volume.service \
            /etc/systemd/journald@mycure-backup.conf \
            /usr/local/sbin/mycure-backup-notify \
            /usr/local/sbin/mycure-backup-verify \
            /usr/local/sbin/mycure-wal-reconcile
sudo systemctl reset-failed "systemd-journald@mycure-backup.service" 2>/dev/null || true
sudo rm -rf /var/log/journal/*/system@mycure-backup-* 2>/dev/null || true
sudo userdel mycure-backup 2>/dev/null || true
# /var/backups/mycure/ contents (or the LUKS image/partition) are left alone —
# decide separately whether to wipe.
```

---

## 6. Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| Script fails at "rclone failed to list spaces:…" | Wrong access key or bucket name | Recheck `SPACES_ACCESS_KEY`/`SECRET`; confirm bucket name and region. |
| Timer `inactive (dead)` after first run | Service failed | `journalctl -u mycure-backup-mirror.service` for stderr. |
| `cryptsetup: Device … is still in use` | Previous mount didn't release | `umount /var/backups/mycure; cryptsetup close mycure-backup` then re-run. |
| Disk fills up | Production data growth, or mirroring too many namespaces | Narrow `--namespaces` (drop low-value repos like `monitoring`/`velero`), shorten the source Velero TTL (`velero.schedules.*.retention`), or grow the disk (see NIFLHEIM_RAID_PROPOSAL.md). Do **not** reach for `--max-age` — it can corrupt restorability. |
| `kopia snapshot list` returns empty | No Velero data-mover backup has run since the on-prem mirror was started | Wait for tonight's `production-daily` schedule, or trigger a manual `velero backup create`. |

---

## Related

- [BACKUP_DR.md](BACKUP_DR.md) — overall 4-tier strategy and RPO/RTO.
- [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md) — using the mirror to recover.
- [`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh) — the script itself.
- [`charts/velero-resources/credentials-template.yaml`](../../charts/velero-resources/credentials-template.yaml) — source of the Kopia repo password.
