# Default Cluster Configuration
# REFERENCE - Copy to clusters/your-cluster/ and customize

module "eks_cluster" {
  source = "../../modules/aws-eks"
  
  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version
  
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  
  enable_private_endpoint = var.enable_private_endpoint
  enable_public_endpoint  = var.enable_public_endpoint
  
  node_groups = var.node_groups
  
  enable_ebs_csi_driver     = var.enable_ebs_csi_driver
  enable_cluster_autoscaler = var.enable_cluster_autoscaler
  enable_irsa               = var.enable_irsa
  enable_flow_logs          = var.enable_flow_logs
  
  tags = var.tags
}
