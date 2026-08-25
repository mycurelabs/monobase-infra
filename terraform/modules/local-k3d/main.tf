# k3d cluster for local / on-prem testing.
#
# Provisioned via the k3d CLI (local-exec), NOT the pvotal-tech/k3d provider.
# That provider's readiness detection aborts before k3s finishes booting — it
# stops tailing the container log at ~20s and fails with "stopped returning log
# lines ... is running=true", even though the cluster comes up fine. The CLI
# with `--wait --timeout` is reliable and is what k3d is actually tested with.

locals {
  context = "k3d-${var.cluster_name}"

  create_cmd = join(" ", compact([
    "k3d cluster create ${var.cluster_name}",
    "--servers ${var.servers}",
    "--agents ${var.agents}",
    "--image rancher/k3s:${var.k3s_version}",
    "-p '${var.http_port}:80@loadbalancer'",
    "-p '${var.https_port}:443@loadbalancer'",
    var.disable_traefik ? "--k3s-arg '--disable=traefik@server:*'" : "",
    "--volume '/tmp/k3d-${var.cluster_name}:/var/lib/rancher/k3s/storage@all'",
    "--wait --timeout ${var.create_timeout}",
  ]))
}

resource "null_resource" "cluster" {
  # Any change to these recreates the cluster (destroy-then-create).
  triggers = {
    cluster_name = var.cluster_name
    k3s_version  = var.k3s_version
    servers      = var.servers
    agents       = var.agents
    http_port    = var.http_port
    https_port   = var.https_port
    traefik      = tostring(var.disable_traefik)
  }

  # Create. Delete-if-exists first so a partial/failed prior run doesn't wedge
  # the nuke-and-reprovision loop. k3d updates ~/.kube/config and switches to
  # the k3d-<name> context by default.
  provisioner "local-exec" {
    command = "k3d cluster delete ${var.cluster_name} >/dev/null 2>&1 || true; ${local.create_cmd}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.triggers.cluster_name}"
  }
}

# Gateway API CRDs (NGINX Gateway Fabric needs them). Applied against the
# freshly-created context.
resource "null_resource" "install_gateway_api" {
  count      = var.install_gateway_api ? 1 : 0
  depends_on = [null_resource.cluster]

  triggers = {
    cluster = null_resource.cluster.id
  }

  provisioner "local-exec" {
    command = "kubectl --context k3d-${var.cluster_name} apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml"
  }
}
