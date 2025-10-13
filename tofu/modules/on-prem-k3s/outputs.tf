# On-Prem K3s Module - Outputs

output "cluster_name" {
  description = "K3s cluster name"
  value       = var.cluster_name
}

output "server_ips" {
  description = "K3s server node IPs"
  value       = var.server_ips
}

output "agent_ips" {
  description = "K3s agent node IPs"
  value       = var.agent_ips
}

output "api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${var.server_ips[0]}:6443"
}

output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = "${path.module}/kubeconfig.yaml"
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "export KUBECONFIG=${abspath(path.module)}/kubeconfig.yaml"
}

output "metallb_ip_range" {
  description = "MetalLB IP range"
  value       = var.metallb_ip_range
}
