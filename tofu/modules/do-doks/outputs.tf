# DigitalOcean DOKS Module - Outputs

output "cluster_id" {
  description = "DOKS cluster ID"
  value       = digitalocean_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "DOKS cluster name"
  value       = digitalocean_kubernetes_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for Kubernetes control plane"
  value       = digitalocean_kubernetes_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = digitalocean_kubernetes_cluster.main.version
}

output "cluster_urn" {
  description = "Uniform Resource Name of the cluster"
  value       = digitalocean_kubernetes_cluster.main.urn
}

output "cluster_ipv4_address" {
  description = "Public IPv4 address of the cluster"
  value       = digitalocean_kubernetes_cluster.main.ipv4_address
}

output "cluster_status" {
  description = "Cluster status"
  value       = digitalocean_kubernetes_cluster.main.status
}

output "vpc_id" {
  description = "VPC UUID"
  value       = digitalocean_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = digitalocean_vpc.main.ip_range
}

output "vpc_urn" {
  description = "VPC URN"
  value       = digitalocean_vpc.main.urn
}

output "node_pool_id" {
  description = "Default node pool ID"
  value       = digitalocean_kubernetes_cluster.main.node_pool[0].id
}

output "node_pool_nodes" {
  description = "List of node pool nodes"
  value       = digitalocean_kubernetes_cluster.main.node_pool[0].nodes
}

output "kubeconfig" {
  description = "kubectl config as string"
  value       = local.kubeconfig
  sensitive   = true
}

output "raw_kubeconfig" {
  description = "Raw kubeconfig from DOKS"
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].raw_config
  sensitive   = true
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "doctl kubernetes cluster kubeconfig save ${digitalocean_kubernetes_cluster.main.name}"
}

output "cluster_ca_certificate" {
  description = "Base64 encoded certificate data"
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Base64 encoded client certificate"
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64 encoded client key"
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].client_key
  sensitive   = true
}

output "token" {
  description = "Kubernetes authentication token"
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].token
  sensitive   = true
}
