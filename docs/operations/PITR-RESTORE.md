# PostgreSQL Point-in-Time Recovery (PITR) — WAL Archiving Runbook

Continuous WAL archiving (via `wal-g`) + a base backup gives **recovery to any
second**, cutting the PostgreSQL RPO from ~24h (daily Velero backup) to ~1
minute. This is the mechanism from issue [#3870](https://github.com/mycurelabs/monobase-mycure/issues/3870),
added after the **2026-08-28** incident where the only recovery point was a
~23h-old Velero backup and ~23h of clinical records were unrecoverable.

> **Status:** live and PITR-proven in **both `mycure-preprod` and
> `mycure-production`** (prod enabled 2026-08-29; prod restore drill **ran
> 2026-09-01**, recovering to target `2026-08-30 19:00:00+00` — an exact second,
> `restored_medical_records` correctly fewer than live). The restore recipe in step 3 below was
> **independently re-drilled in `mycure-preprod` 2026-09-01** — fetch → the
> finding-6 blocker reproduced verbatim → finding-5 param abort reproduced
> verbatim → fix applied → `consistent recovery state reached` / `pausing at end
> of recovery`, data queryable, timeline not forked. This runbook is a
> *correctness requirement*, not documentation: findings 4, 5 & 6 cannot be
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
| *(optional)* second on-prem copy of the WAL prefix, pulled every minute | `scripts/onprem-backup-setup.sh --wal-mirror` — see [ONPREM_BACKUP_SETUP.md](ONPREM_BACKUP_SETUP.md#wal-archive-mirror-pitr-second-copy). Restore from it via `WALG_FILE_PREFIX` if Spaces is unreachable. |

**Why the base backup is an exec-into-primary CronJob:** `wal-g backup-push`
reads the primary's `$PGDATA` files directly (it only calls `pg_backup_start/stop`
over the connection — it does *not* stream a base backup over the replication
protocol). The data PVC is DigitalOcean block storage = **ReadWriteOnce**, so no
second pod can mount it. Every operator-less `wal-g` setup runs `backup-push`
inside the DB pod; ours is a `CronJob` that `kubectl exec`s into
`postgresql-primary-0`.

---

## Six things the rehearsals caught (all still apply)

In every one, WAL archiving reported **healthy** (`pg_stat_archiver.failed_count
= 0`) while recovery was impossible. That is the same shape as the incident this
prevents — the rehearsal is not optional. Findings 1–5 are from the preprod
rehearsal; finding 6 (the drill *blocker*) surfaced only in the 2026-09-01
production drill.

1. **uid 1001 has no `/etc/passwd` entry** in the Bitnami image → `wal-g`'s cgo
   build aborts `backup-push`/`backup-list`/`backup-fetch` with `user: unknown
   userid 1001`. `wal-push` does *not* do the lookup, so archiving works while
   every restore/backup command fails. **Fixed** by the `postgresql-walg-passwd` mount (on `main`).
2. **`backup-push` needs PG credentials** (`PGHOST`/`PGUSER`/`PGPASSWORD`) to
   call `pg_backup_start`. The CronJob injects them; archiving alone does not.
3. **`default-deny-egress` blocks the backup Job from the API server.** The Job
   pod runs `kubectl` (get pod + exec); the namespace is default-deny and, unlike
   the primary (allow-all egress), it has no rule — so it can't reach the API
   server and fails with `dial tcp <apiserver>:443: i/o timeout`. Fixed by the
   `walg-backup` NetworkPolicy (DNS + 443) that ships with the CronJob. The Job
   never talks to Spaces itself — the exec'd `wal-g` runs in the primary, which
   has its own egress. A *restore* pod in another namespace still needs its own.
4. **Bitnami keeps `pg_hba.conf` OUTSIDE `PGDATA`** → it is not in the base, so a
   restored base backup won't start until you supply it. **Runbook requirement.**
   `pg_ident.conf`, by contrast, lives *inside* `PGDATA` (verified: `ident_file =
   /bitnami/postgresql/data/pg_ident.conf`), so `backup-fetch` restores it
   automatically — **do not** try to `cp` it (Joff's original `cp … pg_ident.conf`
   from the conf dir would fail: it isn't there, and under `set -e` that aborts
   the whole restore).
5. **Bitnami keeps `extendedConfiguration` in `conf.d`, outside `PGDATA`** → a
   restore starts with `max_connections=100` against a primary that ran 300 and
   Postgres refuses: *"recovery aborted because of insufficient parameter
   settings"*. You **must** mirror these at recovery time (independently confirmed
   on the live preprod primary 2026-09-01, and prod runs the identical set;
   `server_version 16.4`, `wal_level=replica`):

   ```text
   max_connections = 300
   max_wal_senders = 16
   max_worker_processes = 8      # the default; extendedConfiguration raises
                                 # autovacuum_max_workers=6 but never this
   max_locks_per_transaction = 64
   max_prepared_transactions = 0
   ```
