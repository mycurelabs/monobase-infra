# k3d Local Development Cluster - Outputs

output "cluster_name" {
  description = "Name of the k3d cluster"
  value       = module.k3d_cluster.cluster_name
}

output "kubeconfig" {
  description = "Kubeconfig content"
  value       = module.k3d_cluster.kubeconfig
  sensitive   = true
}

output "cluster_endpoint" {
  description = "API server endpoint"
  value       = module.k3d_cluster.cluster_endpoint
}

output "access_urls" {
  description = "URLs to access services"
  value = {
    http  = "http://localhost:${var.http_port}"
    https = "https://localhost:${var.https_port}"
  }
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.k3d_cluster.configure_kubectl
}

output "next_steps" {
  description = "Next steps after provisioning"
  value = <<-EOT
    1. Configure kubectl:
       ${module.k3d_cluster.configure_kubectl}

    2. Verify cluster:
       kubectl get nodes

    3. (Optional) Configure /etc/hosts for local domains:
       echo "127.0.0.1 api.local.test app.local.test sync.local.test" | sudo tee -a /etc/hosts

    4. Bootstrap applications:
       ./scripts/bootstrap.sh --client monobase --env dev
  EOT
}
