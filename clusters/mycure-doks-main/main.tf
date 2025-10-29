# MyCure DOKS Cluster - Main Configuration
# Minimal staging cluster for MyCure in Singapore region

terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  # Token is read from DIGITALOCEAN_TOKEN or DIGITALOCEAN_ACCESS_TOKEN env var
}

module "doks_cluster" {
  source = "../../terraform/modules/do-doks"

  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version

  # Custom node pool (no autoscaling)
  deployment_profile = "custom"
  node_size          = var.node_size
  node_count         = var.node_count
  min_nodes          = var.min_nodes
  max_nodes          = var.max_nodes

  # No HA control plane (minimal cost)
  ha_control_plane = var.ha_control_plane

  # Auto-upgrade settings
  auto_upgrade  = var.auto_upgrade
  surge_upgrade = var.surge_upgrade

  # Maintenance window (Sunday 4 AM UTC = Sunday 12 PM PHT)
  maintenance_window_day  = var.maintenance_window_day
  maintenance_window_hour = var.maintenance_window_hour

  vpc_cidr = var.vpc_cidr

  tags = var.tags
}


# Staging node pool (separate resource for flexibility)
resource "digitalocean_kubernetes_node_pool" "staging" {
  cluster_id = module.doks_cluster.cluster_id

  name       = "staging"
  size       = var.staging_node_size
  node_count = var.staging_node_count

  # Autoscaling
  auto_scale = true
  min_nodes  = var.staging_min_nodes
  max_nodes  = var.staging_max_nodes

  tags = concat(
    [var.cluster_name, "staging", "monobase-infrastructure"],
    var.tags
  )

  labels = {
    "workload-type" = "staging"
    "node-pool"     = "staging"
    "managed-by"    = "opentofu"
  }

  # Taint to ensure only staging workloads schedule here
  taint {
    key    = "node-pool"
    value  = "staging"
    effect = "NoSchedule"
  }
}

# Production node pool (separate resource for flexibility)
resource "digitalocean_kubernetes_node_pool" "production" {
  cluster_id = module.doks_cluster.cluster_id

  name       = "production"
  size       = var.production_node_size
  node_count = var.production_node_count

  # Autoscaling
  auto_scale = true
  min_nodes  = var.production_min_nodes
  max_nodes  = var.production_max_nodes

  tags = concat(
    [var.cluster_name, "production", "monobase-infrastructure"],
    var.tags
  )

  labels = {
    "workload-type" = "production"
    "node-pool"     = "production"
    "managed-by"    = "opentofu"
  }

  # Taint to ensure only production workloads schedule here
  taint {
    key    = "node-pool"
    value  = "production"
    effect = "NoSchedule"
  }
}
