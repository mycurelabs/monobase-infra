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
    # storage.admin: tofu manages the backup bucket itself (create/update,
    # lifecycle, versioning) + its IAM (STS sink grants) — bucket admin is the job.
    "roles/storage.admin",
    # storagetransfer.admin: tofu manages the STS job + reads the service agent.
    "roles/storagetransfer.admin",
    # pubsub.admin: tofu manages the alert topic + its IAM (publisher grant);
    # publisher/subscriber alone can't create topics or set topic IAM.
    "roles/pubsub.admin",
  ])
  role   = each.value
  member = "serviceAccount:${google_service_account.tf_operator.email}"
}

# Bucket-scoped on the SOURCE so tofu can reconcile the STS-agent binding on
# future applies. The operator SA's only reach into mc-v4-prod, and the only
# thing tofu does there is manage that one IAM binding — so the role is a
# custom role carrying ONLY storage.buckets.{get,set}IamPolicy. No predefined
# role is this narrow (legacyBucketOwner still carries storage.objects.delete);
# storage.admin here would let one identity destroy both source and DR copy.
# The custom role is created once by a mc-v4-prod admin (see plan Task 4.8b);
# tofu references it but does not manage it.
# NOTE: setIamPolicy is inherently self-escalation-capable (the SA could
# re-grant itself broader roles) — irreducible while tofu manages this binding.
resource "google_storage_bucket_iam_member" "tf_operator_source" {
  provider = google.source
  bucket   = var.source_bucket
  role     = "projects/${var.source_project_id}/roles/gcsDrBucketIamManager"
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
