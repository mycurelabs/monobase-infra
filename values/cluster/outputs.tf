# DOKS Cluster - Outputs
# Consumed by ArgoCD / Helm charts that need cluster-level information
# (e.g., kubeconfig generation, gateway IPs, VPC routing).

output "cluster_name" {
  description = "DOKS cluster name"
  value       = module.doks_cluster.cluster_name
}

output "cluster_id" {
  description = "DOKS cluster ID"
  value       = module.doks_cluster.cluster_id
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.doks_cluster.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = module.doks_cluster.cluster_version
}

output "cluster_ipv4_address" {
  description = "Public IPv4 address of the cluster"
  value       = module.doks_cluster.cluster_ipv4_address
}

output "vpc_id" {
  description = "VPC UUID"
  value       = module.doks_cluster.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.doks_cluster.vpc_cidr
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "doctl kubernetes cluster kubeconfig save ${module.doks_cluster.cluster_name}"
}
