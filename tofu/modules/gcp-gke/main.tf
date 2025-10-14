# GCP GKE Cluster Module

resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  min_master_version = var.kubernetes_version

  # Use VPC-native networking
  network    = google_compute_network.main.self_link
  subnetwork = google_compute_subnetwork.nodes.self_link

  # Remove default node pool (we create custom pools)
  remove_default_node_pool = true
  initial_node_count       = 1

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Network policy
  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED"
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  resource_labels = var.tags
}

# Node pools
resource "google_container_node_pool" "main" {
  for_each = var.node_pools

  name     = each.key
  location = var.region
  cluster  = google_container_cluster.main.name
  project  = var.project_id

  initial_node_count = each.value.node_count

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = var.tags
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
