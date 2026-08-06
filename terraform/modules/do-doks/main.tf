# DigitalOcean DOKS Cluster Module

locals {
  default_pool = var.node_pools[var.default_node_pool_key]

  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = digitalocean_kubernetes_cluster.main.name
    clusters = [{
      name = digitalocean_kubernetes_cluster.main.name
      cluster = {
        certificate-authority-data = digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
        server                     = digitalocean_kubernetes_cluster.main.endpoint
      }
    }]
    contexts = [{
      name = digitalocean_kubernetes_cluster.main.name
      context = {
        cluster = digitalocean_kubernetes_cluster.main.name
        user    = digitalocean_kubernetes_cluster.main.name
      }
    }]
    users = [{
      name = digitalocean_kubernetes_cluster.main.name
      user = {
        token = digitalocean_kubernetes_cluster.main.kube_config[0].token
      }
    }]
  })
}

# VPC for cluster isolation
resource "digitalocean_vpc" "main" {
  name     = "${var.cluster_name}-vpc"
  region   = var.region
  ip_range = var.vpc_cidr
}

# DOKS cluster. The pool at var.default_node_pool_key renders inline: the DO
# provider requires exactly one pool inside the cluster resource, it cannot be
# deleted separately, and its `size` is ForceNew ON THE CLUSTER — pick the
# pool least likely to be resized or removed.
resource "digitalocean_kubernetes_cluster" "main" {
  name    = var.cluster_name
  region  = var.region
  version = var.kubernetes_version

  vpc_uuid = digitalocean_vpc.main.id

  # HA control plane (3 masters vs 1)
  ha = var.ha_control_plane

  auto_upgrade  = var.auto_upgrade
  surge_upgrade = var.surge_upgrade

  maintenance_policy {
    day        = var.maintenance_window_day
    start_time = var.maintenance_window_hour
  }

  node_pool {
    name       = var.default_node_pool_key
    size       = local.default_pool.size
    node_count = local.default_pool.auto_scale ? null : local.default_pool.node_count
    auto_scale = local.default_pool.auto_scale
    min_nodes  = local.default_pool.min_nodes
    max_nodes  = local.default_pool.max_nodes
    labels     = local.default_pool.labels
    tags       = local.default_pool.tags

    dynamic "taint" {
      for_each = local.default_pool.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  # Full tag list comes from tfvars verbatim (the provider filters the
  # auto-managed k8s* tags).
  tags = var.tags
}

# All pools other than the inline default. Renaming a map key is an address
# change (destroy+create — every node in the pool drains at once); use
# `tofu state mv` for renames. `size` is ForceNew. node_count is omitted on
# autoscaled pools — the autoscaler owns it.
resource "digitalocean_kubernetes_node_pool" "pool" {
  for_each = { for k, v in var.node_pools : k => v if k != var.default_node_pool_key }

  cluster_id = digitalocean_kubernetes_cluster.main.id
  name       = each.key
  size       = each.value.size
  node_count = each.value.auto_scale ? null : each.value.node_count
  auto_scale = each.value.auto_scale
  min_nodes  = each.value.min_nodes
  max_nodes  = each.value.max_nodes
  labels     = each.value.labels
  tags       = each.value.tags

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
}
