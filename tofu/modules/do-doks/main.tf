# DigitalOcean DOKS Cluster Module - Main Configuration

locals {
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

# DOKS Cluster
resource "digitalocean_kubernetes_cluster" "main" {
  name    = var.cluster_name
  region  = var.region
  version = var.kubernetes_version

  vpc_uuid = digitalocean_vpc.main.id

  # HA control plane (3 masters vs 1)
  ha = var.ha_control_plane

  # Auto-upgrade settings
  auto_upgrade = var.auto_upgrade
  surge_upgrade = var.surge_upgrade

  # Maintenance window
  maintenance_policy {
    day       = var.maintenance_window_day
    start_time = var.maintenance_window_hour
  }

  # Default node pool
  node_pool {
    name       = "general"
    size       = local.effective_node_pool.node_size
    node_count = local.effective_node_pool.node_count

    # Autoscaling
    auto_scale = true
    min_nodes  = local.effective_node_pool.min_nodes
    max_nodes  = local.effective_node_pool.max_nodes

    tags = concat(
      ["monobase-infrastructure", var.cluster_name],
      var.tags
    )

    labels = {
      "workload-type" = "general"
      "managed-by"    = "opentofu"
    }
  }

  tags = concat(
    ["monobase-infrastructure", var.cluster_name],
    var.tags
  )
}

# Firewall for cluster
resource "digitalocean_firewall" "cluster" {
  name = "${var.cluster_name}-firewall"

  tags = [digitalocean_kubernetes_cluster.main.id]

  # Allow all outbound
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow inbound from VPC
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_cidr]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_cidr]
  }

  # Allow Kubernetes API access (controlled by DOKS)
  # Note: DOKS manages API server access, no need to expose port 6443
}
