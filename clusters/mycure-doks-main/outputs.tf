# MyCure DOKS Cluster - Outputs

output "cluster_name" {
  description = "DOKS cluster name"
  value       = module.doks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.doks_cluster.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = module.doks_cluster.cluster_version
}

output "cluster_status" {
  description = "Cluster status"
  value       = module.doks_cluster.cluster_status
}

output "vpc_id" {
  description = "VPC UUID"
  value       = module.doks_cluster.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.doks_cluster.vpc_cidr
}

output "node_pool_id" {
  description = "Default node pool ID"
  value       = module.doks_cluster.node_pool_id
}

output "kubeconfig" {
  description = "Kubeconfig for accessing the cluster"
  value       = module.doks_cluster.kubeconfig
  sensitive   = true
}

# Instructions for accessing the cluster
output "next_steps" {
  description = "Instructions for next steps"
  value = <<-EOT

  ✓ DOKS cluster '${module.doks_cluster.cluster_name}' created successfully!

  Next steps:

  1. Save kubeconfig:
     terraform output -raw kubeconfig > ~/.kube/mycure-doks-main
     export KUBECONFIG=~/.kube/mycure-doks-main

  2. Verify cluster access:
     kubectl get nodes

  3. Deploy infrastructure:
     cd ../../..
     ./scripts/bootstrap.sh --client mycure --env staging

  Cluster details:
  - Name: ${module.doks_cluster.cluster_name}
  - Endpoint: ${module.doks_cluster.cluster_endpoint}
  - Version: ${module.doks_cluster.cluster_version}
  - VPC: ${module.doks_cluster.vpc_id}

  EOT
}


# Production node pool outputs
output "production_node_pool_id" {
  description = "Production node pool ID"
  value       = digitalocean_kubernetes_node_pool.production.id
}

output "production_node_pool_nodes" {
  description = "List of production node pool nodes"
  value       = digitalocean_kubernetes_node_pool.production.nodes
}

output "production_node_pool_status" {
  description = "Production node pool status"
  value = {
    name       = digitalocean_kubernetes_node_pool.production.name
    size       = digitalocean_kubernetes_node_pool.production.size
    node_count = digitalocean_kubernetes_node_pool.production.actual_node_count
    min_nodes  = digitalocean_kubernetes_node_pool.production.min_nodes
    max_nodes  = digitalocean_kubernetes_node_pool.production.max_nodes
  }
}
