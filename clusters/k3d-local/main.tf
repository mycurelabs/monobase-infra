# k3d Local Development Cluster Configuration
#
# This creates a local k3d cluster for development and testing.
# Provision with: ./scripts/provision.sh --cluster k3d-local

terraform {
  required_version = ">= 1.0"

  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = "~> 0.0.7"
    }
  }
}

module "k3d_cluster" {
  source = "../../terraform/modules/local-k3d"

  cluster_name         = var.cluster_name
  k3s_version          = var.k3s_version
  servers              = var.servers
  agents               = var.agents
  http_port            = var.http_port
  https_port           = var.https_port
  disable_traefik      = var.disable_traefik
  install_gateway_api  = var.install_gateway_api
}
