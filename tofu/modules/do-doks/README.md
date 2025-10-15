# DigitalOcean Kubernetes (DOKS) Module

Production-ready DOKS cluster for multi-tenant Monobase Infrastructure deployments.

## Features

- ✅ **Multi-tenant ready** - Sized for multiple clients (3-20 nodes autoscaling)
- ✅ **High availability** - Optional HA control plane (3 masters)
- ✅ **VPC isolation** - Dedicated VPC for cluster networking
- ✅ **Auto-scaling** - Node pool autoscaling based on workload
- ✅ **Auto-upgrade** - Automatic Kubernetes version upgrades
- ✅ **Surge upgrades** - Zero-downtime upgrades with extra nodes
- ✅ **Firewall** - Automatic firewall rules for cluster security
- ✅ **Cost-optimized** - ~5x cheaper than AWS EKS for similar workloads
- ✅ **Simple setup** - No complex IAM or networking configuration

## Usage

```hcl
module "doks_cluster" {
  source = "../../modules/do-doks"

  cluster_name       = "monobase-prod"
  region             = "nyc3"
  kubernetes_version = "1.28.2-do.0"

  # Use deployment profile for quick setup
  deployment_profile = "medium"  # small, medium, or large

  # Or customize node pool
  # node_size  = "s-4vcpu-8gb"
  # node_count = 5
  # min_nodes  = 3
  # max_nodes  = 15

  # Optional: HA control plane
  ha_control_plane = false  # Set to true for production

  # Optional: Auto-upgrade settings
  auto_upgrade  = true
  surge_upgrade = true

  # Maintenance window
  maintenance_window_day  = "sunday"
  maintenance_window_hour = "04:00"

  tags = ["production", "monobase-infrastructure"]
}
```

## Available Regions

DigitalOcean data centers:
- `nyc1`, `nyc3` - New York (US East)
- `sfo3` - San Francisco (US West)
- `tor1` - Toronto (Canada)
- `lon1` - London (Europe)
- `fra1` - Frankfurt (Europe)
- `ams3` - Amsterdam (Europe)
- `sgp1` - Singapore (Asia Pacific)
- `blr1` - Bangalore (India)

## Outputs

### Cluster Outputs
- `cluster_name` - DOKS cluster name
- `cluster_endpoint` - API server endpoint
- `cluster_version` - Kubernetes version
- `cluster_status` - Cluster status (running, provisioning, etc.)
- `kubeconfig` - Complete kubectl configuration

### Network Outputs
- `vpc_id` - VPC UUID
- `vpc_cidr` - VPC CIDR block
- `cluster_ipv4_address` - Public IPv4 address of cluster

### Node Pool Outputs
- `node_pool_id` - Default node pool ID
- `node_pool_nodes` - List of nodes in the pool

## Configuration

### Multi-Tenant Sizing

**Small (1-5 clients):**
```hcl
deployment_profile = "small"
# 3 nodes, s-2vcpu-4gb (2 vCPU, 4GB RAM)
# Cost: ~$108/month
```

**Medium (5-15 clients):**
```hcl
deployment_profile = "medium"
# 5 nodes, s-4vcpu-8gb (4 vCPU, 8GB RAM)
# Cost: ~$180/month
```

**Large (15+ clients):**
```hcl
deployment_profile = "large"
# 10 nodes, s-8vcpu-16gb (8 vCPU, 16GB RAM)
# Cost: ~$480/month
```

### Custom Node Pool

```hcl
deployment_profile = "custom"
node_size          = "s-4vcpu-8gb"
node_count         = 7
min_nodes          = 5
max_nodes          = 20
```

### High Availability

```hcl
ha_control_plane = true  # 3 master nodes instead of 1
# Additional cost: ~$40/month
```

### Available Droplet Sizes

Common sizes for Monobase deployments:

