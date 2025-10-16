# GCP GKE Module - Outputs

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.main.name
}

output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.main.id
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "external_secrets_sa_email" {
  description = "Service account email for External Secrets"
  value       = var.enable_workload_identity ? google_service_account.external_secrets[0].email : null
}

output "velero_sa_email" {
  description = "Service account email for Velero"
  value       = var.enable_workload_identity ? google_service_account.velero[0].email : null
}

output "cert_manager_sa_email" {
  description = "Service account email for cert-manager"
  value       = var.enable_workload_identity ? google_service_account.cert_manager[0].email : null
}
