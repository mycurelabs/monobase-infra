# Restoring from the On-Prem Velero Mirror

This is the **tier-4** recovery path — invoked when DO sgp1 is unreachable, the Velero repository in DO Spaces is compromised, or otherwise the primary backups in `mycure-doks-velero-backups` cannot be used.

On-prem hosts hold a 30-day rolling, encrypted Kopia repository mirrored nightly from DO Spaces via `rclone`. The mirror is the same bytes Velero wrote to Spaces — Kopia-encrypted with the repo password held in GCP Secret Manager (`monobase-velero-repo-password`) and on each on-prem host at `/etc/mycure-backup/kopia.password`.

Two restore paths are documented:

- **Path A** (preferred): build a recovery K8s cluster, install Velero, point it at the on-prem mirror.
- **Path B** (fallback): use `kopia` directly to extract raw PVC contents when no K8s cluster is available.

Both are slow (hours, not minutes). Acceptable — this tier exists for events that occur with probability ≪ 1.

---

## Prerequisites

On the host you are restoring from:

- The on-prem mirror is healthy: `ls -lh /var/backups/mycure/spaces/` shows recent content, `rclone size` against the local path is close to the upstream bucket size.
- The Kopia repo password is readable: `sudo cat /etc/mycure-backup/kopia.password` returns the password (64-char base64 string). If it does not, fetch from 1Password or `gcloud secrets versions access latest --secret=monobase-velero-repo-password`.
- The DO Spaces read-only access key from `/etc/rclone/rclone.conf` is valid — needed only if the upstream bucket is still reachable and you want fresh data.

---

## Path A — Recovery K8s cluster

Use this whenever you have hardware (laptop, spare cloud VM) to spin up a fresh cluster. This is the cleanest restore path because Velero handles all the PVC re-hydration.

### 1. Provision a recovery cluster

```sh
cd /path/to/mycure/infra
mise run provision local-k3d
```

The `terraform/modules/local-k3d` module exists specifically for this — a single-binary k3d cluster on the local machine. Other targets (`aws-eks`, `gcp-gke`, etc.) work too; just pick the fastest available.

### 2. Serve the on-prem mirror as an S3-compatible endpoint

Velero needs an S3 API in front of the on-prem files. Easiest option: run a one-shot MinIO container on the same host.

```sh
docker run -d --name minio-restore \
  -p 9000:9000 \
  -v /var/backups/mycure/spaces:/data/mycure-doks-velero-backups:ro \
  -e MINIO_ROOT_USER=restore \
  -e MINIO_ROOT_PASSWORD="$(openssl rand -base64 24)" \
  minio/minio server /data
```

The MinIO instance is ephemeral, read-only, and reachable only from the recovery cluster. Kill the container when restore is complete.

### 3. Install Velero in the recovery cluster

```sh
# Match the production Velero version (currently v1.14.0)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket mycure-doks-velero-backups \
  --secret-file ./minio-credentials \
  --backup-location-config region=local,s3ForcePathStyle=true,s3Url=http://<host-ip>:9000 \
  --use-node-agent
```

Where `minio-credentials` is an INI file with the MinIO root creds from step 2:

```ini
[default]
aws_access_key_id=restore
aws_secret_access_key=<from step 2>
```

Then configure the Kopia repo password so the data-mover can decrypt:

```sh
kubectl -n velero create secret generic velero-repo-credentials \
  --from-literal=repository-password="$(sudo cat /etc/mycure-backup/kopia.password)"
```

### 4. Restore

```sh
# List backups visible from the on-prem mirror
velero backup get

# Restore the latest production-daily
velero restore create restore-$(date +%s) \
  --from-backup production-daily-YYYYMMDDHHMMSS \
  --include-namespaces mycure-production
```

Watch with `velero restore describe <name>` and `kubectl -n mycure-production get pods -w`. Postgres pods come up from restored PVCs and replay WAL on startup (crash-consistent).

### 5. Cleanup

```sh
docker rm -f minio-restore
# Tear down the recovery cluster when no longer needed:
mise run provision local-k3d -- -destroy
```

---

## Path B — `kopia` bare-metal extract

Use this only when Path A is not possible (no hardware for a recovery cluster, or the recovery cluster cannot be provisioned in time). Extracting raw PVC bytes and splicing them into a fresh Postgres is brittle but works — drill-tested 2026-05-14 (3.5M `medical_records` rows recovered, total ~8 min from snapshot ID to verified query; 127/140 user tables exactly matched production at the snapshot moment).

