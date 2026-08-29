# PostgreSQL Point-in-Time Recovery (PITR) — WAL Archiving Runbook

Continuous WAL archiving (via `wal-g`) + a base backup gives **recovery to any
second**, cutting the PostgreSQL RPO from ~24h (daily Velero backup) to ~1
minute. This is the mechanism from issue [#3870](https://github.com/mycurelabs/monobase-mycure/issues/3870),
added after the **2026-08-28** incident where the only recovery point was a
~23h-old Velero backup and ~23h of clinical records were unrecoverable.

> **Status:** live and PITR-proven in `mycure-preprod`. **Production is not yet
> enabled** — see [Production rollout](#production-rollout). This runbook is a
> *correctness requirement*, not documentation: findings 4 & 5 below cannot be
> re-derived during an incident.

---

## How it works (and why base backup + WAL are two halves of one thing)

| | What it is | Alone it gives |
|---|---|---|
| **Base backup** | A physical copy of the data dir at a known LSN | A DB frozen at one instant |
| **WAL archive** | Every write, shipped off-box as 16 MB segments | A change log with no start point |
| **Both** | base + replay to `recovery_target_time` | **Any second**, to the second |

The base backup is a photograph; the WAL archive is the video from that moment
on. The video is useless without the photo to start from. This is the canonical
PostgreSQL PITR mechanism (docs ch. 26.3) — the same thing RDS/Cloud SQL and
every mature K8s operator (CloudNativePG, Zalando, Crunchy) implement under the
hood. We use `wal-g` (the natural fit for object-storage / cloud-native; note
pgBackRest went unmaintained April 2026).

**Velero is complementary, not redundant.** Velero backs up the whole namespace
(K8s resources, MinIO, Valkey) at discrete daily points — it *cannot* do PITR
(no snapshot frequency can stop at 14:31:59 before a bad 14:32 `DELETE`). WAL is
a continuum; Velero is discrete points. Keep both:

```text
Velero        → rebuild the environment   (discrete, whole-namespace, RPO 24h)
base backup   → the anchor for replay
WAL archive   → roll forward from the anchor to any second   (RPO ~1min)
```

---

## What is deployed

| Piece | Where |
|---|---|
| `archive_mode=on`, `archive_command='/opt/wal-g/wal-g wal-push %p'`, `archive_timeout=60` | `values/deployments/mycure-preprod.yaml` (`postgresql.primary.extendedConfiguration`) |
| `wal-g` v3.0.9 binary (initContainer → emptyDir; PG container is read-only-rootfs) | `docker/wal-g/Dockerfile`, same values |
| WAL → DO Spaces `s3://mycure-doks-velero-backups/wal/mycure-preprod`, zstd | same (`extraEnvVars`) |
| Spaces creds (shared Velero key) via ExternalSecret | `charts/database-secrets/templates/walg-externalsecret.yaml` |
| **Base backup + retention CronJob** (weekly `backup-push` + `delete retain FULL 4`) | `charts/database-secrets/templates/walg-backup.yaml` (gated `walg.backup.enabled`) |
| uid-1001 `/etc/passwd` mount on the primary | `postgresql-walg-passwd` ConfigMap + `postgresql.primary.extraVolumes` |
| Alerts `PostgresWALArchiveFailing` / `PostgresWALArchiveStalled` | `charts/monitoring-resources/templates/prometheus-rules.yaml` |

**Why the base backup is an exec-into-primary CronJob:** `wal-g backup-push`
reads the primary's `$PGDATA` files directly (it only calls `pg_backup_start/stop`
over the connection — it does *not* stream a base backup over the replication
protocol). The data PVC is DigitalOcean block storage = **ReadWriteOnce**, so no
second pod can mount it. Every operator-less `wal-g` setup runs `backup-push`
inside the DB pod; ours is a `CronJob` that `kubectl exec`s into
`postgresql-primary-0`.

---

## Five things the preprod rehearsal caught (all still apply)

In every one, WAL archiving reported **healthy** (`pg_stat_archiver.failed_count
= 0`) while recovery was impossible. That is the same shape as the incident this
prevents — the rehearsal is not optional.

1. **uid 1001 has no `/etc/passwd` entry** in the Bitnami image → `wal-g`'s cgo
   build aborts `backup-push`/`backup-list`/`backup-fetch` with `user: unknown
   userid 1001`. `wal-push` does *not* do the lookup, so archiving works while
   every restore/backup command fails. **Fixed** by the `postgresql-walg-passwd` mount (on `main`).
2. **`backup-push` needs PG credentials** (`PGHOST`/`PGUSER`/`PGPASSWORD`) to
   call `pg_backup_start`. The CronJob injects them; archiving alone does not.
3. **`default-deny-egress`** — the backup Job reaches Spaces via the
   namespace-wide 443 egress allow. A *restore* pod in another namespace needs
   its own egress rule.
4. **Bitnami keeps `pg_hba.conf` / `pg_ident.conf` OUTSIDE `PGDATA`** → a
   restored base backup won't start until you supply them. **Runbook requirement.**
5. **Bitnami keeps `extendedConfiguration` in `conf.d`, outside `PGDATA`** → a
   restore starts with `max_connections=100` against a primary that ran 300 and
   Postgres refuses: *"recovery aborted because of insufficient parameter
   settings"*. You **must** mirror these at recovery time:

   ```text
   max_connections = 300
   max_wal_senders          # match primary
   max_worker_processes     # match primary
   max_locks_per_transaction
   max_prepared_transactions
   ```

---

## Restore — Path A: wal-g native base (primary method, rehearsed 2026-08-29)

Restore into a **scratch namespace/PVC**, never over a live primary. `wal-g`
env (`WALG_S3_PREFIX`, `AWS_*`) must be present in the restore pod.

```bash
# 0. Pick the target. T = the second to recover to (just before the bad event).
T="2026-08-28 14:31:59+00"

# 1. List available base backups; confirm one predates T.
kubectl exec postgresql-primary-0 -c postgresql -- \
  /opt/wal-g/wal-g backup-list --detail

# 2. In a scratch pod with the wal-g image + WALG_S3_PREFIX/AWS_* + the passwd
#    mount, fetch the latest base backup that predates T into an empty PGDATA:
wal-g backup-fetch /bitnami/postgresql/data LATEST     # or a named base before T

# 3. Supply the Bitnami-external configs (finding 4) into the restored PGDATA,
#    and the recovery-time parameters (finding 5):
cp pg_hba.conf pg_ident.conf /bitnami/postgresql/data/
cat >> /bitnami/postgresql/data/postgresql.auto.conf <<EOF
restore_command = '/opt/wal-g/wal-g wal-fetch %f %p'
recovery_target_time = '$T'
recovery_target_action = 'promote'
max_connections = 300
max_wal_senders = <match primary>
max_worker_processes = <match primary>
max_locks_per_transaction = <match primary>
max_prepared_transactions = <match primary>
EOF
touch /bitnami/postgresql/data/recovery.signal

# 4. Start Postgres. It crash-recovers from the base, then replays archived WAL
#    forward and STOPS at T. Confirm in the log:
#      recovery stopping before commit of transaction NNNNN
#      last completed transaction was at log time ...
```

> Recovery is *greedy* by default — without `recovery_target_time` it replays
> **all** WAL to the latest point. Always set the target to stop before the event.

---

## Restore — Path B: Velero CSI snapshot as the base (fallback, $0 to keep)

A Velero daily CSI snapshot **is** a valid PITR base — the PG PVC is one volume
holding PGDATA + `pg_wal`, the snapshot is atomic, `full_page_writes=on`, so
Postgres crash-recovers from it and then replays archived WAL. Use this if the
`wal-g` base catalog is unavailable.

```bash
# 1. Restore the daily Velero backup that PRECEDES T into a scratch namespace
#    (provisions a PVC from the CSI snapshot).
velero restore create --from-backup <daily-before-T> \
  --include-namespaces mycure-preprod --namespace-mappings mycure-preprod:pitr-restore

# 2. On the restored PGDATA, set the SAME recovery config as Path A step 3
#    (restore_command = wal-g wal-fetch, recovery_target_time = T, recovery.signal,
#    and the finding-4/finding-5 configs). Start Postgres → replays WAL to T.
```

Difference from Path A: the base is Velero's (on Velero's TTL), not in the
`wal-g` catalog. **If you ever rely on Path B for retention, prune WAL by age
aligned to Velero's TTL** — never leave WAL shorter than the oldest Velero daily
you'd restore from.

