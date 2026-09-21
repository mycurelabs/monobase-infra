# PG Logical Backup — logical `pg_dump` DR tier (monobase-mycure#4320)

The physical backup tiers (Velero/Kopia volume snapshots, wal-g PITR WAL, the
GCS-DR blob mirror) are all **physical** — tied to the PG major version + the
Bitnami block format, and they faithfully replicate logical corruption. This
chart adds the missing **logical** tier: a nightly, portable `pg_dump -Fc` of the
`hapihub` database, dumped from the **read replica**, integrity-checked,
crypt-encrypted, and shipped off-cloud to niflheim. It restores into *any*
Postgres ≥ source, on any host, with **no cluster rebuild** and **selective
(table-level) restore**.

- Chart: [`charts/pg-logical-backup`](../../charts/pg-logical-backup)
- Overlay: `values/deployments/mycure-preprod.yaml` (`pgLogicalBackup:`), staged
  **disabled**.
- Cross-links: [BACKUP_DR.md](BACKUP_DR.md), [PITR-RESTORE.md](PITR-RESTORE.md).

---

## Activation prerequisites (out-of-band)

Do ALL of these **before** setting `pgLogicalBackup.enabled: true`:

1. **Seed the two GCP Secret Manager keys** (handoff to Joff / IAM):
   - `mycure-preprod-pg-logical-backup-db-password` — a strong random password
     for the read-only `dumper` role.
   - `mycure-preprod-pg-logical-backup-rclone-conf` — an rclone config with a
     `crypt` remote named `pgdump-crypt` wrapping the backend niflheim pulls
     from (sftp-to-niflheim, or an object-store prefix). The crypt password lives
     ONLY here.
   ESO syncs both via **`ClusterSecretStore/gcp-secretstore`** (the cluster-wide
   store this cluster actually provides — not a per-namespace `SecretStore`).

2. **Pin the egress destination.** `networkPolicy.destinations` must contain
   niflheim's real tailnet `/32` (+ port 22 for sftp, or 443 for an HTTPS object
   store). The overlay ships a **placeholder** `100.64.0.0/10` — replace it with
   the confirmed peer IP. The chart **fails to render** if the backup is enabled
   with no destination pinned (never `0.0.0.0/0`).

3. **niflheim receive/pull side** — configure niflheim's rclone timer to pull (or
   receive) `pgdump-preprod/` into its storage.

4. **Pass the restore drill (below).** Evidence-before-activation.

5. Flip `pgLogicalBackup.enabled: true` (and `suspend: false`).

---

## The restore gate (finding #5 — real scratch-restore, not `--list`)

`pg_restore --list` validates only the archive table-of-contents. Even the
in-CronJob **full-decompress** check (`pg_restore -> /dev/null`, which reads and
decompresses every DATA block — a real upgrade over `--list`) only proves the
archive is *readable*. Neither proves the dump **restores into a working database
with rows**. Two things close that gap:

### A. Out-of-cluster drill (run this before activation)

[`scripts/pg-logical-backup-restore-drill.sh`](../../scripts/pg-logical-backup-restore-drill.sh)
pulls the newest crypt dump, restores it into a **throwaway Docker Postgres**
(nothing touches prod, nothing persists), and asserts the required tables came
back non-empty. Non-zero exit = **do not activate**.

```bash
scripts/pg-logical-backup-restore-drill.sh \
  --remote pgdump-crypt:pgdump-preprod \
  --rclone-conf ~/.config/rclone/rclone.conf \
  --require organizations,accounts --min-rows 1
# … [drill] PASS — dump restores into a working database (N rows verified). Safe to activate.
```

### B. In-cluster gate (`restoreVerify` Job)

For a gate that runs *inside* the cluster (CI / pre-promotion, no Docker host),
enable the `restore-verify` Job. It spins a **throwaway Postgres server inside its
own pod** (`initdb` on an emptyDir), restores the newest crypt dump into a scratch
database, and asserts row counts — then dies with the pod. It is **not** part of
the nightly path.

