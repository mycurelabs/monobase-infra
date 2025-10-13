# On-Prem K3s Cluster Installation

locals {
  first_server = var.server_ips[0]
  additional_servers = slice(var.server_ips, 1, length(var.server_ips))
  ha_mode = var.enable_ha && length(var.server_ips) >= 3
}

# Install K3s on first server (init)
resource "null_resource" "k3s_first_server" {
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = local.first_server
  }

  # Install K3s
  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} sh -s - server ${local.ha_mode ? "--cluster-init" : ""} --token=${var.k3s_token} --disable=traefik --write-kubeconfig-mode=644"
    ]
  }
}

# Install K3s on additional servers (join)
resource "null_resource" "k3s_additional_servers" {
  count = length(local.additional_servers)

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = local.additional_servers[count.index]
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} sh -s - server --server=https://${local.first_server}:6443 --token=${var.k3s_token} --disable=traefik"
    ]
  }

  depends_on = [null_resource.k3s_first_server]
}

# Install K3s on agent nodes
resource "null_resource" "k3s_agents" {
  count = length(var.agent_ips)

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    host        = var.agent_ips[count.index]
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} K3S_URL=https://${local.first_server}:6443 K3S_TOKEN=${var.k3s_token} sh -"
    ]
  }

  depends_on = [null_resource.k3s_first_server]
}

# Get kubeconfig from first server
resource "null_resource" "get_kubeconfig" {
  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ${var.ssh_user}@${local.first_server} 'sudo cat /etc/rancher/k3s/k3s.yaml' | sed 's/127.0.0.1/${local.first_server}/g' > ${path.module}/kubeconfig.yaml"
  }

  depends_on = [null_resource.k3s_first_server]
}

# Install Longhorn (if enabled)
resource "null_resource" "install_longhorn" {
  count = var.install_longhorn ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/kubeconfig.yaml
      kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
    EOT
  }

  depends_on = [null_resource.get_kubeconfig]
}

# Install MetalLB (if enabled)
resource "null_resource" "install_metallb" {
  count = var.install_metallb ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/kubeconfig.yaml
      kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
      sleep 30
      kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - ${var.metallb_ip_range}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
EOF
    EOT
  }

  depends_on = [null_resource.get_kubeconfig]
}
