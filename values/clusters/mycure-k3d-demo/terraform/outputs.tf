output "cluster_name" {
  value = module.k3d.cluster_name
}

output "context" {
  value = module.k3d.context
}

output "configure_kubectl" {
  value = module.k3d.configure_kubectl
}