The fast path is `scripts/onprem-backup-restore.sh`. It wraps the entire flow (rclone S3 shim, kopia connect, snapshot lookup, restore, container boot) into four subcommands. The long-form manual procedure below documents what the script does in case you ever need to deviate or debug.

### 1. Fast path — using the script

On the host that holds the mirror (e.g. `hel.niflheim`):

```sh
# What snapshots are available?
sudo scripts/onprem-backup-restore.sh list

# Restore the latest postgres-primary snapshot:
sudo scripts/onprem-backup-restore.sh extract \
  --pvc=data-postgresql-primary-0 \
  --target=/tmp/pg-restore

# Boot postgres:16 against it (writes minimal pg config; chowns to uid 999):
sudo scripts/onprem-backup-restore.sh boot-postgres

# psql in:
sudo docker exec -it pg-restore psql -U postgres -d hapihub

# Tear everything down:
sudo scripts/onprem-backup-restore.sh cleanup
```

Other PVCs follow the same pattern — e.g. `--pvc=datadir-mongodb-0` extracts the mongo PVC, after which you'd boot a `mongo:7` container manually rather than `boot-postgres`.

### 2. Long-form (what the script does)

Notable gotchas not obvious from the upstream docs:
- **`kopia connect filesystem` does NOT work** on Velero's mirrored repos — they're written via the S3 backend (flat blob layout) which kopia's filesystem backend refuses to open ([kopia/kopia#2065](https://github.com/kopia/kopia/issues/2065)). Workaround: serve the local mirror via `rclone serve s3` and connect kopia to localhost via its S3 backend.
- **The data PVC contains only `PG_VERSION` and `pg_ident.conf`**, not the `postgresql.conf` / `pg_hba.conf` that stock Postgres expects in `PGDATA`. Bitnami keeps these in `/opt/bitnami/postgresql/conf/` on the running cluster. We have to write minimal versions before booting Postgres.
- **Use stock `postgres:16` image, not `bitnamilegacy/postgresql`**. Bitnami's entrypoint tries to chown `/opt/bitnami/postgresql/conf` which fails when the container is run with `--user 1001` against a pre-existing data dir.

### 1. Find the snapshot

```sh
ssh hel.niflheim

# Start an ephemeral S3 server pointing at the mirror, with random creds.
export PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
export ACCESS_KEY=$(openssl rand -hex 8)
export SECRET_KEY=$(openssl rand -hex 16)
sudo /usr/local/bin/rclone serve s3 /mnt/storage/mycure-backup/spaces \
  --addr 127.0.0.1:$PORT \
  --auth-key "$ACCESS_KEY,$SECRET_KEY" \
  --vfs-cache-mode off --no-checksum \
  > /tmp/rclone-restore.log 2>&1 &

# Wait for it to bind, then connect kopia.
sleep 2
export HOME=/root KOPIA_CHECK_FOR_UPDATES=false
PASSWORD=$(sudo cat /etc/mycure-backup/kopia.password)
sudo HOME=/root kopia repository disconnect 2>/dev/null || true
sudo HOME=/root kopia repository connect s3 \
  --endpoint="127.0.0.1:$PORT" --disable-tls \
  --bucket=infrastructure --prefix=kopia/mycure-production/ \
  --access-key="$ACCESS_KEY" --secret-access-key="$SECRET_KEY" \
  --password="$PASSWORD"

# Snapshots are owned by velero's synthetic user; --all to see them.
sudo HOME=/root kopia snapshot list --all --max-results=20
```

Find the most-recent line under `default@default:snapshot-data-upload-download/kopia/mycure-production/data-postgresql-primary-0` — its first field is the snapshot ID (e.g. `k2bdf22833ec4fafad2f76faabe47f78b`).

### 2. Restore the PVC contents

```sh
SNAPSHOT=k2bdf22833ec4fafad2f76faabe47f78b   # use the ID from step 1
sudo HOME=/root kopia snapshot restore "$SNAPSHOT" /tmp/pg-restore
```

Expect ~8 min for a 20 GB PVC on HDD-backed mirror (~40 MB/s). The result lives at `/tmp/pg-restore/data/` (the kopia snapshot captures the parent PVC mount, so the Postgres data is one level down).

### 3. Drop in minimal Postgres config