---

## Retention & the `pg_upgrade` footgun

The CronJob runs `wal-g delete retain FULL 4 --confirm` — keeps the last 4 weekly
bases **and the WAL needed to replay from them** (base-relative, never age-based;
age-based pruning silently orphans bases you still depend on).

> **After any PostgreSQL major-version upgrade (`pg_upgrade`)**, the timeline
> prefix in backup names changes, breaking `delete retain FULL`'s alphabetic
> sort — it can delete the **newest** bases ([wal-g #636](https://github.com/wal-g/wal-g/issues/636)).
> **Verify `wal-g backup-list` before any destructive delete post-upgrade.**

---

## Emergency: `pg_wal` filling the volume

If `archive_command` fails, Postgres stops recycling WAL, `pg_wal` grows, and the
DB halts when the volume fills — the failure mode the alerts exist to catch.

1. **Alert fires** (`PostgresWALArchiveFailing` / `…Stalled`). Fix the cause:
   check the `postgresql-walg` secret and Spaces reachability. Once archiving
   succeeds, Postgres recycles the backlog automatically.
2. **If the volume is already full:** add space (expand the PVC) or delete a
   pre-staged dummy file on the mount to get Postgres running.
3. **Last resort only** (accepts a broken WAL chain): temporarily set
   `archive_command = /bin/true` to let Postgres recycle, then **immediately take
   a fresh base backup** — the archive is valid only up to the break.

---

## Drill checklist (repeat quarterly — proven 2026-08-29)

1. Insert marker **A**; note timestamp **T**; after T insert marker **B**.
2. Restore a base backup into a scratch pod, replay WAL to **T** (Path A).
3. Assert: **A present, B absent**, application data intact.
4. Confirm the log shows `recovery stopping before commit of transaction …`.
5. For Path B, repeat once from a Velero snapshot base.

`wal-g wal-verify integrity` between drills catches WAL-chain gaps proactively
(wal-g's verification is weaker than pgBackRest's — the drill is what matters).

---

## Cost / storage / scale

DO Spaces bills **$0 per request** and **free inbound**, so `archive_timeout=60`
(a segment/minute) costs nothing in requests, and archiving traffic is free.
Storage is $0.02/GiB-mo over the 250 GiB base.

- **WAL:** preprod 0.5–2 GB/day compressed; **prod estimate 5–20 GB/day — measure
  after 48h** via `pg_stat_archiver` + Spaces usage before extrapolating.
- **Base backups:** 188 GB → zstd ≈ ~70 GB each; `retain FULL 4` ≈ 280 GB.
- **Total prod PITR footprint** ≈ ~560 GB ≈ **~$11/mo incremental** — a rounding
  error beside the Velero snapshots already in the same bucket.
- **Scale risk = operational, not $:** a stalled archiver fills `pg_wal`. Confirm
  the `pg_wal` PV has headroom for a multi-hour outage; the alerts + PV-fill
  backstop cover it. Weekly fulls bound WAL replay (and RTO) to ≤7 days.

---

## Production rollout

Preprod-only today. To enable production (needs a brief primary **restart** for
`archive_mode`, scheduled outside clinic hours):

1. Push the image to GHCR (see `docker/wal-g/Dockerfile` header).
2. Mirror the `walg` / `metrics` / `primary.initContainers` / `extraVolumes` /
   `extraVolumeMounts` / `extraEnvVars` blocks into
   `values/deployments/mycure-production.yaml` with
   `WALG_S3_PREFIX=…/wal/mycure-production`.
3. Restart the primary; take the first `backup-push` immediately.
4. Alerts already match `*-production` namespaces — they light up on flip.

See also: [BACKUP_DR.md](BACKUP_DR.md) (Velero, whole-namespace, RPO 24h).
