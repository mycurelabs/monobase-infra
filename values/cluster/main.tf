# Live DOKS cluster (mycure-doks-main) — the OpenTofu root for cluster IaC.
# State: DO Spaces bucket mycure-tfstate (S3 backend). Credentials via env:
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY  = Spaces key pair
#   DIGITALOCEAN_TOKEN                          = DO API token
# (.env.local, auto-loaded by mise. Never committed.)
# Entry points: mise run cluster-init | cluster-plan | cluster-apply.
# Rule: a plan line containing "forces replacement" is an automatic stop.

terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket = "mycure-tfstate"
    key    = "cluster/mycure-doks-main/terraform.tfstate"
    region = "us-east-1" # placeholder; Spaces ignores it
    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
    }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true # Spaces rejects the newer AWS SDK checksum headers
    use_lockfile                = true # S3-native locking; remove if Spaces rejects conditional PUTs
  }

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.86"
    }
  }
}

provider "digitalocean" {} # DIGITALOCEAN_TOKEN from env

module "doks_cluster" {
  source = "../../terraform/modules/do-doks"

  cluster_name          = var.cluster_name
  region                = var.region
  kubernetes_version    = var.kubernetes_version
  vpc_cidr              = var.vpc_cidr
  ha_control_plane      = var.ha_control_plane
  auto_upgrade          = var.auto_upgrade
  surge_upgrade         = var.surge_upgrade
  tags                  = var.tags
  node_pools            = var.node_pools
  default_node_pool_key = var.default_node_pool_key
}