| Size | vCPU | RAM | Disk | Cost/month |
|------|------|-----|------|------------|
| `s-2vcpu-2gb` | 2 | 2GB | 60GB | $18 |
| `s-2vcpu-4gb` | 2 | 4GB | 80GB | $36 |
| `s-4vcpu-8gb` | 4 | 8GB | 160GB | $72 |
| `s-8vcpu-16gb` | 8 | 16GB | 320GB | $144 |
| `s-16vcpu-32gb` | 16 | 32GB | 640GB | $288 |

Use `doctl compute size list` to see all available sizes.

## After Provisioning

### Get kubeconfig

```bash
# Via Terraform output
tofu output -raw kubeconfig > ~/.kube/monobase-prod
export KUBECONFIG=~/.kube/monobase-prod

# Or via doctl CLI
doctl kubernetes cluster kubeconfig save monobase-prod

# Verify
kubectl get nodes
```

### Deploy Monobase Application Stack

```bash
# Use existing Monobase workflow
cd ../../..
./scripts/new-client-config.sh client-a client-a.com

# Deploy via ArgoCD or Helm
helm install hapihub charts/hapihub -f config/client-a/values-production.yaml
```

### Install Storage (Optional)

DOKS includes DigitalOcean Block Storage CSI driver by default. To use Longhorn (for on-cluster distributed storage):

```bash
# Install Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.1/deploy/longhorn.yaml

# Set as default storage class
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass do-block-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

## Requirements

- DigitalOcean account with API token
- OpenTofu >= 1.6
- doctl CLI (optional, for easier kubeconfig management)

## Resources Created

- DOKS cluster (control plane)
- VPC (dedicated network)
- Droplet node pool (auto-scaling)
- Firewall rules
- Load balancer (created by Kubernetes Service objects)

## Security

- ✅ VPC isolation (private cluster networking)
- ✅ Firewall rules (automatic cluster security)
- ✅ RBAC enabled (Kubernetes role-based access control)
- ✅ Encrypted secrets (enabled by default)
- ✅ Automatic security updates (via auto_upgrade)

## Cost Estimate

**Medium cluster (5 nodes, s-4vcpu-8gb):**
- Control plane: Free (included with cluster)
- Worker nodes: ~$180/month (5 × $36)
- Load balancer: ~$12/month per LoadBalancer service
- Block storage: ~$0.10/GB/month
- **Total: ~$200/month** for ~10-15 clients

**Compared to AWS EKS medium cluster (~$920/month), DOKS is ~78% cheaper!**

## Kubernetes Versions

List available versions:
```bash
doctl kubernetes options versions
```

Versions follow format: `1.28.2-do.0`

## Troubleshooting

### Check cluster status
```bash
doctl kubernetes cluster get monobase-prod
```

### View cluster events
```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Scale node pool manually
```bash
doctl kubernetes cluster node-pool update monobase-prod <node-pool-id> --count 7
```

### Upgrade Kubernetes version
```bash
# List available upgrades
doctl kubernetes options versions

# Upgrade cluster
doctl kubernetes cluster upgrade monobase-prod --version 1.29.0-do.0
```

## Limitations

- **No IRSA equivalent** - DOKS doesn't have native workload identity. Use Kubernetes secrets or External Secrets Operator with DigitalOcean Spaces.
- **Single region** - Node pools must be in the same region as the cluster.
- **Load balancer costs** - Each LoadBalancer service creates a $12/month DigitalOcean Load Balancer. Consider using Ingress or Gateway API instead.

## Integration with Monobase

This module creates the Kubernetes cluster. After provisioning:

1. **Configure kubectl** using the `kubeconfig` output
2. **Deploy infrastructure** using Monobase charts:
   - MongoDB
   - Longhorn (or use DO Block Storage)
   - External Secrets (with DO API token)
   - Gateway API (Envoy Gateway)
3. **Deploy applications** using Monobase charts:
   - HapiHub
   - MyCureApp
   - Syncd

See main repository README for deployment instructions.
