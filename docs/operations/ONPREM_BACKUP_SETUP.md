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
| `--max-age=DURATION` | `30d` | rclone `--max-age`; older objects skipped/deleted locally. |
| `--service-user=USER` | `mycure-backup` | System user that runs the mirror. |
| `--timer-on-calendar=S` | `*-*-* 02:30:00 UTC` | systemd OnCalendar for the mirror. |
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

The setup also installs `mycure-backup-verify.service` and `.timer`. The timer fires by default at **Sunday 03:00 UTC**, runs `/usr/local/sbin/mycure-backup-verify`, which executes `rclone check` against the upstream DO Spaces bucket:

```
rclone check spaces:mycure-doks-velero-backups /mnt/storage/mycure-backup/spaces/ --one-way ...
```

This compares hashes between every remote object and its local mirror copy. It catches:

- silent bit-rot on the local disk
- mirror desync (interrupted `rclone sync` runs, partial transfers)
- accidental local modifications

Failure path: non-zero exit → `OnFailure=mycure-backup-verify-failure.service` → Discord red embed.

**What it does NOT catch**: Kopia repo *internal* corruption (broken chains of references, encrypted blob inconsistencies from Kopia's POV). The Kopia layout used by Velero's data-mover (S3-backend, flat blob namespace) is not directly readable via `kopia connect filesystem` (see [kopia/kopia#2065](https://github.com/kopia/kopia/issues/2065)), and the rclone-serve-s3 shim that *would* expose it to Kopia stalls on large repos with HDD-backed mirrors. Deeper structural validation lives in the quarterly drill in [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md), where the operator round-trips a real restore.

If DO Spaces is unreachable during a verify run, the rclone check fails fast and the OnFailure handler fires a red Discord embed — exactly the alert behaviour you want, since the cloud being unreachable is one of the scenarios this mirror exists for.

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
| `/usr/local/sbin/mycure-backup-verify` | 0755 | root | Helper: connect to local Kopia repo + run content verify. |
| `/etc/systemd/system/mycure-backup-volume.service` | 0644 | root | LUKS open+mount at boot (only LUKS modes). |
| `/etc/systemd/journald@mycure-backup.conf` | 0644 | root | Per-unit journal namespace config (size-capped). |
| `/var/backups/mycure/` | 0750 | mycure-backup | Mirror target (mountpoint in LUKS modes). |

---

## 5. Operations

### Re-run after changing flags

The script is idempotent. Re-running with different flags reconfigures cleanly:

```sh
# Bump retention from 30d to 60d:
sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
  scripts/onprem-backup-setup.sh --max-age=60d
```

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
sudo systemctl disable --now mycure-backup-volume.service 2>/dev/null || true
sudo umount /var/backups/mycure 2>/dev/null || true
sudo cryptsetup close mycure-backup 2>/dev/null || true
sudo kopia repository disconnect 2>/dev/null || true
sudo rm -rf /etc/mycure-backup /etc/rclone/rclone.conf \
            /etc/systemd/system/mycure-backup-mirror.* \
            /etc/systemd/system/mycure-backup-verify.* \
            /etc/systemd/system/mycure-backup-volume.service \
            /etc/systemd/journald@mycure-backup.conf \
            /usr/local/sbin/mycure-backup-notify \
            /usr/local/sbin/mycure-backup-verify
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
| Disk fills before 30 days | Production data growth exceeded estimate | Increase disk, shorten `--max-age`, or revisit on-prem retention vs. cloud retention. |
| `kopia snapshot list` returns empty | No Velero data-mover backup has run since the on-prem mirror was started | Wait for tonight's `production-daily` schedule, or trigger a manual `velero backup create`. |

---

## Related

- [BACKUP_DR.md](BACKUP_DR.md) — overall 4-tier strategy and RPO/RTO.
- [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md) — using the mirror to recover.
- [`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh) — the script itself.
- [`infrastructure/external-secrets/velero-repo-credentials-externalsecret.yaml`](../../infrastructure/external-secrets/velero-repo-credentials-externalsecret.yaml) — source of the Kopia repo password.
