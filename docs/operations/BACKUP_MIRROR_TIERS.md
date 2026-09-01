# Peer-host Backup-Mirror Tiers — Setup Runbook

A generic building block for replicating one host's backup directory onto another
host **read-only, without giving the replica any backend credentials**. It layers
on top of the [on-prem Velero mirror](ONPREM_BACKUP_SETUP.md) to add redundant
copies on additional servers.

Automated by [`scripts/backup-mirror-setup.sh`](../../scripts/backup-mirror-setup.sh).

---

## Model

Each link is a one-directional, read-only `rsync` **pull** over SSH:

```
DO Spaces ──(onprem-backup-setup.sh)──▶ niflheim:/mnt/storage/mycure
                                             │
                        (backup-mirror-setup.sh, this runbook)
                                             ▼
                                   vanaheim:/mnt/hdd/backup-mirror/niflheim
```

Topology is emergent — nothing is hardcoded:

- **Chain** — a replica can itself be a source for a further hop: run
  `--role=source` on it too, pointing `--allowed-path` at its target dir.
- **Fan-out** — one source can authorize many replicas for redundancy: run
  `--role=source` once per replica (distinct `--replica-name` / `--replica-ip`).

### Why this design

| Concern | How it's handled |
|---|---|
| Replica must hold **no creds** | It only `rsync`s the already-Kopia-encrypted blob files. No DO Spaces key, no Kopia password ever reach it. |
| Least privilege | The replica's SSH key is pinned to a **read-only `rrsync` forced command**, **path-jailed** to one dir, and **`from=` IP-locked** to the replica's tailnet IP. No shell, no write-back, no other paths. |
| Ransomware containment | Pull-only + read-only means a compromised replica cannot write to or corrupt the source's copy. |
| Data-at-rest | Blobs are Kopia-encrypted; a stolen replica leaks nothing readable. |
| Transport | Runs over Tailscale — no public exposure. |

Rejected alternatives: `kopia repository sync-to` (must `connect` first, which needs
the repo password — violates no-creds); rclone/Syncthing (no advantage over `rsync`
for Linux↔Linux, and Syncthing is bidirectional).

---

## Prerequisites

- Both hosts: Debian/Ubuntu with `rsync` (the source also needs `/usr/bin/rrsync`,
  shipped in the `rsync` package) and reachability over Tailscale.
- The source already has a populated backup dir (e.g. niflheim's
  `/mnt/storage/mycure` from the on-prem mirror).
- You know the replica's tailnet IP (`tailscale ip -4` on the replica) for the
  `from=` lock.

---

## Setup

Two steps, in this order. The replica step generates the key and prints the exact
source command to run next.

### 1. On the REPLICA (the host that will hold the copy)

```sh
sudo [DISCORD_WEBHOOK_URL=...] scripts/backup-mirror-setup.sh --role=replica \
  --name=<source-label> \
  --source-host=<source tailnet IP or resolvable host> \
  --source-path=spaces \
  --target-dir=<big-disk path> \
  --timer-on-calendar="*-*-* 05,17:00:00 Asia/Manila"
```

- `--source-host` must be **system-resolvable** (a tailnet IP, or a MagicDNS name)
  — the pull runs as the unprivileged `backup-mirror` user, which does **not** see
  your personal `~/.ssh/config` aliases.
- `--source-path` is **relative to the source's rrsync jail**. With the source
  exposing `/mnt/storage/mycure`, `spaces` pulls the whole mirror.
- `--target-dir` should be on a disk with room for the full copy.
- Schedule: default is **05:00 & 17:00 PHT** — 2h after niflheim's 03:00/15:00
  pull, which is 3h after the 00:00/12:00 PHT source Velero backups. Each tier
  leaves the one below it time to finish. (`Asia/Manila` suffix needs systemd ≥ 240.)

The script generates `/etc/backup-mirror/<name>.key`, installs the pull + weekly
verify units, and prints the pubkey + the source command.

### 2. On the SOURCE (the host that holds backup data)

```sh
sudo scripts/backup-mirror-setup.sh --role=source \
  --replica-name=<replica hostname> \
  --replica-ip=<replica tailnet IP> \
  --replica-pubkey="ssh-ed25519 AAAA... backup-mirror:<name>@<replica>"
```

