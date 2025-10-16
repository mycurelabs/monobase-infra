# GCP Networking for GKE

resource "google_compute_network" "main" {
  name                    = "${var.cluster_name}-network"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "nodes" {
  name          = "${var.cluster_name}-nodes"
  ip_cidr_range = cidrsubnet(var.network_cidr, 4, 0)
  region        = var.region
  network       = google_compute_network.main.self_link
  project       = var.project_id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(var.network_cidr, 2, 1)
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(var.network_cidr, 4, 1)
  }
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.main.self_link
  project = var.project_id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.network_cidr]
}
