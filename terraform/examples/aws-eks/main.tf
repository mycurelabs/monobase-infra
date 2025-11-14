# Example AWS EKS Cluster Configuration
# REFERENCE - Copy to clusters/your-cluster/ and customize

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  # Credentials from environment: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  # Or AWS profile: AWS_PROFILE=your-profile
}

module "eks_cluster" {
  source = "../../terraform/modules/aws-eks"

  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version

  # Network configuration
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  # API access
  enable_public_endpoint = var.enable_public_endpoint
  api_access_cidrs       = var.api_access_cidrs

  # Deployment size (small/medium/large or custom)
  deployment_profile = var.deployment_profile
  node_groups        = var.node_groups

  # Addons
  enable_ebs_csi_driver     = var.enable_ebs_csi_driver
  enable_cluster_autoscaler = var.enable_cluster_autoscaler
  enable_irsa               = var.enable_irsa
  enable_flow_logs          = var.enable_flow_logs

  # IAM policy scoping (optional but recommended)
  velero_backup_bucket = var.velero_backup_bucket
  route53_zone_arns    = var.route53_zone_arns

  tags = var.tags
}
