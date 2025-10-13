# GCP Service Accounts for Workload Identity

# Service Account for External Secrets
resource "google_service_account" "external_secrets" {
  count = var.enable_workload_identity ? 1 : 0

  account_id   = "${var.cluster_name}-external-secrets"
  display_name = "External Secrets Operator"
  project      = var.project_id
}

resource "google_service_account_iam_member" "external_secrets_workload_identity" {
  count = var.enable_workload_identity ? 1 : 0

  service_account_id = google_service_account.external_secrets[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets-system/external-secrets]"
}

resource "google_project_iam_member" "external_secrets_secret_accessor" {
  count = var.enable_workload_identity ? 1 : 0

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets[0].email}"
}

# Service Account for Velero
resource "google_service_account" "velero" {
  count = var.enable_workload_identity ? 1 : 0

  account_id   = "${var.cluster_name}-velero"
  display_name = "Velero Backup"
  project      = var.project_id
}

resource "google_service_account_iam_member" "velero_workload_identity" {
  count = var.enable_workload_identity ? 1 : 0

  service_account_id = google_service_account.velero[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[velero/velero]"
}

# Service Account for cert-manager
resource "google_service_account" "cert_manager" {
  count = var.enable_workload_identity ? 1 : 0

  account_id   = "${var.cluster_name}-cert-manager"
  display_name = "cert-manager DNS-01"
  project      = var.project_id
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  count = var.enable_workload_identity ? 1 : 0

  service_account_id = google_service_account.cert_manager[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
}

resource "google_project_iam_member" "cert_manager_dns" {
  count = var.enable_workload_identity ? 1 : 0

  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager[0].email}"
}
