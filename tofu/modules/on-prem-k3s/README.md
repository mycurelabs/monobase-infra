# On-Premises K3s Module

Provisions K3s cluster on bare metal servers for healthcare on-prem deployments.

## Features

- ✅ **Healthcare-ready** - On-premises for compliance
- ✅ **Simple** - K3s easier than kubeadm
- ✅ **HA mode** - 3+ servers with embedded etcd
- ✅ **Lightweight** - <512MB RAM, 1 CPU per server
- ✅ **Automatic setup** - SSH-based provisioning
- ✅ **LoadBalancer** - MetalLB for service exposure
- ✅ **Storage** - Longhorn distributed storage
- ✅ **Air-gapped ready** - Offline installation support

## Requirements

**Hardware:**
- 3+ servers for HA (or 1 for dev)
- 4 CPU cores per server (minimum)
- 8GB RAM per server (minimum)
- 100GB disk per server
- Network connectivity between servers

**Access:**
- SSH access to all servers
- sudo privileges
- Ubuntu 20.04/22.04 or RHEL 8/9

## Usage

```hcl
module "k3s_cluster" {
  source = "../../modules/on-prem-k3s"
  
  cluster_name = "lfh-clinic-prod"
  
  # Server IPs (control plane)
  server_ips = [
    "192.168.1.10",
    "192.168.1.11",
    "192.168.1.12"
  ]
  
  # Optional worker nodes
  agent_ips = [
    "192.168.1.20",
    "192.168.1.21"
  ]
  
  # K3s configuration
  k3s_version = "v1.28.3+k3s1"
  k3s_token   = "your-secure-token-here"  # Generate: openssl rand -base64 32
  
  # SSH access
  ssh_user             = "ubuntu"
  ssh_private_key_path = "~/.ssh/id_rsa"
  
  # Components
  enable_ha        = true   # HA with embedded etcd
  install_longhorn = true   # Distributed storage
  install_metallb  = true   # LoadBalancer
  metallb_ip_range = "192.168.1.100-192.168.1.110"
}
```

## Outputs

- `cluster_name` - Cluster name
- `api_endpoint` - API server endpoint
- `kubeconfig_path` - Path to kubeconfig
- `server_ips` - Control plane IPs
- `metallb_ip_range` - LoadBalancer IP range

## After Provisioning

```bash
# Get kubeconfig
export KUBECONFIG=$(tofu output -raw kubeconfig_path)
kubectl get nodes

# Deploy LFH stack
cd ../../..
./scripts/new-client-config.sh clinic-a clinic-a.local
# Deploy apps
```

## HA Configuration

**3 servers (recommended):**
- Embedded etcd (no external dependency)
- Can lose 1 server
- VIP recommended for API endpoint

**5+ servers (large deployments):**
- Better availability
- Can lose 2 servers
- More capacity

## Network Requirements

**Between servers:**
- Port 6443: Kubernetes API
- Port 2379-2380: etcd (if HA)
- Port 10250: Kubelet metrics
- Port 8472: Flannel VXLAN (or 51820/51821 for WireGuard)

**Internet (for installation):**
- get.k3s.io (K3s installer)
- github.com (Longhorn, MetalLB manifests)
- Or use air-gapped installation

## Air-Gapped Installation

See: [Air-Gapped Guide](https://docs.k3s.io/installation/airgap) for offline bundles.

## Troubleshooting

**Nodes not joining:**
- Check K3s token matches
- Verify network connectivity (port 6443)
- Check firewall rules

**Storage issues:**
- Ensure disks available for Longhorn
- Check disk permissions

**LoadBalancer pending:**
- Verify MetalLB IP range available
- Check no IP conflicts
