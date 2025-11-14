output "cluster_name" {
  description = "k3d cluster name"
  value       = module.k3d_cluster.cluster_name
}

output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = module.k3d_cluster.kubeconfig_path
}

output "api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.k3d_cluster.api_endpoint
}
