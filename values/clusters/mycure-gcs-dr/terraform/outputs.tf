output "backup_bucket_url" { value = "gs://${google_storage_bucket.backup.name}" }
output "transfer_job_name" { value = google_storage_transfer_job.dr.name }
output "sts_service_account" { value = data.google_storage_transfer_project_service_account.sts.email }
output "tf_operator_sa" { value = google_service_account.tf_operator.email }
