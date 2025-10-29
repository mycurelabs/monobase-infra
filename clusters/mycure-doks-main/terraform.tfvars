# MyCure DOKS Cluster - Configuration Values
# Minimal staging cluster for MyCure

cluster_name       = "mycure-doks-main"
region             = "sgp1"  # Singapore - nearest to Manila/Philippines
kubernetes_version = "1.33.1-do.5"  # Latest stable version

# Node pool configuration (staging - fixed size)
node_size  = "s-2vcpu-4gb"  # 2 vCPU, 4GB RAM
node_count = 3
min_nodes  = 3
max_nodes  = 3  # Fixed size for staging

# High availability (disabled for minimal cost)
ha_control_plane = false  # Single master node

# Auto-upgrade settings
auto_upgrade  = true   # Automatic Kubernetes version upgrades
surge_upgrade = true   # Zero-downtime upgrades

# VPC configuration
vpc_cidr = "10.116.0.0/20"  # Valid DO VPC range (10.116.0.0 - 10.116.15.255)

# Maintenance window (Sunday 4 AM UTC = Sunday 12 PM PHT)
maintenance_window_day  = "sunday"
maintenance_window_hour = "04:00"

# Tags
tags = ["mycure", "staging", "monobase-infrastructure"]

# Production node pool configuration
production_node_size  = "s-4vcpu-8gb"  # 4 vCPU, 8GB RAM
production_node_count = 1              # Start with 1 node
production_min_nodes  = 1              # Minimum for cost efficiency
production_max_nodes  = 3              # Can scale to 3 nodes
