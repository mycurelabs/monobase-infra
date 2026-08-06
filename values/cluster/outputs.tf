output "cluster_id" { value = module.doks_cluster.cluster_id }
output "cluster_endpoint" { value = module.doks_cluster.cluster_endpoint }
output "node_pool_ids" { value = module.doks_cluster.node_pool_ids }
output "kubeconfig" {
  value     = module.doks_cluster.kubeconfig
  sensitive = true
}
