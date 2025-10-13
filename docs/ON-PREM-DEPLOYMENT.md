# On-Premises Deployment Guide

Complete guide for deploying LFH Infrastructure on-premises using K3s.

## Overview

On-premises deployment using K3s provides:
- ✅ HIPAA compliance (data stays on-prem)
- ✅ Air-gapped capability
- ✅ Full control
- ✅ Simple Kubernetes (K3s vs full kubeadm)
- ✅ Cost-effective (use existing hardware)

## Hardware Requirements

### Minimum (Development/Small Clinic)
- **1 server**
- 4 CPU cores
- 8GB RAM
- 100GB SSD
- Single location

### Recommended (Production/HA)
- **3 servers** (control plane HA)
- 8 CPU cores each
- 16GB RAM each
- 500GB SSD each
- Same network/location

### Large (Hospital/Multi-Clinic)
- **3 servers** (control plane)
- **2+ agents** (workers)
- 16 CPU cores each
- 32GB RAM each
- 1TB SSD each

## Network Requirements

**Between servers:**
- Low latency (<10ms)
- 1 Gbps minimum
- Ports: 6443, 2379-2380, 10250, 8472

**Internet (installation only):**
- Download K3s binary (~60MB)
- Optional: Download container images
- Can be air-gapped after setup

**LoadBalancer IP range:**
- Reserve 10-20 IPs for services (MetalLB)
- Example: 192.168.1.100-192.168.1.110

## Deployment Steps

### 1. Prepare Servers

```bash
# On each server (Ubuntu 22.04):
sudo apt update
sudo apt install -y curl open-iscsi nfs-common

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

### 2. Create Cluster Config

```bash
# Bootstrap config
./scripts/new-cluster-config.sh clinic-prod

# Or copy manually
cp -r tofu/clusters/default-cluster tofu/clusters/clinic-prod
cd tofu/clusters/clinic-prod
```

### 3. Customize for K3s

```bash
# Edit main.tf - use on-prem-k3s module
vim main.tf

# Change:
# source = "../../modules/aws-eks"
# to:
# source = "../../modules/on-prem-k3s"

# Edit terraform.tfvars
vim terraform.tfvars
```

Example terraform.tfvars:
```hcl
cluster_name = "lfh-clinic-prod"

server_ips = [
  "192.168.1.10",  # Server 1
  "192.168.1.11",  # Server 2
  "192.168.1.12"   # Server 3
]

agent_ips = []  # Optional worker nodes

k3s_version = "v1.28.3+k3s1"
k3s_token   = "your-secure-random-token"  # openssl rand -base64 32

ssh_user             = "ubuntu"
ssh_private_key_path = "~/.ssh/id_rsa"

enable_ha        = true   # 3+ servers
install_longhorn = true   # Storage
install_metallb  = true   # LoadBalancer
metallb_ip_range = "192.168.1.100-192.168.1.110"
```

### 4. Provision Cluster

```bash
tofu init
tofu plan
tofu apply

# Wait 5-10 minutes for installation
```

### 5. Get Kubeconfig

```bash
export KUBECONFIG=$(tofu output -raw kubeconfig_path)
kubectl get nodes

# All nodes should be Ready
```

### 6. Deploy LFH Stack

```bash
cd ../../..

# Set storage provider to longhorn (for on-prem)
./scripts/new-client-config.sh clinic-a clinic-a.local

# Edit config
vim config/clinic-a/values-production.yaml
# Set: global.storage.provider: longhorn

# Deploy
helm install hapihub charts/hapihub -f config/clinic-a/values-production.yaml -n clinic-a-prod --create-namespace
```

## High Availability Setup

**3 K3s servers:**
- Embedded etcd (automatic)
- Can lose 1 server
- No external dependencies

**API Endpoint HA (optional):**
- Use keepalived for VIP
- Or DNS round-robin
- Or hardware load balancer

## Storage (Longhorn)

**Automatically installed if `install_longhorn: true`**

Verify:
```bash
kubectl get pods -n longhorn-system
kubectl get storageclass longhorn
```

## LoadBalancer (MetalLB)

**Automatically installed if `install_metallb: true`**

Verify:
```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

Test:
```bash
# Gateway should get LoadBalancer IP
kubectl get svc -n gateway-system
# Should show EXTERNAL-IP from MetalLB range
```

## Air-Gapped Installation

For facilities without internet:

1. Download K3s bundle on connected machine
2. Transfer to servers
3. Install offline:
   ```bash
   INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh
   ```

See: https://docs.k3s.io/installation/airgap

## Maintenance

**Upgrade K3s:**
```bash
# On each server
sudo systemctl stop k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.29.0+k3s1 sh -
sudo systemctl start k3s
```

**Backup:**
- Velero backs up applications
- Longhorn backs up volumes
- Backup etcd: `k3s etcd-snapshot save`

## Troubleshooting

**Nodes not joining:**
```bash
# Check K3s service
sudo systemctl status k3s

# Check logs
sudo journalctl -u k3s -f

# Verify token
cat /var/lib/rancher/k3s/server/token
```

**Storage issues:**
```bash
# Check Longhorn
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager
```

Perfect for healthcare clinics and hospitals!
