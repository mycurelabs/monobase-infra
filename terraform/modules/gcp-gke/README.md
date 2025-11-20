# GCP GKE Module

Production-ready GKE cluster for multi-tenant Monobase Infrastructure deployments.

## Features

- ✅ **Multi-tenant ready** - Sized for multiple clients (3-20 nodes autoscaling)
- ✅ **Regional HA cluster** - Multi-zone cluster for high availability
- ✅ **Workload Identity** - GCP workload identity for External Secrets, Velero
- ✅ **GCP Persistent Disk CSI** - Managed disk provisioning
- ✅ **Auto-scaling** - Cluster autoscaler for node pools
- ✅ **VPC-native networking** - Alias IP ranges for pods and services
- ✅ **Network policy** - Calico network policy enforcement
- ✅ **Auto-repair** - Automatic node repair
- ✅ **Auto-upgrade** - Automatic Kubernetes version upgrades
- ✅ **Encryption** - Disk encryption, secrets encryption at rest
- ✅ **Monitoring** - Cloud Monitoring and Cloud Logging integration

## Usage

```hcl
module "gke_cluster" {
  source = "../../modules/gcp-gke"
  
  cluster_name       = "monobase-prod"
  project_id         = "my-project-123456"
  region             = "us-central1"
  kubernetes_version = "1.28"
  
  # VPC configuration
  network_cidr = "10.0.0.0/16"
  
  # Node pools (multi-tenant sizing)
  node_pools = {
    general = {
      machine_type = "n2-standard-8"  # 8 vCPU, 32GB RAM
      node_count   = 5   # ~5-10 clients
      min_count    = 3   # HA minimum
      max_count    = 20  # ~20-30 clients
      disk_size_gb = 100
    }
  }
  
  # Add-ons (required for Monobase)
  enable_workload_identity = true  # External Secrets, Velero
  
  tags = {
    Environment = "production"
    ManagedBy   = "opentofu"
  }
}
```

## Outputs

### Cluster Outputs
- `cluster_name` - GKE cluster name
- `cluster_endpoint` - API server endpoint
- `cluster_ca_certificate` - Cluster CA certificate
- `kubeconfig` - Complete kubectl configuration

### Workload Identity Outputs (for Monobase components)
- `external_secrets_sa_email` - Service account for External Secrets Operator
- `velero_sa_email` - Service account for Velero backups

### Network Outputs
- `network_name` - VPC network name
- `subnet_name` - GKE subnet name

## Configuration

### Multi-Tenant Sizing

**Small (5-10 clients):**
```hcl
node_pools = {
  general = {
    machine_type = "n2-standard-4"   # 4 vCPU, 16GB
    node_count   = 3
    min_count    = 3
    max_count    = 10
  }
}
```

**Medium (10-20 clients):**
```hcl
node_pools = {
  general = {
    machine_type = "n2-standard-8"   # 8 vCPU, 32GB
    node_count   = 5
    min_count    = 3
    max_count    = 20
  }
}
```

**Large (20+ clients):**
```hcl
node_pools = {
  general = {
    machine_type = "n2-standard-16"  # 16 vCPU, 64GB
    node_count   = 10
    min_count    = 5
    max_count    = 30
  }
}
```

### Available Machine Types

Common GCP machine types for Monobase deployments:

| Machine Type | vCPU | RAM | Cost/month (us-central1) |
|--------------|------|-----|-------------------------|
| `n2-standard-2` | 2 | 8GB | ~$50 |
| `n2-standard-4` | 4 | 16GB | ~$100 |
| `n2-standard-8` | 8 | 32GB | ~$200 |
| `n2-standard-16` | 16 | 64GB | ~$400 |

Use `gcloud compute machine-types list --zones=us-central1-a` to see all types.

### Private Cluster

```hcl
enable_private_nodes    = true  # Nodes have private IPs only
enable_private_endpoint = true  # Private API endpoint (requires VPN/bastion)
```

### Cost Optimization

```hcl
# Use preemptible nodes for non-critical workloads
node_pools = {
  general = {
    machine_type = "n2-standard-8"
    preemptible  = true  # ~60-80% cost savings
    # ...
  }
}

# Or use Spot VMs (newer, more flexible)
node_pools = {
  general = {
    machine_type = "n2-standard-8"
    spot         = true  # Similar savings to preemptible
    # ...
  }
}
```

## After Provisioning

### Get kubeconfig

```bash
# Via Terraform output
tofu output -raw kubeconfig > ~/.kube/monobase-prod
export KUBECONFIG=~/.kube/monobase-prod

# Or via gcloud CLI
gcloud container clusters get-credentials monobase-prod --region us-central1 --project my-project

# Verify
kubectl get nodes
```

### Configure kubectl for Workload Identity

Service accounts will automatically use workload identity when annotated:

```yaml
# External Secrets Operator
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: external-secrets-system
  annotations:
    iam.gke.io/gcp-service-account: <external_secrets_sa_email>
```

### Deploy Monobase Application Stack

```bash
# Use existing Monobase workflow
cd ../../..
./scripts/new-client-config.sh client-a client-a.com

# Deploy via ArgoCD or Helm
helm install api charts/api -f config/client-a/values-production.yaml
```

## Requirements

- GCP project with billing enabled
- OpenTofu >= 1.6
- gcloud CLI configured (`gcloud auth login`)

## Resources Created

- GKE cluster (control plane)
- VPC network and subnet
- Firewall rules
- Service accounts (cluster, nodes, workload identities)
- GCP Persistent Disk storage class
- Cloud Logging and Monitoring

## Security

- ✅ Disk encryption enabled
- ✅ Secrets encryption at rest
- ✅ Network policy enforcement (Calico)
- ✅ Workload Identity for pod-level permissions
- ✅ Private nodes option
- ✅ Shielded GKE nodes
- ✅ Binary authorization ready
- ✅ Cloud Logging and Monitoring

## Cost Estimate

**Medium cluster (5 nodes, n2-standard-8):**
- GKE control plane: ~$73/month (regional cluster)
- VM nodes: ~$1,000/month (5 × $200)
- Persistent disks: ~$50/month
- Load balancer: ~$20/month
- **Total: ~$1,143/month** for ~10-15 clients

**Note:** Regional GKE clusters charge for control plane; zonal clusters have free control plane.

## Troubleshooting

### Check cluster status
```bash
gcloud container clusters describe monobase-prod --region us-central1 --project my-project
```

### View cluster events
```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Scale node pool manually
```bash
gcloud container clusters resize monobase-prod --region us-central1 --node-pool general --num-nodes 7
```

### Upgrade Kubernetes version
```bash
# List available upgrades
gcloud container get-server-config --region us-central1

# Upgrade cluster (control plane first, then nodes)
gcloud container clusters upgrade monobase-prod --region us-central1 --cluster-version 1.29.0
```

## Integration with Monobase

This module creates the Kubernetes cluster. After provisioning:

1. **Configure kubectl** using the `kubeconfig` output
2. **Deploy infrastructure** using Monobase charts:
   - PostgreSQL
   - Longhorn or GCP Persistent Disk storage
   - External Secrets (with GCP Secret Manager)
   - Gateway API (Envoy Gateway)
3. **Deploy applications** using Monobase charts:
   - Monobase API
   - Monobase Account
   - API Worker

See main repository README for deployment instructions.