Creates the `backup-replica` SSH principal (once), adds it to the group owning
`--allowed-path` (default `/mnt/storage/mycure`), and appends one locked-down
`authorized_keys` line for this replica. Re-running for the same `--replica-name`
replaces just that line; a new name adds another (fan-out).

### 3. First pull

```sh
sudo systemctl start backup-mirror-<name>.service
sudo journalctl --namespace=backup-mirror-<name> -u backup-mirror-<name>.service -f
```

---

## Verify

```sh
# Timers armed:
systemctl list-timers backup-mirror-<name>.timer backup-mirror-verify-<name>.timer

# Copy landed:
sudo du -sh <target-dir>

# The jail is READ-ONLY (run from the replica, as the mirror user):
sudo -u backup-mirror ssh -i /etc/backup-mirror/<name>.key \
  -o UserKnownHostsFile=/etc/backup-mirror/known_hosts \
  backup-replica@<source>            # must NOT give a shell
sudo -u backup-mirror rsync -a /etc/hostname \
  -e "ssh -i /etc/backup-mirror/<name>.key -o UserKnownHostsFile=/etc/backup-mirror/known_hosts" \
  backup-replica@<source>:spaces/CANARY   # must be REFUSED (rrsync -ro)

# Integrity (checksum diff vs source):
sudo systemctl start backup-mirror-verify-<name>.service
sudo journalctl --namespace=backup-mirror-<name> -u backup-mirror-verify-<name>.service -n 20
```

---

## Restore from a replica

The replica holds Kopia-**encrypted** blobs and **no password** — by design. To
restore from this copy, bring the copy to a recovery host and supply the Kopia
password (`gcloud secrets versions access latest --secret=monobase-velero-repo-password`
or the password manager), then follow [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md)
against the replicated directory. The replica being credential-free does not reduce
its value as a redundant copy.

---

## Operations

### Rotate the replica key

```sh
sudo rm /etc/backup-mirror/<name>.key /etc/backup-mirror/<name>.key.pub
sudo scripts/backup-mirror-setup.sh --role=replica --name=<name> ...   # regenerates
# then re-run --role=source on the source with the new pubkey
```

### Revoke a replica (on the source)

Remove its line from `/var/lib/backup-replica/.ssh/authorized_keys` (the line
ending `mirror-replica:<name>`), or delete the user if it was the only replica.

### Teardown (on a replica)

```sh
sudo systemctl disable --now backup-mirror-<name>.timer backup-mirror-verify-<name>.timer
sudo rm -f /etc/systemd/system/backup-mirror-<name>.* \
           /etc/systemd/system/backup-mirror-verify-<name>.* \
           /etc/backup-mirror/<name>.env /etc/backup-mirror/<name>.key*
sudo systemctl daemon-reload
# <target-dir> contents are left in place — remove separately if desired.
```

---

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| `Permission denied (publickey)` | source not authorized, or `from=` IP mismatch | Re-run `--role=source` with the replica's current tailnet IP + pubkey. |
| `rrsync: refusing …` / write fails | working as intended — jail is read-only | Nothing to fix; that's the guarantee. |
| Pull hangs on host-key prompt | first connect, `known_hosts` empty | The runner uses `StrictHostKeyChecking=accept-new`; ensure `/etc/backup-mirror/known_hosts` is writable by `backup-mirror`. |
| `rsync: change_dir failed` | wrong `--source-path` relative to the jail | Path is relative to `--allowed-path`; use `spaces`, not `/mnt/storage/mycure/spaces`. |
| Disk fills on the replica | copy larger than target disk | Point `--target-dir` at a bigger disk, or narrow what the source exposes. |

---

## Related

- [ONPREM_BACKUP_SETUP.md](ONPREM_BACKUP_SETUP.md) — the DO-Spaces→on-prem tier below this one.
- [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md) — recovering from a mirror.
- [BACKUP_DR.md](BACKUP_DR.md) — overall tier strategy.
- [`scripts/backup-mirror-setup.sh`](../../scripts/backup-mirror-setup.sh) — the script.
