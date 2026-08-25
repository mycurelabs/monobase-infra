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
    # node-pool=infra label so infra components (ESO/tailscale/gateway) that carry
    # the DOKS node-pool=infra nodeSelector schedule here (k3d has no real pools).
    "--k3s-node-label 'node-pool=infra@server:*'",
    "--k3s-node-label 'node-pool=infra@agent:*'",
    "--volume '/tmp/k3d-${var.cluster_name}:/var/lib/rancher/k3s/storage@all'",
    "--wait --timeout ${var.create_timeout}",
  ]))

  # CoreDNS: suppress AAAA so pods use IPv4. This host/Docker has no IPv6 egress,
  # but public CDNs (e.g. charts.external-secrets.io -> googlehosted) return AAAA,
  # making pod-side `helm pull` / external fetches hang. Without this, ArgoCD's
  # repo-server times out rendering charts pulled from external Helm registries.
  coredns_aaaa = "template IN AAAA {\n  rcode NOERROR\n}"
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

# Gateway API CRDs — the NGINX Gateway Fabric EXPERIMENTAL bundle pinned to the
# NGF version (nginxGateway.version). NGF needs GRPCRoute/UDPRoute/TCPRoute/
# ListenerSet etc.; the plain gateway-api standard bundle omits them and NGF
# crashloops ("no matches for kind GRPCRoute"). Keep gateway_api_ref in lockstep
# with scripts/upgrade-gateway-api-crds.sh.
resource "null_resource" "install_gateway_api" {
  count      = var.install_gateway_api ? 1 : 0
  depends_on = [null_resource.cluster]

  triggers = {
    cluster = null_resource.cluster.id
    ref     = var.gateway_api_ref
  }

  provisioner "local-exec" {
    command = "kubectl --context k3d-${var.cluster_name} apply --server-side --force-conflicts -k 'https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=${var.gateway_api_ref}'"
  }
}

# CoreDNS AAAA suppression (see local.coredns_aaaa). Applied via the k3s
# coredns-custom overlay convention, then CoreDNS is restarted to load it.
resource "null_resource" "coredns_ipv4" {
  depends_on = [null_resource.cluster]

  triggers = {
    cluster = null_resource.cluster.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context k3d-${var.cluster_name} -n kube-system create configmap coredns-custom \
        --from-literal='aaaa.override=${local.coredns_aaaa}' \
        --dry-run=client -o yaml | kubectl --context k3d-${var.cluster_name} apply -f -
      kubectl --context k3d-${var.cluster_name} -n kube-system rollout restart deploy/coredns
    EOT
  }
}
