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

Use this only when Path A is not possible (no hardware for a recovery cluster, or the recovery cluster cannot be provisioned in time). Extracting raw PVC bytes and splicing them into a fresh Postgres is brittle but works.

### 1. Connect to the on-prem Kopia repo

```sh
sudo kopia repository connect filesystem \
  --path=/var/backups/mycure/spaces/kopia \
  --password="$(sudo cat /etc/mycure-backup/kopia.password)"
```

The exact path under `/var/backups/mycure/spaces/` depends on the Velero data-mover prefix — inspect with `find /var/backups/mycure/spaces -type d -name 'kopia' -maxdepth 4` if uncertain.

### 2. List snapshots

```sh
sudo kopia snapshot list
```

Each Velero data-mover upload appears as a Kopia snapshot. Note the snapshot ID for the PVC you want (typically `data-postgresql-primary-0`).

### 3. Restore raw files

```sh
sudo kopia restore <snapshot-id> /tmp/pvc-extract/
```

The contents of `/tmp/pvc-extract/` are the raw Postgres data directory as it was on the source PVC at backup time.

### 4. Bring up a Postgres around it

```sh
# Match the production Postgres major version (currently 16)
docker run -d --name pg-restore \
  -v /tmp/pvc-extract:/var/lib/postgresql/data:Z \
  -e POSTGRES_PASSWORD=temporary \
  postgres:16

docker exec -it pg-restore psql -U postgres -d hapihub -c '\dt'
```

Postgres replays WAL on startup (it's a crash-consistent snapshot). Once up, dump out logically and re-ingest into the eventual target:

```sh
docker exec pg-restore pg_dump -U postgres -Fc -d hapihub > hapihub-recovered.pgc
# Then on the real target Postgres:
pg_restore -d hapihub --no-owner --no-privileges --jobs=4 hapihub-recovered.pgc
```

### 5. Cleanup

```sh
docker rm -f pg-restore
sudo rm -rf /tmp/pvc-extract
sudo kopia repository disconnect
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
- [infrastructure/velero/](../../infrastructure/velero/) — Velero schedules and BackupStorageLocation config
- [infrastructure/external-secrets/velero-repo-credentials-externalsecret.yaml](../../infrastructure/external-secrets/velero-repo-credentials-externalsecret.yaml) — Kopia password source
