# k3d Cluster for Local Testing

resource "k3d_cluster" "main" {
  name    = var.cluster_name
  servers = var.servers
  agents  = var.agents

  image = "rancher/k3s:${var.k3s_version}"

  # Port mappings for LoadBalancer services
  port {
    host_port      = 80
    container_port = 80
    node_filters   = ["loadbalancer"]
  }

  port {
    host_port      = 443
    container_port = 443
    node_filters   = ["loadbalancer"]
  }

  # k3s server arguments
  k3s {
    extra_args {
      arg          = var.disable_traefik ? "--disable=traefik" : ""
      node_filters = ["server:*"]
    }
  }

  # Volume mount for persistent data
  volume {
    source       = "/tmp/k3d-${var.cluster_name}"
    destination  = "/var/lib/rancher/k3s/storage"
    node_filters = ["all"]
  }
}

# Install Gateway API CRDs
resource "null_resource" "install_gateway_api" {
  count = var.install_gateway_api ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG="${k3d_cluster.main.credentials[0].kubeconfig_file}"
      kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
    EOT
  }

  depends_on = [k3d_cluster.main]
}
