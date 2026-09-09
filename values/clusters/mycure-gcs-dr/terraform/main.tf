# GCS DR backup for gs://mc-v4-prod.appspot.com — Tier 1 (STS → separate GCP account).
# Issue monobase-mycure#3878. State: DO Spaces (S3 backend), same pattern as the DOKS root.
# Auth: GOOGLE_OAUTH_ACCESS_TOKEN (or ADC) for an identity with storage.admin +
#   storagetransfer.admin + pubsub.admin on the backup project AND storage.admin on
#   the source bucket. Entry points: mise run cluster-init|cluster-plan|cluster-apply mycure-gcs-dr.
# Rule: a plan line containing "forces replacement" is an automatic stop.

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket                      = "mycure-tfstate"
    key                         = "cluster/mycure-gcs-dr/terraform.tfstate"
    region                      = "us-east-1" # placeholder; Spaces ignores it
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

# user_project_override + billing_project route API quota to the backup project
# (where the APIs are enabled + the operator has serviceusage.services.use), so
# user-credential/token auth doesn't fall back to Google's default quota project.
provider "google" {
  alias                 = "backup"
  project               = var.backup_project_id
  user_project_override = true
  billing_project       = var.backup_project_id
}

provider "google" {
  alias                 = "source"
  project               = var.source_project_id
  user_project_override = true
  billing_project       = var.backup_project_id
}

# The Google-managed STS agent for the BACKUP project. STS runs the job as this
# identity, so it must read the source bucket, write the sink, and publish alerts.
data "google_storage_transfer_project_service_account" "sts" {
  provider = google.backup
  project  = var.backup_project_id
}

# Grant the STS agent read on the SOURCE bucket (cross-account). Bucket-level IAM
# so we touch only this one bucket in mc-v4-prod.
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

# ---- Failure alerting (Task 4.5): STS -> Pub/Sub on failed operations ----
resource "google_pubsub_topic" "sts_alerts" {
  provider = google.backup
  project  = var.backup_project_id
  name     = "gcs-dr-sts-alerts"
}

# STS agent must be able to publish notifications to the topic.
resource "google_pubsub_topic_iam_member" "sts_publisher" {
  provider = google.backup
  project  = var.backup_project_id
  topic    = google_pubsub_topic.sts_alerts.name
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${data.google_storage_transfer_project_service_account.sts.email}"
}

resource "google_storage_transfer_job" "dr" {
  provider    = google.backup
  project     = var.backup_project_id
  description = "DR mirror of gs://${var.source_bucket} (twice daily, monobase-mycure#3878)"

  transfer_spec {
    gcs_data_source { bucket_name = var.source_bucket }
    gcs_data_sink { bucket_name = google_storage_bucket.backup.name }

    transfer_options {
      # Rely on STS DEFAULT overwrite (only DIFFERENT objects rewritten). Do NOT set
      # overwrite_objects_already_existing_in_sink=true — it re-copies all ~302 GB
      # every run (~$540/mo). delete_objects_unique_in_sink=true makes this a MIRROR;
      # sink versioning + 30-day lifecycle keep the point-in-time window.
      delete_objects_unique_in_sink = true
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

  notification_config {
    pubsub_topic   = google_pubsub_topic.sts_alerts.id
    event_types    = ["TRANSFER_OPERATION_FAILED"]
    payload_format = "JSON"
  }

  depends_on = [
    google_storage_bucket_iam_member.source_read,
    google_storage_bucket_iam_member.sink_write,
    google_pubsub_topic_iam_member.sts_publisher,
  ]
}
