# On-prem k3d cluster (mycure-onprem-vanaheim) — OpenTofu root for the vanaheim
# workstation. Disposable/nuke-friendly: LOCAL state, no remote backend.
# Hosts the tailnet-only `mycure-staging` environment (its own in-cluster ArgoCD).
# Entry points: mise run cluster-{init,plan,apply,destroy} mycure-onprem-vanaheim.
# Requires: Docker running.
# ponytail: cluster data lives under /tmp/k3d-<name> (module default) — wiped on
# reboot; fine for a regularly-nuked staging box. Persist via a docker volume in
# the module only if reboot-survival becomes a hard requirement.

module "k3d" {
  source = "../../../../terraform/modules/local-k3d"

  cluster_name        = var.cluster_name
  k3s_version         = var.k3s_version
  servers             = var.servers
  agents              = var.agents
  http_port           = var.http_port
  https_port          = var.https_port
  disable_traefik     = var.disable_traefik
  install_gateway_api = var.install_gateway_api
}
