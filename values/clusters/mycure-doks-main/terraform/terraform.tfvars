# Mirrors the live cluster exactly — `tofu plan` must be empty (the gate).

cluster_name       = "mycure-doks-main"
region             = "sgp1"
kubernetes_version = "1.33.12-do.2"
vpc_cidr           = "10.116.0.0/20"
ha_control_plane   = false
auto_upgrade       = true
surge_upgrade      = true
tags               = ["monobase-infrastructure", "mycure", "mycure-doks-main", "staging"]

# infra holds the immutable inline seat: least likely to be resized or
# deleted (prod-db resizes with DB growth; nonprod is the most deletable).
default_node_pool_key = "infra"

node_pools = {
  infra = {
    size       = "s-2vcpu-8gb-amd"
    node_count = 2
    labels     = { "node-pool" = "infra" }
    taints     = [{ key = "node-pool", value = "infra", effect = "NoSchedule" }]
  }
  prod-db = {
    size       = "g-4vcpu-16gb"
    node_count = 1
    labels     = { "node-pool" = "prod-db" }
    taints     = [{ key = "node-pool", value = "prod-db", effect = "NoSchedule" }]
  }
  prod-apps = {
    size       = "s-4vcpu-16gb-amd"
    auto_scale = true
    min_nodes  = 2
    max_nodes  = 3
    labels     = { "node-pool" = "prod-apps" }
    taints     = [{ key = "node-pool", value = "prod-apps", effect = "NoSchedule" }]
  }
  nonprod = {
    size       = "s-4vcpu-8gb"
    auto_scale = true
    min_nodes  = 2
    max_nodes  = 4
    labels     = { "node-pool" = "nonprod" }
  }
}
