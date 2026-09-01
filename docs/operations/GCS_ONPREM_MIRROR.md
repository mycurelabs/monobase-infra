# On-prem GCS Mirror — Runbook

Off-Google, **encrypted** on-prem mirror of the prod uploads bucket
`gs://mc-v4-prod.appspot.com` — **Tier 2** of the GCS DR design
([monobase-mycure#3878](https://github.com/mycurelabs/monobase-mycure/issues/3878);
Tier 1 = STS → separate GCP org). Sibling of the Velero/Kopia mirror
(`onprem-backup-setup.sh`) — deliberately separate so the live Spaces mirror is
never touched. Script: `scripts/gcs-onprem-mirror.sh`.

## Model

- `rclone sync gcs-src:<bucket> → gcs-crypt:current` on **niflheim** (the backup
  server), pulling through an rclone **crypt** remote so objects **and filenames
  land encrypted at rest**. Raw GCS objects are plaintext PHI — crypt is what
  keeps the on-prem copy (and any downstream replica) ciphertext-only.
- Deleted/overwritten objects are preserved (encrypted) under
  `gcs-crypt:archive/<date>` via `--backup-dir` — a source-side deletion or
  ransomware wipe can't erase the on-prem history.
- The crypt password lives **only on niflheim**. A host→host replica
  (`backup-mirror-setup.sh`, #400) receives **ciphertext only, never the
  password** — same model as the Kopia password. Restore supplies it at restore
  time.

## Prerequisites (not in the script)

1. **Read-only GCS SA** in `mc-v4-prod`: `roles/storage.objectViewer` on
   `mc-v4-prod.appspot.com` (list + read only). Download its JSON key.
2. **Crypt password** (+ optional salt): generate offline, **escrow it** with
   the same custody policy as the secrets-DR age key
   ([[secrets-dr-3882]] / #3882) — it is the GCS-mirror analogue of the Kopia
   password. Losing it = the on-prem copy is unrecoverable.
3. **Go-ahead on egress + capacity** (see below).

## Setup (on niflheim)

```bash
sudo GCS_SA_JSON=/root/mc-v4-prod-ro-sa.json \
     GCS_CRYPT_PASSWORD='…' GCS_CRYPT_PASSWORD2='…' \
     DISCORD_WEBHOOK_URL='https://discord.com/api/webhooks/…' \
  scripts/gcs-onprem-mirror.sh \
     --bucket=mc-v4-prod.appspot.com \
     --backup-dir=/mnt/storage/mycure-gcs        # 1.8T disk; NOT root FS
```
Installs pinned rclone, the `[gcs-src]`+`[gcs-crypt]` remotes, a bounded
`mycure-gcs` journal namespace, a Discord notifier, and the
`mycure-gcs-mirror`/`mycure-gcs-verify` timers (twice daily ~30m after the STS
run; weekly cryptcheck). Idempotent.

## Host→host fan-out to vanaheim (#400)

The crypt vault is just more encrypted blobs, so `backup-mirror-setup.sh` fans
it out unchanged — just make sure the replica's authorized pull path covers the
vault dir (`--backup-dir` above). vanaheim then holds ciphertext only.

## Verify

```bash
systemctl list-timers 'mycure-gcs-*'
sudo systemctl start mycure-gcs-mirror.service     # trigger a pull now
sudo journalctl --namespace=mycure-gcs -u mycure-gcs-mirror.service -f
sudo systemctl start mycure-gcs-verify.service     # rclone cryptcheck vs source
```
Encrypted-at-rest check: `file /mnt/storage/mycure-gcs/vault/<name>` → not a
recognizable image/pdf; contents are readable only *through* `gcs-crypt:`.

## Restore / break-glass

```bash
# Supply the crypt password at restore time (like Kopia). On niflheim OR vanaheim:
export RCLONE_CONFIG=<cfg-with-crypt-remote>
rclone copy gcs-crypt:current/<object-path> ./restore/          # latest
rclone copy gcs-crypt:archive/<date>/<object-path> ./restore/   # a prior version
rclone hash md5 ./restore/<obj>   # optional: compare to source md5/crc32c
# Full restore back to a bucket: rclone copy gcs-crypt:current gcs-src:<target-bucket>
```

## Restore drill (quarterly, on vanaheim — "local = testable")

Using **only** the replica's ciphertext + the crypt password: decrypt one object
and checksum it against the source; confirm an `archive/<date>` version restores.
Record the result on #3878 (mirrors #400's live-host verification and the PG
restore-drill precedent [[pg-backup-restore-drill]]).

## Cost & capacity (measure first)

- **Egress:** the pull leaves Google → **$0.12/GB** on the initial full copy,
  then only changed bytes per run. Measure the bucket first:
  `gcloud storage du -s gs://mc-v4-prod.appspot.com`.
- **Capacity:** the encrypted vault must fit `/mnt/storage` (1.8T; PG data-mover
  already uses ~188G) **plus** headroom on vanaheim. If the bucket is very large,
  scope Tier 2 with `--include-prefix` while keeping Tier 1 (STS) whole.
- STS/rclone software: $0; on-prem storage: existing hardware.
