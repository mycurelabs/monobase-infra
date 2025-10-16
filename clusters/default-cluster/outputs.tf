# Default Cluster - Outputs

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks_cluster.cluster_arn
}

output "kubeconfig" {
  description = "kubectl configuration"
  value       = module.eks_cluster.kubeconfig
  sensitive   = true
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.eks_cluster.configure_kubectl
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets"
  value       = module.eks_cluster.external_secrets_role_arn
}

output "velero_role_arn" {
  description = "IAM role ARN for Velero"
  value       = module.eks_cluster.velero_role_arn
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager"
  value       = module.eks_cluster.cert_manager_role_arn
}
