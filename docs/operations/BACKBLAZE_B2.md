# Backblaze B2 — off-provider backup destination

A second, **independent-cloud-provider** copy of production backups, so a DigitalOcean
Spaces outage — or account loss/compromise — no longer means zero recoverable backups.
Motivated by the 2026-08-28 data-loss incident (the risk this workstream exists to remove).
Tracked in [mycurelabs/monobase-mycure#4007]; PRs #406 (setup), #410 (native-b2 fix),
#412 (OOM fix).

B2 is the **off-provider cloud tier** — complementary to the on-prem mirror (Tier 4). See
the tier table in [BACKUP_DR.md](BACKUP_DR.md).

## What lands in B2

| Data | Mechanism | Where |
|---|---|---|
| Velero backups (whole `mycure-production` namespace incl. PG data PVCs) | **Native dual-write** | B2 bucket, prefix `infrastructure/` + per-app |
| PostgreSQL WAL archive (wal-g base backups + WAL segments) | **Async mirror** | B2 bucket, prefix `wal/mycure-production` |

Bucket `mycure-velero-backblaze-b2-backups` · region `us-east-005` ·
endpoint `s3.us-east-005.backblazeb2.com`.

## Why two mechanisms (not one)

The two backup systems can't be handled the same way — this is load-bearing, don't "simplify":

- **Velero has no native mirror** and can't write one backup to two locations. Its blessed
  redundancy is **duplicate Schedules** to a *distinct* bucket. So B2 gets a second,
  non-default `BackupStorageLocation` (`backblaze`) plus duplicate Schedules
  (`*-backblaze`), **staggered** off the primary crons so the ~382 GiB prod PVCs aren't
  snapshotted twice at once. These are **independent Kopia repos** in B2 — not copies of
  the DO backup — so they must be restore-tested on their own.
- **wal-g cannot dual-write WAL** (upstream [wal-g#180]; "failover storages" is
  fallback-only). So WAL reaches B2 only via an **async rclone mirror** of the `wal/`
  prefix (every 15 min → low secondary RPO, and B2 stays out of PostgreSQL's
  `archive_command` critical path). The proper long-term fix (wal-g → pgBackRest native
  multi-repo) is tracked in #4008.

## Credentials

- One shared GCP Secret Manager secret `monobase-backblaze-b2` (project `mc-v4-prod`),
  JSON `{access_key, secret_key}` — same shape as `monobase-digitalocean-spaces`. Use a
  **bucket-scoped B2 application key** (least privilege), not the master key.
- Synced via `gcp-secretstore` (ESO) into two k8s secrets in the `velero` namespace:
  `velero-credentials-b2` (aws-ini for the BSL) and `backblaze-mirror-credentials`
  (DO source + B2 dest keys for the mirror).

## Two hard-won gotchas (B2-specific)

1. **Object Lock ⇒ the mirror MUST use rclone's native `b2` backend, not S3.** The bucket
   has Object Lock, which requires a `Content-MD5` on every `PutObject`. Objects streamed
   from DO Spaces have **no source MD5** (Spaces returns `hashes=None` for
   multipart-uploaded objects), so an rclone **s3→s3** copy has nothing to send and B2
   returns `400 InvalidRequest` (base-backup `part_*.tar.zst` all fail). The native `b2`
   backend (`RCLONE_CONFIG_DST_TYPE=b2`, `ACCOUNT`=keyID, `KEY`=appKey) computes B2's
   `X-Bz-Content-Sha1` while streaming → Object Lock satisfied. (#410)
2. **rclone memory must be bounded** or the mirror pod OOMKills on large deltas. Drop
   `--fast-list` (it buffers the whole listing) and cap upload buffers
   (`--transfers 4 --b2-chunk-size 32M --b2-upload-concurrency 2`), limit 1Gi. (#412)

## Immutability (air gap)

- Object Lock **default 14-day retention** + versioning ("keep all versions") on the
  bucket. A `rclone sync` delete only writes a hide-marker; the locked version survives
  14 days → data destroyed on DO stays recoverable on B2 for 14 days.
- 14d < Velero TTL (14–90d) and wal-g retention, so expiry `Delete`s are never blocked.
- **Required:** a B2 **lifecycle rule** to hard-delete non-current versions after ≥14d,
  or the versioned+locked copy grows unbounded.
- If Object Lock is ever removed, B2 protects against a DO **outage** only — **not** data
  destruction. Don't plan recovery around an air gap that isn't there.

## Account tier / cost

Requires a **paid B2 plan** with the storage cap raised/removed — the real volume is
multi-TB (WAL + versioned, 14d-locked prod Velero backups). B2 storage ≈ $6/TB-month;
egress (restore) is free up to 3× stored/month.

## Restore from B2

Same as any Velero restore, but targeting the `backblaze` backup/BSL. The data-mover
(`DataDownload`) needs `velero-repo-credentials` (Kopia password `monobase-velero-repo-password`)
in the `velero` namespace.

**Surgical PG-data-volume restore into an isolated namespace (drill / partial recovery):**

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata: { name: b2-verify-pg-<date>, namespace: velero }
spec:
  backupName: production-daily-backblaze-<ts>   # pick one with phase=Completed, failedOps=0
  includedResources: [persistentvolumeclaims]
  labelSelector: { matchLabels: { app.kubernetes.io/name: postgresql, app.kubernetes.io/component: primary } }
  namespaceMapping: { mycure-production: velero-restore-test }
  restorePVs: true
  itemOperationTimeout: 4h0m0s
```

Then verify the restored PVC with a throwaway `bitnamilegacy/postgresql:16.x` pod (uid 1001
matches the data ownership): `pg_controldata /bitnami/postgresql/data` first (valid/consistent
cluster, no config needed), then boot — remembering the Bitnami gotcha that `postgresql.conf`
/ `pg_hba.conf` live **outside** PGDATA (supply them; do **not** copy `pg_ident.conf`, which is
inside PGDATA). For a full-cluster rebuild from B2 alone, see the "Restore to new cluster" path
in [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md) (point Velero at the B2 bucket instead of
the on-prem mirror). Clean up the restored 400 GiB volume afterwards — it's a real DO block
volume that keeps billing.

## Operations

```bash
# B2 Velero backups + their phase
kubectl -n velero get backups.velero.io | grep backblaze

# BSL health
kubectl -n velero get bsl backblaze

# WAL mirror runs (should Complete, not OOMKilled)
kubectl -n velero get jobs | grep backblaze-wal-mirror
kubectl -n velero get cronjob backblaze-wal-mirror

# ExternalSecrets synced
kubectl -n velero get externalsecret velero-credentials-b2 backblaze-mirror-credentials
```

Config lives in `charts/velero-resources/templates/{backup-locations,schedules-backblaze,backblaze-mirror}.yaml`
and `values/clusters/mycure-doks-main/argocd/infrastructure.yaml` (`velero.backblaze.*`,
gated on `enabled`).

## Related

- [BACKUP_DR.md](BACKUP_DR.md) · [PITR-RESTORE.md](PITR-RESTORE.md) ·
  [RESTORE_FROM_ONPREM.md](RESTORE_FROM_ONPREM.md) · [BACKUP_MIRROR_TIERS.md](BACKUP_MIRROR_TIERS.md)
- Issue #4007 (setup), #4008 (pgBackRest migration eval)

[mycurelabs/monobase-mycure#4007]: https://github.com/mycurelabs/monobase-mycure/issues/4007
[wal-g#180]: https://github.com/wal-g/wal-g/issues/180
