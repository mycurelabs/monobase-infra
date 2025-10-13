# k3d Module - Outputs

output "cluster_name" {
  description = "Name of the k3d cluster"
  value       = k3d_cluster.main.name
}

output "kubeconfig_file" {
  description = "Path to kubeconfig file"
  value       = k3d_cluster.main.credentials[0].kubeconfig_file
}

output "kubeconfig" {
  description = "Kubeconfig content"
  value       = k3d_cluster.main.credentials[0].kubeconfig_raw
  sensitive   = true
}

output "cluster_endpoint" {
  description = "API server endpoint"
  value       = k3d_cluster.main.credentials[0].host
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "export KUBECONFIG=${k3d_cluster.main.credentials[0].kubeconfig_file}"
}
