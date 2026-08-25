output "cluster_name" {
  value = module.k3d.cluster_name
}

output "cluster_endpoint" {
  value = module.k3d.cluster_endpoint
}

output "kubeconfig" {
  value     = module.k3d.kubeconfig
  sensitive = true
}

output "configure_kubectl" {
  value = module.k3d.configure_kubectl
}
