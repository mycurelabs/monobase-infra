# Public k3d cluster (mycure-k3d-demo) — OpenTofu root for the demo VPS.
# LOCAL state, no remote backend (same as vanaheim). Hosts the internet-facing
# `mycure-demo` environment (sales / client demos / training) with its own
# in-cluster ArgoCD tracking `cluster/demo`.
# Entry points: mise run cluster-{init,plan,apply,destroy} mycure-k3d-demo.
# Requires: Docker running, host ports 80/443 TCP + 6472/7842 UDP free.
#
# Unlike vanaheim, this cluster is LONG-LIVED: PV data lives under
# storage_path (a persistent host dir, not /tmp), so Postgres/MinIO survive a
# reboot. Docker creates the dir on first create.

module "k3d" {
  source = "../../../../terraform/modules/local-k3d"

  cluster_name        = var.cluster_name
  k3s_version         = var.k3s_version
  servers             = var.servers
  agents              = var.agents
  http_port           = var.http_port
  https_port          = var.https_port
  storage_path        = var.storage_path
  extra_port_mappings = var.extra_port_mappings
  api_port            = var.api_port
  disable_traefik     = var.disable_traefik
  install_gateway_api = var.install_gateway_api
}
