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

1. **Read-only GCS SA** — ✅ **already provisioned** (2026-09-01):
   `gcs-dr-onprem-ro@mc-v4-prod.iam.gserviceaccount.com`, granted
   `roles/storage.objectViewer` on `gs://mc-v4-prod.appspot.com` (bucket-scoped).
   **No key minted yet** — mint it at rollout only (a long-lived key shouldn't
   sit around while the rollout is gated). See the rollout checklist below.
2. **Crypt password** (+ optional salt): generate offline, **escrow it** with
   the same custody policy as the secrets-DR age key
   ([[secrets-dr-3882]] / #3882) — it is the GCS-mirror analogue of the Kopia
   password. Losing it = the on-prem copy is unrecoverable.
3. **Go-ahead on egress + capacity** (see below).

## Rollout checklist (exact commands)

Run in order once #2/#3 above are decided. Steps 0–1 create credential material —
do them at rollout, not before.

```bash
# 0. Mint the SA key and land it on niflheim (off-GCP host can't use workload
#    identity, so it needs an exported key). Mint → scp → shred the local copy.
gcloud iam service-accounts keys create /tmp/gcs-dr-ro.json \
  --iam-account=gcs-dr-onprem-ro@mc-v4-prod.iam.gserviceaccount.com
scp /tmp/gcs-dr-ro.json hel.niflheim:/root/gcs-dr-ro.json
shred -u /tmp/gcs-dr-ro.json          # never leave the key on the workstation

# 1. Generate + ESCROW the crypt password and salt (reuse the #3882 custody).
openssl rand -base64 32     # -> GCS_CRYPT_PASSWORD  (escrow, do not commit)
openssl rand -base64 32     # -> GCS_CRYPT_PASSWORD2 (escrow, do not commit)

# 2. On niflheim, run the setup (measure size first for egress/capacity).
ssh hel.niflheim
gcloud storage du -s gs://mc-v4-prod.appspot.com   # confirm it fits /mnt/storage (1.8T; PG ~188G)
sudo GCS_SA_JSON=/root/gcs-dr-ro.json \
     GCS_CRYPT_PASSWORD='…' GCS_CRYPT_PASSWORD2='…' \
     DISCORD_WEBHOOK_URL='https://discord.com/api/webhooks/…' \
  /path/to/repo/scripts/gcs-onprem-mirror.sh \
     --bucket=mc-v4-prod.appspot.com \
     --backup-dir=/mnt/storage/mycure-gcs
sudo rm -f /root/gcs-dr-ro.json       # script copied it to /etc/mycure-gcs/; remove the drop

# 3. Trigger the first pull + confirm encrypted-at-rest.
sudo systemctl start mycure-gcs-mirror.service
sudo journalctl --namespace=mycure-gcs -u mycure-gcs-mirror.service -f

# 4. Wire the host→host fan-out (#400) to include /mnt/storage/mycure-gcs so
#    vanaheim pulls the ciphertext (see backup-mirror-setup.sh --role=source).
```
If rclone errors on bucket metadata (`storage.buckets.get`), add the fallback
role: `gcloud storage buckets add-iam-policy-binding gs://mc-v4-prod.appspot.com
--member=serviceAccount:gcs-dr-onprem-ro@mc-v4-prod.iam.gserviceaccount.com
--role=roles/storage.legacyBucketReader`.

**Teardown / revoke** (if abandoned): `gcloud iam service-accounts delete
gcs-dr-onprem-ro@mc-v4-prod.iam.gserviceaccount.com` (removes the SA + its
bucket binding + any keys).

## Setup (on niflheim)

```bash
sudo GCS_SA_JSON=/root/gcs-dr-ro.json \
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