> **Values nesting (finding #3).** This chart is deployed by the ArgoCD
> Application factory (`charts/argocd-applications` + `appRegistry` in
> `values/deployments/base.yaml`), which extracts the overlay's **`pgLogicalBackup:`
> sub-tree** and passes it to the chart **at its root** (plus `global`). So the
> chart reads `.Values.enabled`, **not** `.Values.pgLogicalBackup.enabled`.
> Feeding the whole overlay with `-f values/deployments/mycure-preprod.yaml
> --set pgLogicalBackup.enabled=true` renders **zero** resources (the chart never
> looks under `pgLogicalBackup.*`). Extract the sub-tree first, exactly as the
> factory does:

```bash
# 1. Extract the overlay's pgLogicalBackup block as chart-root values
#    (this is what the ArgoCD factory feeds the chart).
yq eval '.pgLogicalBackup' values/deployments/mycure-preprod.yaml > /tmp/pglb-vals.yaml

# 2. Render the restore-verify Job. networkPolicy.enabled=false: the restore
#    gate only FETCHES + restores into a throwaway PG (no off-cloud upload), so
#    the egress guard is irrelevant here — turning it off avoids the (correct)
#    fail-closed guard that blocks a render with no /32 destination pinned.
helm template pg-logical-backup charts/pg-logical-backup \
  -f /tmp/pglb-vals.yaml \
  --set enabled=true \
  --set restoreVerify.enabled=true \
  --set networkPolicy.enabled=false \
  --set global.namespace=mycure-preprod \
  --show-only templates/restore-verify-job.yaml \
  | kubectl apply -f -   # then watch the Job, expect "[restore] PASS"
```

To eyeball the manifest without applying, drop the `| kubectl apply -f -`. To
render the FULL app (CronJob + provision + ExternalSecret + restore-verify) as
ArgoCD would, drop `--show-only` and pin a valid destination
(`--set-json 'networkPolicy.destinations=[{"cidr":"<niflheim-/32>","ports":[{"port":22,"protocol":"TCP"}]}]'`
instead of `--set networkPolicy.enabled=false`).

Tune `restoreVerify.requireTables` / `minRows` to the DB's real key tables.

---

## Restore (recovery procedure)

```bash
# 1. Pull + decrypt the chosen run (crypt decrypts on pull).
rclone copy pgdump-crypt:pgdump-preprod/<TS> .

# 2. Roles/grants first (reset passwords after — dumped --no-role-passwords).
psql -f globals-<TS>.sql

# 3. Restore the database (parallel).
pg_restore -j4 -d <target-db> hapihub-<TS>.dump
```

Selective (table-level) restore is `pg_restore -t <table> …` — one of the reasons
this logical tier exists alongside the physical ones.

---

## Verify a nightly run

```bash
kubectl -n mycure-preprod get cronjob,job -l app.kubernetes.io/name=pg-logical-backup
kubectl -n mycure-preprod logs job/<job-name> -c dump      # dump + integrity gate
kubectl -n mycure-preprod logs job/<job-name> -c upload    # upload + retention prune
```

## Operational notes

- **Per-run workspace.** Each run stages into `/work/run-<TS>` and uploads ONLY
  that dir, so a run never re-ships historical dumps. The plaintext dump is
  deleted after a successful crypt upload; on PVC mode any stray `run-*` dir is
  swept too. Plaintext PHI never lingers and never rests off-cluster.
- **Retention failures are visible.** The nightly prune (`rclone delete
  --min-age <retentionDays>d`) is **not** suppressed with `|| true` — a failed
  prune fails the Job so it is alertable (an unbounded remote is a cost + blast
  radius problem).
- **Least privilege.** The dump runs as a dedicated read-only `dumper` role
  (`pg_read_all_data`), provisioned on the primary. No password ever appears on a
  command line: the superuser password is passed via `PGPASSWORD`, the dumper
  password via `psql \getenv`.
- **Password rotation self-heals (finding #1).** The role is bootstrapped at
  deploy time by a sync-wave `-10` Job, but rotation is NOT owned by that Job — a
  completed Job with an unchanged manifest is Synced and is never re-run, so an
  ESO password rotation would leave PG on the old password. Instead, the **nightly
  CronJob carries a `provision-role` initContainer** running the same idempotent
  `ALTER ROLE … PASSWORD` (from the ESO-synced Secret) as the superuser against
  the primary before every dump. So a rotated password re-syncs to PG within
  ≤24h, deterministically, with no dependence on ArgoCD re-running anything.