6. **Bitnami keeps `postgresql.conf` OUTSIDE `PGDATA` too** (in
   `/opt/bitnami/postgresql/conf/`) → `backup-push` never captures it, so
   `backup-fetch` gives a valid data dir **no Postgres can open**:
   *"could not access the server configuration file
   `/bitnami/postgresql/data/postgresql.conf`: No such file or directory"*.
   **This blocked the production drill.** Copy it into `PGDATA` and neuter its
   `include_dir` (the `conf.d` it references lives outside `PGDATA`) — see restore
   step 3.

---

## Restore — Path A: wal-g native base (primary method, re-drilled 2026-09-01)

Restore into a **scratch namespace/PVC**, never over a live primary. `wal-g`
env (`WALG_S3_PREFIX`, `AWS_*`) must be present in the restore pod. **Use a
read-only Spaces key** for restore pods — it makes archive pollution (a promoted
timeline fork) and accidental `wal-g delete` *structurally* impossible rather
than procedurally avoided.

```bash
# 0. Pick the target. T = the second to recover to (just before the bad event).
T="2026-08-28 14:31:59+00"

# 1. List available base backups; pick the newest one whose start time is
#    BEFORE T (do NOT blindly use LATEST — a base taken after T already
#    contains the bad data and can't be rolled back past its start).
kubectl exec postgresql-primary-0 -c postgresql -- \
  /opt/wal-g/wal-g backup-list --detail
BASE=base_000000010000...   # the name from the list that predates T

# 2. In a scratch pod with the wal-g image + WALG_S3_PREFIX/AWS_* + the passwd
#    mount, fetch that base into an empty PGDATA:
wal-g backup-fetch /bitnami/postgresql/data "$BASE"    # LATEST only if it predates T

# 3. Supply the two config files that live OUTSIDE PGDATA and are therefore NOT
#    in the base (findings 4 & 6 — verified by drill 2026-09-01: a fetched base
#    contains pg_ident.conf + postgresql.auto.conf but NOT postgresql.conf or
#    pg_hba.conf). Source them from the restore image's conf dir; the wal-g /
#    bitnami postgresql image ships both there.
D=/bitnami/postgresql/data
cp /opt/bitnami/postgresql/conf/postgresql.conf "$D/postgresql.conf"      # finding 6 (BLOCKER)
sed -i 's|^include_dir|#include_dir|' "$D/postgresql.conf"                # conf.d lives outside PGDATA
cp /opt/bitnami/postgresql/conf/pg_hba.conf "$D/pg_hba.conf"
# DO NOT copy pg_ident.conf — it lives INSIDE PGDATA, so backup-fetch already
# restored it (verified). Copying a stray one over it is wrong. With no
# hba_file/ident_file set in the copied conf, Postgres resolves both from PGDATA.

cat >> "$D/postgresql.auto.conf" <<EOF
restore_command = '/opt/wal-g/wal-g wal-fetch %f %p'
recovery_target_time = '$T'
# DRILL SAFETY: 'pause' stops at the target WITHOUT forking the timeline.
# 'promote' forks to TLI 2 and — if archiving is on with the same prefix —
# writes that fork into the PRODUCTION archive. Only use 'promote' for a real
# recovery you intend to keep.
recovery_target_action = 'pause'
archive_mode = off
# finding 5 — mirror the live primary or Postgres refuses to start:
max_connections = 300
max_wal_senders = 16
max_worker_processes = 8
max_locks_per_transaction = 64
max_prepared_transactions = 0
EOF
touch "$D/recovery.signal"

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

> ⬜ **Open follow-up B — retention deletion unexercised:** with only 2 bases the
> delete correctly no-ops (`No objects matched the deletion criteria`; verified as
> a dry-run on preprod 2026-09-01). It won't actually delete until the 5th weekly
> base (~4 weeks out). **Do a manual `--confirm`-less dry-run before then** to
> confirm it drops the *oldest* base, not — via the `pg_upgrade` sort footgun
> below — the newest.

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

> **Disabling archiving:** don't just flip `walg.enabled: false` to pause it —
> that prunes the `postgresql-walg-passwd` ConfigMap the primary mounts at
> `/etc/passwd`, so the next primary restart fails
> (`MountVolume.SetUp failed: configmap "postgresql-walg-passwd" not found`).
> To pause, set `archive_command` to a no-op (or `archive_mode=off`, needs a
> restart) and leave `walg.enabled` on; only remove `walg.enabled` together with
> the `postgresql.primary` passwd volume/mount.

---

## Drill checklist (repeat quarterly — proven 2026-08-29)

1. Insert marker **A**; note timestamp **T**; after T insert marker **B**.
2. Restore a base backup into a scratch pod, replay WAL to **T** (Path A).
3. Assert: **A present, B absent**, application data intact.
4. Confirm the log shows `recovery stopping before commit of transaction …`.
5. For Path B, repeat once from a Velero snapshot base.

`wal-g wal-verify integrity` between drills catches WAL-chain gaps proactively
(wal-g's verification is weaker than pgBackRest's — the drill is what matters).
It **needs PG credentials** (`PGHOST`/`PGUSER`/`PGPASSWORD`) — same class as
finding 2 — and fails `password authentication failed for user "postgres"`
without them. This is the command you reach for at 3am to answer "can we
actually recover?", so don't discover the missing creds then.

---

## Cost / storage / scale

DO Spaces bills **$0 per request** and **free inbound**, so `archive_timeout=60`
(a segment/minute) costs nothing in requests, and archiving traffic is free.
Storage is $0.02/GiB-mo over the 250 GiB base.

- **WAL — MEASURED from actual Spaces usage 2026-09-01 (not extrapolated):**
  prod `wal/mycure-production/wal_005` = **6.15 GB compressed over 2.64 days =
  ~2.33 GB/day**. The raw segment count (~1,876/day ≈ **29 GiB/day uncompressed**)
  overstates the footprint ~13×: with `archive_timeout=60` a large fraction of
  segments are timeout-forced and near-empty (preprod, which sits at the pure
  1440-seg/day floor, compresses **360×** to ~45 KB/segment; its whole WAL history
  is ~65 MB/day). So the compressed figure lands **below** the original 5–20
  GB/day estimate — **use billed bytes, never the raw segment count, for cost.**
- **Base backups (measured):** prod `basebackups_005` = 80.6 GB for 2 bases ≈
  **~37.5 GiB each** compressed; `retain FULL 4` ≈ **~150 GiB**.
- **Total prod PITR footprint (measured):** ≈ 150 GiB bases + ~4 weeks WAL
  (~61 GiB) ≈ **~210 GiB ≈ ~$4/mo incremental** — a rounding error beside the
  Velero snapshots already in the same bucket.
- **Scale risk = operational, not $:** a stalled archiver fills `pg_wal`. Confirm
  the `pg_wal` PV has headroom for a multi-hour outage; the alerts + PV-fill
  backstop cover it. Weekly fulls bound WAL replay (and RTO) to ≤7 days.

---

## Production rollout — DONE (2026-08-29)

Enabled in production 2026-08-29: primary rolled cleanly (~36s restart), first
base `base_0000000100000322000000B8` (start LSN `322/B8000028`, ~157 GB in ~17
min) in Spaces, `pg_stat_archiver.failed_count = 0`. Restore drill **ran
2026-09-01** (recovering to target `2026-08-30 19:00:00+00`; see Status). The
steps that were followed, for reference / other environments:

1. Push the image to GHCR (see `docker/wal-g/Dockerfile` header).
2. Mirror the `walg` / `metrics` / `primary.initContainers` / `extraVolumes` /
   `extraVolumeMounts` / `extraEnvVars` blocks into
   `values/deployments/mycure-production.yaml` with
   `WALG_S3_PREFIX=…/wal/mycure-production`.
3. Restart the primary; take the first `backup-push` immediately.
4. Alerts already match `*-production` namespaces — they light up on flip.

See also: [BACKUP_DR.md](BACKUP_DR.md) (Velero, whole-namespace, RPO 24h).
