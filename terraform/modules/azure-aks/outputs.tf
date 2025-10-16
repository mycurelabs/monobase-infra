# Azure AKS Module - Outputs

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
}

output "kubeconfig" {
  description = "kubectl configuration"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${var.cluster_name}"
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "external_secrets_identity_client_id" {
  description = "Client ID for External Secrets Workload Identity"
  value       = var.enable_workload_identity ? azurerm_user_assigned_identity.external_secrets[0].client_id : null
}

output "velero_identity_client_id" {
  description = "Client ID for Velero Workload Identity"
  value       = var.enable_workload_identity ? azurerm_user_assigned_identity.velero[0].client_id : null
}

output "cert_manager_identity_client_id" {
  description = "Client ID for cert-manager Workload Identity"
  value       = var.enable_workload_identity ? azurerm_user_assigned_identity.cert_manager[0].client_id : null
}
