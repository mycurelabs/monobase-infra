# k3d Module - Outputs

output "cluster_name" {
  description = "Name of the k3d cluster"
  value       = var.cluster_name
  depends_on  = [null_resource.cluster]
}

output "context" {
  description = "kubectl context for the cluster (k3d merges it into ~/.kube/config)"
  value       = local.context
}

output "kubeconfig_file" {
  description = "Path to kubeconfig file (k3d writes to the default location)"
  value       = pathexpand("~/.kube/config")
}

output "configure_kubectl" {
  description = "Command to switch kubectl to this cluster"
  value       = "kubectl config use-context ${local.context}"
}
