# Persistent least-privilege Terraform operator SA (pattern b). Created on the
# bootstrap apply; thereafter tofu runs by IMPERSONATING it (keyless), and the
# human bootstrap operator's direct roles are removed. See Task 4.8 in the plan.
resource "google_service_account" "tf_operator" {
  provider     = google.backup
  project      = var.backup_project_id
  account_id   = "gcs-dr-tf-operator"
  display_name = "GCS DR Terraform operator (least-priv)"
}

resource "google_project_iam_member" "tf_operator_backup" {
  provider = google.backup
  project  = var.backup_project_id
  for_each = toset([
    "roles/storage.admin",
    "roles/storagetransfer.admin",
    "roles/pubsub.admin",
  ])
  role   = each.value
  member = "serviceAccount:${google_service_account.tf_operator.email}"
}

# Bucket-scoped on the SOURCE so tofu can reconcile the STS-agent binding on
# future applies. The operator SA's only reach into mc-v4-prod.
resource "google_storage_bucket_iam_member" "tf_operator_source" {
  provider = google.source
  bucket   = var.source_bucket
  role     = "roles/storage.admin"
  member   = "serviceAccount:${google_service_account.tf_operator.email}"
}

# Humans who may RUN tofu / restores: keyless impersonation only — their entire
# standing footprint. No direct storage/transfer/pubsub roles anywhere.
resource "google_service_account_iam_member" "tf_operator_impersonators" {
  provider           = google.backup
  for_each           = toset(var.tf_operators)
  service_account_id = google_service_account.tf_operator.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}