The restored data dir is missing `postgresql.conf` and `pg_hba.conf` — Bitnami stores those outside the PVC. Add minimal versions so stock `postgres:16` can boot.

```sh
DATA=/tmp/pg-restore/data
sudo tee "$DATA/postgresql.conf" > /dev/null <<'EOF'
listen_addresses = '*'
port = 5432
max_connections = 100
shared_buffers = 256MB
dynamic_shared_memory_type = posix
max_wal_size = 1GB
log_timezone = 'UTC'
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'en_US.utf8'
lc_monetary = 'en_US.utf8'
lc_numeric = 'en_US.utf8'
lc_time = 'en_US.utf8'
default_text_search_config = 'pg_catalog.english'
EOF
sudo tee "$DATA/pg_hba.conf" > /dev/null <<'EOF'
# Throwaway restore drill — trust local only.
local all all                trust
host  all all 127.0.0.1/32   trust
host  all all ::1/128        trust
host  all all 0.0.0.0/0      trust
EOF

# Stock postgres:16 runs as uid 999. Match ownership; drop any stale PID.
sudo chown -R 999:999 "$DATA"
sudo rm -f "$DATA/postmaster.pid"
```

### 4. Boot Postgres + run sanity queries

```sh
sudo docker rm -f pg-restore 2>/dev/null || true
sudo docker run -d --name pg-restore \
  -v "$DATA":/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=dummyforinitdb \
  postgres:16

# WAL replay takes a few seconds; wait for ready.
until sudo docker exec pg-restore pg_isready -U postgres 2>/dev/null; do sleep 3; done

# Sanity: database list + a few real row counts.
sudo docker exec pg-restore psql -U postgres -c "
  SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
  FROM pg_database WHERE datistemplate = false
  ORDER BY pg_database_size(datname) DESC;
"
sudo docker exec pg-restore psql -U postgres -d hapihub -c "
  SELECT 'medical_records' AS t, count(*) FROM medical_records UNION ALL
  SELECT 'services',                count(*) FROM services       UNION ALL
  SELECT 'session',                 count(*) FROM session;
"
```

You'll see a `WARNING: database "hapihub" has a collation version mismatch` — that's benign for a drill (cluster libc was 2.36, the postgres:16 image is 2.41). For a real restore-to-production target it'd warrant a `REINDEX` or matching libc.

Logical export for later re-ingest (optional, if you actually need the data elsewhere):

```sh
sudo docker exec pg-restore pg_dump -U postgres -Fc -d hapihub > /tmp/hapihub-recovered.pgc
# On the real target:
pg_restore -d hapihub --no-owner --no-privileges --jobs=4 /tmp/hapihub-recovered.pgc
```

### 5. Cleanup

```sh
sudo docker rm -f pg-restore
sudo rm -rf /tmp/pg-restore /tmp/hapihub-recovered.pgc
sudo HOME=/root kopia repository disconnect
# Kill the transient rclone S3 server we started in step 1:
sudo pkill -f "rclone serve s3" || true
```

---

## Quarterly drill

This restore path is only useful if it works. The mirror itself is no use if nobody knows how to use it.

- **When:** first Monday of each quarter.
- **What:** execute Path A (or Path B, alternating) end-to-end against the latest `production-daily` backup on a throwaway target.
- **Pass criteria:** Postgres comes up healthy, expected row counts within 5% of production for `medical_records`, `billing_invoices`, and `users` tables.
- **Document:** record the run in an internal log with the date, path used, observed duration, and any deviations from this runbook.

If a quarterly drill fails, treat it as a P1 incident — the secondary backup is the entire safety net for cloud-provider failures.

---

## Related

- [BACKUP_DR.md](BACKUP_DR.md) — overall backup strategy
- [ONPREM_BACKUP_SETUP.md](ONPREM_BACKUP_SETUP.md) — how to add a new mirror host
- [`scripts/onprem-backup-restore.sh`](../../scripts/onprem-backup-restore.sh) — Path B restore + drill helper
- [`scripts/onprem-backup-setup.sh`](../../scripts/onprem-backup-setup.sh) — host-side mirror installer
- [infrastructure/velero/](../../infrastructure/velero/) — Velero schedules and BackupStorageLocation config
- [infrastructure/external-secrets/velero-repo-credentials-externalsecret.yaml](../../infrastructure/external-secrets/velero-repo-credentials-externalsecret.yaml) — Kopia password source
