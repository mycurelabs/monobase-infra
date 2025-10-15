# k3d Module - Outputs

output "cluster_name" {
  description = "Name of the k3d cluster"
  value       = k3d_cluster.main.name
}

output "kubeconfig_file" {
  description = "Path to kubeconfig file (k3d writes to default location)"
  value       = pathexpand("~/.kube/config")
}

output "kubeconfig" {
  description = "Kubeconfig content"
  value       = k3d_cluster.main.credentials[0].raw
  sensitive   = true
}

output "cluster_endpoint" {
  description = "API server endpoint"
  value       = k3d_cluster.main.credentials[0].host
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "k3d kubeconfig merge ${k3d_cluster.main.name} --kubeconfig-switch-context"
}
