# Default Cluster Configuration
# Copy to your-cluster/ and customize

cluster_name       = "monobase-default-cluster"
region             = "us-east-1"
kubernetes_version = "1.28"

vpc_cidr = "10.0.0.0/16"

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
]

# Multi-tenant node group (sized for ~10-15 clients)
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"] # 8 vCPU, 32GB RAM
    desired_size   = 5
    max_size       = 20
    min_size       = 3
    disk_size      = 100
    labels         = {}
    taints         = []
  }
}

enable_private_endpoint   = false # Set true for maximum security
enable_public_endpoint    = true
enable_ebs_csi_driver     = true # Required for storage
enable_cluster_autoscaler = true # Required for autoscaling
enable_irsa               = true # Required for External Secrets
enable_flow_logs          = true

tags = {
  Environment = "production"
  ManagedBy   = "opentofu"
  Project     = "monobase-infrastructure"
}
