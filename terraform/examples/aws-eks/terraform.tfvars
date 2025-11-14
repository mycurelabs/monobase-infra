# Example AWS EKS Cluster - Configuration Values
# Copy this file and customize for your cluster

# Basic cluster configuration
cluster_name       = "example-eks"
region             = "us-east-1"
kubernetes_version = "1.28"

# Network configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = [] # Auto-detect (uses 3 AZs in the region)

# API endpoint access
enable_public_endpoint = true
api_access_cidrs       = ["0.0.0.0/0"] # ⚠️ CHANGE IN PRODUCTION: Restrict to your IP ranges

# Deployment size profile
deployment_profile = "small" # small (3 nodes), medium (5 nodes), large (5+ larger nodes)

# Custom node groups (optional - leave empty to use deployment_profile defaults)
node_groups = {}
# Example custom configuration:
# node_groups = {
#   general = {
#     instance_types = ["m6i.xlarge"]  # 4 vCPU, 16GB RAM
#     desired_size   = 3
#     min_size       = 3
#     max_size       = 10
#     disk_size      = 100
#     labels         = {}
#     taints         = []
#   }
# }

# Cluster addons
enable_ebs_csi_driver     = true  # Required for persistent storage
enable_cluster_autoscaler = true  # Auto-scale nodes based on pod demands
enable_irsa               = true  # Required for External Secrets Operator
enable_flow_logs          = true  # VPC flow logs for security/debugging

# IAM policy scoping (recommended for production)
velero_backup_bucket = ""  # Example: "my-cluster-velero-backups"
route53_zone_arns    = []  # Example: ["arn:aws:route53:::hostedzone/Z1234567890ABC"]

# Resource tags
tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Project     = "monobase-infra"
}
