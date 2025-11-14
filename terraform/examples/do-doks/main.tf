# Example DigitalOcean DOKS Cluster Configuration
# REFERENCE - Copy to clusters/your-cluster/ and customize

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
  # Token from environment: DIGITALOCEAN_TOKEN or DIGITALOCEAN_ACCESS_TOKEN
}

module "doks_cluster" {
  source = "../../terraform/modules/do-doks"

  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version

  # Deployment size or custom node configuration
  deployment_profile = var.deployment_profile
  node_size          = var.node_size
  node_count         = var.node_count
  min_nodes          = var.min_nodes
  max_nodes          = var.max_nodes

  # High availability control plane
  ha_control_plane = var.ha_control_plane

  # Auto-upgrade settings
  auto_upgrade  = var.auto_upgrade
  surge_upgrade = var.surge_upgrade

  # Maintenance window
  maintenance_window_day  = var.maintenance_window_day
  maintenance_window_hour = var.maintenance_window_hour

  vpc_cidr = var.vpc_cidr
  tags     = var.tags
}
