# GCS DR Backup (mc-v4-prod.appspot.com) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the prod patient-file bucket `gs://mc-v4-prod.appspot.com` an automated, isolated, point-in-time-recoverable DR backup (issue [monobase-mycure#3878](https://github.com/mycurelabs/monobase-mycure/issues/3878)).

**Architecture:** Two **additive** DR tiers (both built — not either/or), same defense-in-depth as PG (Spaces → niflheim → vanaheim):
- **Tier 1 — cloud (STS → separate GCP org):** a Storage Transfer Service job in a **separate GCP org/project** mirrors the source bucket into a hardened backup bucket twice daily (00:00 & 12:00 PHT), with **versioning + 30-day noncurrent lifecycle + soft-delete** (rolling 30-day point-in-time). Isolated from a `mc-v4-prod` compromise, $0 egress, fully managed, no exported creds. **Fast RTO, but still on Google.**
- **Tier 2 — on-prem (GCS → niflheim → vanaheim), NEW:** the existing `onprem-backup-setup.sh` pattern gains a `--source=gcs` mode — rclone pulls the bucket from GCS (read-only SA) through an **rclone `crypt`** remote so objects land **encrypted at rest** on `hel.niflheim`, then the generic host→host mirror (#400) fans the ciphertext niflheim→vanaheim for free. **Fully off-Google** (survives total Google loss / billing termination / org-wide compromise). Costs GCS egress on the pull; on-prem storage is ~free. Verified end-to-end on the same niflheim (backup) + vanaheim (dev) boxes #400 was proven on.

**Tech Stack:** OpenTofu (`google` provider), Google Cloud Storage, Storage Transfer Service, DO Spaces S3 backend (tofu state); **rclone (crypt remote) + systemd timers on niflheim/vanaheim** reusing `scripts/onprem-backup-setup.sh` + `scripts/backup-mirror-setup.sh` (#400); `mise` tasks (`cluster-init/plan/apply`).

**Spec:** This plan; requirements captured from issue #3878 + the biz/eng decisions recorded on that issue (STS, separate GCP org, twice-daily, 30-day retention).

## Global Constraints

- **Source bucket:** `gs://mc-v4-prod.appspot.com`, project `mc-v4-prod`, **US multi-region**. Read-only from our side — the plan touches only its IAM policy (adds one grant for the STS agent).
- **Mechanism:** Storage Transfer Service only (destination must be GCS — STS cannot write to S3/Azure/DO; verified against Google docs). STS service fee = **$0** for GCS→GCS.
- **Schedule:** twice daily at **00:00 and 12:00 PHT** = **16:00 and 04:00 UTC** → STS `start_time_of_day = 16:00:00 UTC`, `repeat_interval = 43200s` (12h).
- **Retention:** rolling **30 days** via destination versioning + lifecycle (delete noncurrent after 30d).
- **Isolation:** backup bucket lives in a **separate GCP org + billing account**, no `mc-v4-prod` admin has IAM there.
- **No secrets in git.** STS uses a Google-managed service agent + IAM grants — no exported HMAC keys (that's the whole point vs the AWS/Azure alternatives).
- **Tofu conventions (match existing roots):** root at `values/clusters/mycure-gcs-dr/terraform/`, S3 backend `mycure-tfstate` key `cluster/mycure-gcs-dr/terraform.tfstate`, run via `mise run cluster-init|cluster-plan|cluster-apply mycure-gcs-dr`. A `plan` line containing `forces replacement` is an automatic stop.
- **No reusable module** — one bucket, one job. Keep it a flat root (add a `terraform/modules/gcs-dr-backup` only if a second product ever needs it). `# ponytail: flat root, extract a module when a 2nd bucket needs the same shape`.

---

## File Structure

| File | Responsibility |
|---|---|
| `values/clusters/mycure-gcs-dr/terraform/main.tf` | Backend, two aliased `google` providers (backup + source), the STS agent data source, source-bucket IAM grant, the transfer job. |
| `values/clusters/mycure-gcs-dr/terraform/bucket.tf` | Backup bucket: location, storage class, UBLA, public-access-prevention, versioning, lifecycle (30d noncurrent), soft-delete. |
| `values/clusters/mycure-gcs-dr/terraform/variables.tf` | `backup_project_id`, `source_project_id`, `source_bucket`, `backup_bucket`, `backup_location`, `backup_storage_class`, `schedule_start_date`, `retention_days`. |
| `values/clusters/mycure-gcs-dr/terraform/outputs.tf` | `backup_bucket_url`, `transfer_job_name`, `sts_service_account`. |
| `values/clusters/mycure-gcs-dr/terraform/terraform.tfvars` | Concrete values (project ids, bucket names, region, dates). No secrets. |
| `docs/operations/GCS_DR_BACKUP.md` | Operational runbook: manual run, backup verification, restore drill, cost, incident recovery. |

**Human prerequisites (NOT tofu-managed — need org/billing/IAM-admin rights):**
- **P1.** A **separate GCP org + billing account** exists (or a new project under a separate billing account if standing up a full org is too heavy — note the weaker isolation). Needs Cloud Identity super-admin (org) + billing account creator. → **biz/owner action.**
- **P2.** A **backup project** exists in that org (e.g. `mycure-dr-backup`), billing linked, `storagetransfer.googleapis.com` + `storage.googleapis.com` APIs enabled.
- **P3.** The tofu operator has creds (ADC / `GOOGLE_APPLICATION_CREDENTIALS`) with: `roles/storage.admin` (+ `roles/storagetransfer.admin`) on the **backup project**, AND `roles/storage.admin` on the **source bucket** `mc-v4-prod.appspot.com` (to add the STS agent IAM grant).

---

### Task 1: Scaffold the OpenTofu root + backend + providers

**Files:**
- Create: `values/clusters/mycure-gcs-dr/terraform/main.tf`
- Create: `values/clusters/mycure-gcs-dr/terraform/variables.tf`
- Create: `values/clusters/mycure-gcs-dr/terraform/terraform.tfvars`

**Interfaces:**
- Consumes: DO Spaces S3-backend creds (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` = Spaces key pair, from `.env.local` via mise), Google ADC.
- Produces: initialized root usable by `mise run cluster-init mycure-gcs-dr`; two providers `google.backup` and `google.source`.

- [ ] **Step 1: Write `variables.tf`**

```hcl
variable "backup_project_id"    { type = string }
variable "source_project_id"    { type = string, default = "mc-v4-prod" }
variable "source_bucket"        { type = string, default = "mc-v4-prod.appspot.com" }
variable "backup_bucket"        { type = string } # globally unique, e.g. "mycure-prod-appspot-dr"
variable "backup_location"      { type = string, default = "us-central1" } # regional Nearline (cheapest total)
variable "backup_storage_class" { type = string, default = "NEARLINE" }
variable "retention_days"       { type = number, default = 30 }
variable "schedule_start_date"  { type = object({ year = number, month = number, day = number }) }
```

- [ ] **Step 2: Write `main.tf` (backend + providers + STS agent + source IAM + job)**

```hcl
# GCS DR backup for gs://mc-v4-prod.appspot.com (issue monobase-mycure#3878).
# State: DO Spaces bucket mycure-tfstate (S3 backend), same pattern as the DOKS root.
# Auth: Google ADC / GOOGLE_APPLICATION_CREDENTIALS with storage.admin on the
#   backup project AND on the source bucket; storagetransfer.admin on backup project.
# Entry points: mise run cluster-init | cluster-plan | cluster-apply mycure-gcs-dr.
# Rule: a plan line containing "forces replacement" is an automatic stop.

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket = "mycure-tfstate"
    key    = "cluster/mycure-gcs-dr/terraform.tfstate"
    region = "us-east-1" # placeholder; Spaces ignores it
    endpoints                   = { s3 = "https://sgp1.digitaloceanspaces.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  alias   = "backup"
  project = var.backup_project_id
}

provider "google" {
  alias   = "source"
  project = var.source_project_id
}

# The Google-managed STS agent for the BACKUP project. STS runs the job as this
# identity, so it must be able to read the source bucket and write the sink.
data "google_storage_transfer_project_service_account" "sts" {
  provider = google.backup
  project  = var.backup_project_id
}

# Grant the STS agent read on the SOURCE bucket (cross-org). Bucket-level IAM so
# we touch only this one bucket in mc-v4-prod, nothing else in the project.
resource "google_storage_bucket_iam_member" "source_read" {
  provider = google.source
  bucket   = var.source_bucket
  for_each = toset(["roles/storage.objectViewer", "roles/storage.legacyBucketReader"])
  role     = each.value
  member   = "serviceAccount:${data.google_storage_transfer_project_service_account.sts.email}"
}

# Grant the STS agent write on the SINK (backup) bucket.
resource "google_storage_bucket_iam_member" "sink_write" {
  provider = google.backup
  bucket   = google_storage_bucket.backup.name
  for_each = toset(["roles/storage.legacyBucketWriter", "roles/storage.objectViewer"])
  role     = each.value
  member   = "serviceAccount:${data.google_storage_transfer_project_service_account.sts.email}"
}

resource "google_storage_transfer_job" "dr" {
  provider    = google.backup
  project     = var.backup_project_id
  description = "DR mirror of gs://${var.source_bucket} (twice daily, monobase-mycure#3878)"

  transfer_spec {
    gcs_data_source { bucket_name = var.source_bucket }
    gcs_data_sink   { bucket_name = google_storage_bucket.backup.name }

    transfer_options {
      # Update objects whose content changed; skip identical ones (STS diffs by
      # checksum/size). delete_objects_unique_in_sink = true makes this a MIRROR:
      # a source delete removes the live object in the sink, but versioning keeps
      # it as a noncurrent version for `retention_days` (see bucket.tf). That is
      # the bounded 30-day point-in-time window. Because the sink lives in a
      # separate org, a prod-side mass-delete cannot purge those versions.
      overwrite_objects_already_existing_in_sink = true
      delete_objects_unique_in_sink              = true
    }
  }

  schedule {
    schedule_start_date {
      year  = var.schedule_start_date.year
      month = var.schedule_start_date.month
      day   = var.schedule_start_date.day
    }
    # 00:00 & 12:00 PHT == 16:00 & 04:00 UTC. Start 16:00 UTC, repeat every 12h.
    start_time_of_day {
      hours   = 16
      minutes = 0
      seconds = 0
      nanos   = 0
    }
    repeat_interval = "43200s" # 12h
  }

  depends_on = [
    google_storage_bucket_iam_member.source_read,
    google_storage_bucket_iam_member.sink_write,
  ]
}
```

- [ ] **Step 3: Write `terraform.tfvars` (concrete, non-secret)**

```hcl
backup_project_id   = "mycure-dr-backup"       # from prereq P2
source_project_id   = "mc-v4-prod"
source_bucket       = "mc-v4-prod.appspot.com"
backup_bucket       = "mycure-prod-appspot-dr" # must be globally unique
backup_location     = "us-central1"
backup_storage_class = "NEARLINE"
retention_days      = 30
schedule_start_date = { year = 2026, month = 9, day = 2 }
```

- [ ] **Step 4: Init**

Run: `mise run cluster-init mycure-gcs-dr`
Expected: providers download, backend initializes against `mycure-tfstate`. (Requires `bucket.tf` from Task 2 to `validate`; init alone succeeds.)

- [ ] **Step 5: Commit**

```bash
git add values/clusters/mycure-gcs-dr/terraform/{main.tf,variables.tf,terraform.tfvars}
git commit -m "feat(dr): scaffold GCS DR backup OpenTofu root (monobase-mycure#3878)"
```

---

### Task 2: Define the hardened backup bucket

**Files:**
- Create: `values/clusters/mycure-gcs-dr/terraform/bucket.tf`

**Interfaces:**
- Consumes: `var.backup_*`, `var.retention_days`, `provider google.backup`.
- Produces: `google_storage_bucket.backup` (referenced by `main.tf`'s job + sink IAM).

- [ ] **Step 1: Write `bucket.tf`**

```hcl
resource "google_storage_bucket" "backup" {
  provider = google.backup
  project  = var.backup_project_id
  name     = var.backup_bucket
  location = var.backup_location

  storage_class               = var.backup_storage_class
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Rolling point-in-time window: every overwrite/delete keeps the prior bytes
  # as a noncurrent version; lifecycle purges them after retention_days.
  versioning { enabled = true }

  lifecycle_rule {
    condition { days_since_noncurrent_time = var.retention_days }
    action    { type = "Delete" }
  }

  # Extra safety net for anything deleted without a version (default is 7d).
  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }

  # This is a backup of the last resort — never auto-destroy on tofu.
  lifecycle {
    prevent_destroy = true
  }
}
```

- [ ] **Step 2: Write `outputs.tf`**

```hcl
output "backup_bucket_url"    { value = "gs://${google_storage_bucket.backup.name}" }
output "transfer_job_name"    { value = google_storage_transfer_job.dr.name }
output "sts_service_account"  { value = data.google_storage_transfer_project_service_account.sts.email }
```

- [ ] **Step 3: Validate**

Run: `cd values/clusters/mycure-gcs-dr/terraform && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add values/clusters/mycure-gcs-dr/terraform/{bucket.tf,outputs.tf}
git commit -m "feat(dr): hardened backup bucket + versioning/lifecycle/soft-delete"
```

---

### Task 3: Plan + review (the gate — NO apply yet)

**Files:** none (review step).

- [ ] **Step 1: Plan**

Run: `mise run cluster-plan mycure-gcs-dr`
Expected: create `google_storage_bucket.backup`, 4 `google_storage_bucket_iam_member` (2 source + 2 sink), 1 `google_storage_transfer_job`. Exit code 2 (changes pending).

- [ ] **Step 2: Review checklist (STOP on any failure)**
  - [ ] No line contains `forces replacement`.
  - [ ] The source IAM grants land on `mc-v4-prod.appspot.com` and **only** that bucket.
  - [ ] Bucket has `versioning=true`, lifecycle `days_since_noncurrent_time=30`, `public_access_prevention=enforced`, `prevent_destroy=true`.
  - [ ] Job schedule is `16:00 UTC` / `43200s`.

- [ ] **Step 3: Biz/owner sign-off recorded on issue #3878** before apply (this plan is delivered for that decision).

---

### Task 4: Apply + first-run verification

**Files:** none (operational).

- [ ] **Step 1: Apply**

Run: `mise run cluster-apply mycure-gcs-dr`
Expected: state backed up to `backups/terraform-state/` first, then resources created.

- [ ] **Step 2: Trigger an on-demand run (don't wait for the schedule)**

Run: `gcloud transfer jobs run "$(cd values/clusters/mycure-gcs-dr/terraform && tofu output -raw transfer_job_name)" --project=<backup_project_id>`
Expected: an operation starts.

- [ ] **Step 3: Verify the run succeeded and data landed**

```bash
gcloud transfer operations list --job-names=<job> --project=<backup> --format='value(metadata.status,counters.objectsCopiedToSink,counters.bytesCopiedToSink)'
gcloud storage du -s gs://<backup_bucket>
```
Expected: status `SUCCESS`; sink byte/object counts ≈ source (`gcloud storage du -s gs://mc-v4-prod.appspot.com`).

- [ ] **Step 4: Commit the lockfile**

```bash
git add values/clusters/mycure-gcs-dr/terraform/.terraform.lock.hcl
git commit -m "chore(dr): pin google provider lockfile for GCS DR root"
```

---

### Task 5: Runbook (backup verification + restore drill)

**Files:**
- Create: `docs/operations/GCS_DR_BACKUP.md`

- [ ] **Step 1: Write the runbook** with these sections (fill the `<...>` at implementation time):

```markdown
# GCS DR Backup — Runbook (gs://mc-v4-prod.appspot.com)

**What:** STS mirrors the prod uploads bucket into `gs://<backup_bucket>` in the
separate DR project `<backup_project_id>` twice daily (00:00 & 12:00 PHT).
30-day point-in-time window via versioning + lifecycle. Managed by OpenTofu at
`values/clusters/mycure-gcs-dr/terraform` (issue monobase-mycure#3878).

## Health check (weekly)
    gcloud transfer operations list --job-names=<job> --project=<backup> \
      --format='table(metadata.startTime,metadata.status,counters.objectsCopiedToSink)'
Last op should be SUCCESS within the last 12h. If ERROR: inspect
`gcloud transfer operations describe <op>`; common cause = IAM grant on source
bucket removed by ArgoCD/self-heal or a prod IAM cleanup — re-run
`mise run cluster-apply mycure-gcs-dr`.

## Restore a single object (latest)
    gcloud storage cp gs://<backup_bucket>/<path> gs://mc-v4-prod.appspot.com/<path> --project=<backup>

## Restore a deleted / previous version (within 30 days)
    gcloud storage ls -a gs://<backup_bucket>/<path>          # list generations
    gcloud storage cp gs://<backup_bucket>/<path>#<generation> gs://mc-v4-prod.appspot.com/<path>

## Full-bucket restore (DR)
    gcloud storage rsync -r gs://<backup_bucket> gs://mc-v4-prod.appspot.com
(Or stand up a new bucket and repoint hapihub `STORAGE_BUCKET` if the source
bucket/project is lost.)

## Restore drill (run quarterly — proves the backup, per PG-drill precedent)
1. Pick a known object; copy it from the backup to a scratch path.
2. Checksum-compare against source: `gcloud storage hash`.
3. Delete a throwaway test object on source, wait for next sync, confirm it
   becomes a noncurrent version in the backup and is restorable.
4. Record the drill result on the DR tracking issue.

## Cost (measure real size first: `gcloud storage du -s gs://mc-v4-prod.appspot.com`)
- STS service fee: $0.
- Storage: <SIZE_GB> × $0.010/GB/mo (us-central1 Nearline) ≈ $<...>/mo, plus up
  to 30 days of churned noncurrent versions.
- Egress: source is US multi-region, sink is us-central1 → inter-region egress
  (~$0.02/GB) on the INITIAL full copy once, then only on changed bytes per run.
  To make egress $0, switch `backup_location` to `US` multi-region (storage then
  ~$0.015/GB Nearline-MR instead of $0.010 regional — pick per size).
```

- [ ] **Step 2: Commit**

```bash
git add docs/operations/GCS_DR_BACKUP.md
git commit -m "docs(dr): GCS DR backup runbook + restore drill (monobase-mycure#3878)"
```

---

> **Tasks 1–5 = Tier 1 (cloud/STS). Tasks 6–7 = Tier 2 (on-prem), additive — both ship.**

### Task 6: On-prem tier — `--source=gcs` mode for `onprem-backup-setup.sh`

**Files:**
- Modify: `scripts/onprem-backup-setup.sh` (add a `--source=gcs` branch alongside the existing Spaces/Kopia source)

**Interfaces:**
- Consumes: read-only GCS SA (prereq P5 below), an rclone `crypt` password (held like `KOPIA_PASSWORD`, supplied out-of-band).
- Produces: an encrypted-at-rest mirror at `<backup-dir>/gcs/mc-v4-prod.appspot.com` on niflheim + a systemd pull timer — a backup dir shaped exactly like the Kopia mirror so **#400 stacks it unchanged**.

**Prereq P5 (human):** create a read-only exporter SA in `mc-v4-prod` with `roles/storage.objectViewer` on `mc-v4-prod.appspot.com`; put its JSON in `/etc/rclone/` on niflheim (same place as the read-only Spaces key). Generate the rclone crypt password offline; escrow it (reuse the [[secrets-dr-3882]] escrow policy — it's the GCS-mirror analogue of the Kopia password).

- [ ] **Step 1:** Add rclone remotes to `/etc/rclone/rclone.conf` on niflheim (documented by the script):

```ini
[gcs-src]
type = google cloud storage
service_account_file = /etc/rclone/mc-v4-prod-readonly-sa.json
project_number = <mc-v4-prod number>

[gcs-crypt]
type = crypt
remote = /mnt/storage/mycure/gcs/mc-v4-prod.appspot.com
password = <obscured crypt password>   # rclone obscure; real pw escrowed offline
```

- [ ] **Step 2:** In `onprem-backup-setup.sh`, add the `--source=gcs` pull command (encrypt-on-ingest so plaintext PHI never rests on the host — the invariant that keeps the host→host stack ciphertext-only):

```bash
# --source=gcs : rclone pull GCS -> crypt (encrypted at rest). Unlike the Kopia
# source (blobs arrive pre-encrypted), raw GCS objects are plaintext patient
# files, so we write THROUGH the crypt remote. --backup-dir keeps a dated copy of
# overwritten/deleted objects = point-in-time on-prem without versioned storage.
"$RCLONE_BIN" --config "$RCLONE_CONFIG" sync gcs-src:mc-v4-prod.appspot.com gcs-crypt: \
  --backup-dir "gcs-crypt-archive:$(date -u +%Y-%m-%d)" \
  --transfers "$RCLONE_TRANSFERS" --checkers "$RCLONE_CHECKERS" --fast-list
```

- [ ] **Step 3:** Install a pull timer (offset from the STS run for freshness; reuse the script's timer scaffolding): e.g. `--timer-on-calendar='04:30,16:30 Asia/Manila'`. Weekly `rclone check gcs-src:… gcs-crypt:…` verify (the script already wires a check step).

- [ ] **Step 4: shellcheck + commit**

Run: `shellcheck scripts/onprem-backup-setup.sh`
```bash
git add scripts/onprem-backup-setup.sh
git commit -m "feat(onprem-backup): --source=gcs encrypted mirror of the uploads bucket (monobase-mycure#3878)"
```

---

### Task 7: Stack host→host (#400) + verify/restore drill on niflheim + vanaheim

**Files:**
- Modify: `docs/operations/GCS_DR_BACKUP.md` (add the on-prem tier + the drill)

This tier is **host-side only** (both boxes are off-cluster) — no GitOps changes, same as #400. It must be **testable on the same niflheim (backup) + vanaheim (dev) setup** #400 was proven on.

- [ ] **Step 1: Fan-out is free** — the encrypted `gcs/` mirror dir is just more blobs under the backup root, so the existing `backup-mirror-setup.sh` (#400) replica on vanaheim already pulls it. Confirm it lands: `ls /mnt/hdd/backup-mirror/niflheim/.../gcs/` on vanaheim.

- [ ] **Step 2: Verify encrypted-at-rest** — on niflheim, confirm files under `/mnt/storage/mycure/gcs/...` are **ciphertext** (not viewable), and that decryption needs the crypt password:
```bash
file /mnt/storage/mycure/gcs/<obscured-name>      # not a recognizable image/pdf
rclone --config /etc/rclone/rclone.conf ls gcs-crypt: | head   # readable only WITH the crypt remote
```

- [ ] **Step 3: Restore drill (on the dev box, vanaheim)** — the whole point of "local = testable":
```bash
# On vanaheim, using ONLY the replica's blobs + the crypt password (supplied at
# restore, like Kopia): decrypt one object and checksum it against the source.
rclone --config <cfg-with-crypt> copy gcs-crypt:<path> /tmp/restore/
gcloud storage hash gs://mc-v4-prod.appspot.com/<path>   # compare md5/crc32c
```
Expected: checksum matches source. Record the drill result on #3878 (mirrors #400's live-host verification + the PG restore-drill precedent [[pg-backup-restore-drill]]).

- [ ] **Step 4: Document + commit** the on-prem tier section in `GCS_DR_BACKUP.md` (mechanism, crypt-password escrow, the drill above, capacity note).
```bash
git add docs/operations/GCS_DR_BACKUP.md
git commit -m "docs(dr): on-prem GCS tier + niflheim/vanaheim restore drill"
```

---

## Self-Review

**Spec coverage — Tier 1 (cloud):** twice-daily schedule → Task 1. 30-day retention → Task 2. Separate-org isolation → prereqs P1/P2 + separate provider. STS mechanism → Task 1 job. Runbook → Task 5. Verification/restore → Tasks 4–5. **Tier 2 (on-prem):** GCS→niflheim encrypted mirror → Task 6 (`--source=gcs` + rclone crypt); host→host fan-out + local restore drill on niflheim/vanaheim → Task 7. ✅

**Open items for biz/owner decision (issue #3878):**
1. Approve standing up a **separate GCP org + billing account** (P1) — the isolation Tier 1 depends on. Lighter fallback = new project under a separate billing account (weaker: shares org-level admins).
2. `backup_location`: `us-central1` regional Nearline (cheapest storage, small delta egress) **vs** `US` multi-region Nearline ($0 egress, ~1.5× storage). Decide against measured bucket size.
3. Confirm "6hrs interval" in the issue really means twice-daily (00:00/12:00) — plan uses 12h; switch `repeat_interval` to `21600s` for true 6h if they want tighter RPO.
4. **On-prem tier egress + capacity** — the GCS→niflheim pull pays **$0.12/GB Google egress** on the initial full copy (deltas after), and the mirror must fit `hel.niflheim` `/mnt/storage` (1.8T; PG data-mover already ~188G) **plus** headroom on vanaheim. Both gated on the **measured bucket size** (`gcloud storage du -s` — scan still pending). If the bucket is very large, consider a prefix/age filter for the on-prem tier while keeping Tier 1 whole.
5. **Crypt-password escrow** for the on-prem mirror — reuse the [[secrets-dr-3882]] age/Shamir escrow policy (this password is the GCS-mirror analogue of the Kopia password).

**Placeholder scan:** `<backup_project_id>`, `<backup_bucket>`, `<job>`, `<SIZE_GB>`, `<mc-v4-prod number>`, `<obscured crypt password>`, `<path>` are operational fill-ins (real ids / measured size / escrowed secret), not logic gaps. No TODO logic.

**Type consistency:** `google_storage_bucket.backup.name` referenced consistently in `main.tf` (sink IAM + job) and `outputs.tf`; `data.google_storage_transfer_project_service_account.sts.email` referenced in both IAM grants. ✅
