resource "google_storage_bucket" "backup" {
  provider = google.backup
  project  = var.backup_project_id
  name     = var.backup_bucket
  location = var.backup_location

  storage_class               = var.backup_storage_class
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Rolling point-in-time window: overwrite/delete keeps the prior bytes as a
  # noncurrent version; lifecycle purges them after retention_days.
  versioning { enabled = true }

  lifecycle_rule {
    condition { days_since_noncurrent_time = var.retention_days }
    action { type = "Delete" }
  }

  # Extra safety net for anything deleted without a version (default is 7d).
  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }

  # Backup of last resort — never auto-destroy on tofu.
  lifecycle {
    prevent_destroy = true
  }
}
