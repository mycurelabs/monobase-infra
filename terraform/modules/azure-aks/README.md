# Azure AKS Module

Production-ready AKS cluster for multi-tenant Monobase Infrastructure deployments.

## Features

- ✅ **Multi-tenant ready** - Sized for multiple clients (3-20 nodes autoscaling)
- ✅ **High availability** - Zone-redundant cluster across availability zones
- ✅ **Workload Identity** - Azure AD workload identity for External Secrets, Velero
- ✅ **Azure Disk CSI** - Managed disk provisioning
- ✅ **Auto-scaling** - Cluster autoscaler for node pools
- ✅ **VNet integration** - Dedicated VNet with subnet isolation
- ✅ **Network Security** - NSG rules and Azure CNI networking
- ✅ **RBAC enabled** - Azure AD integration for Kubernetes RBAC
- ✅ **Encryption** - Disk encryption, secrets encryption at rest
- ✅ **Monitoring** - Azure Monitor integration

## Usage

```hcl
module "aks_cluster" {
  source = "../../modules/azure-aks"
  
  cluster_name        = "monobase-prod"
  resource_group_name = "monobase-prod-rg"
  location            = "eastus"
  kubernetes_version  = "1.28"
  
  # VNet configuration
  vnet_cidr = "10.0.0.0/16"
  
  # Node pools (multi-tenant sizing)
  node_pools = {
    general = {
      vm_size      = "Standard_D8s_v3"  # 8 vCPU, 32GB RAM
      node_count   = 5   # ~5-10 clients
      min_count    = 3   # HA minimum
      max_count    = 20  # ~20-30 clients
      os_disk_size = 100
    }
  }
  
  # Add-ons (required for Monobase)
  enable_workload_identity = true  # External Secrets, Velero
  enable_azure_disk_csi    = true  # Storage
  
  tags = {
    Environment = "production"
    ManagedBy   = "opentofu"
  }
}
```

## Outputs

### Cluster Outputs
- `cluster_name` - AKS cluster name
- `cluster_endpoint` - API server endpoint
- `cluster_arn` - Cluster resource ID
- `kubeconfig` - Complete kubectl configuration

### Workload Identity Outputs (for Monobase components)
- `external_secrets_identity_client_id` - For External Secrets Operator
- `velero_identity_client_id` - For Velero backups

### Network Outputs
- `vnet_id` - Virtual Network ID
- `subnet_id` - AKS subnet ID

## Configuration

### Multi-Tenant Sizing

**Small (5-10 clients):**
```hcl
node_pools = {
  general = {
    vm_size    = "Standard_D4s_v3"   # 4 vCPU, 16GB
    node_count = 3
    min_count  = 3
    max_count  = 10
  }
}
```

**Medium (10-20 clients):**
```hcl
node_pools = {
  general = {
    vm_size    = "Standard_D8s_v3"   # 8 vCPU, 32GB
    node_count = 5
    min_count  = 3
    max_count  = 20
  }
}
```

**Large (20+ clients):**
```hcl
node_pools = {
  general = {
    vm_size    = "Standard_D16s_v3"  # 16 vCPU, 64GB
    node_count = 10
    min_count  = 5
    max_count  = 30
  }
}
```

### Available VM Sizes

Common Azure VM sizes for Monobase deployments:

| VM Size | vCPU | RAM | Disk | Cost/month (East US) |
|---------|------|-----|------|---------------------|
| `Standard_D2s_v3` | 2 | 8GB | 50GB | ~$70 |
| `Standard_D4s_v3` | 4 | 16GB | 100GB | ~$140 |
| `Standard_D8s_v3` | 8 | 32GB | 200GB | ~$280 |
| `Standard_D16s_v3` | 16 | 64GB | 400GB | ~$560 |

Use `az vm list-sizes --location eastus` to see all available sizes.

### Private Cluster

```hcl
enable_private_cluster = true  # Private API endpoint only
```

### Cost Optimization

```hcl
# Use spot instances for non-critical workloads
node_pools = {
  general = {
    vm_size       = "Standard_D8s_v3"
    priority      = "Spot"  # ~60-80% cost savings
    eviction_policy = "Delete"
    spot_max_price = -1  # Pay up to regular price
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

# Or via Azure CLI
az aks get-credentials --resource-group monobase-prod-rg --name monobase-prod

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
    azure.workload.identity/client-id: <external_secrets_identity_client_id>
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

- Azure subscription
- OpenTofu >= 1.6
- Azure CLI configured (`az login`)

## Resources Created

- AKS cluster (control plane)
- Virtual Network with subnet
- Network Security Group
- Managed identities (cluster, nodes, workload identities)
- Azure Disk storage class
- Log Analytics workspace (monitoring)

## Security

- ✅ Disk encryption enabled
- ✅ Secrets encryption at rest
- ✅ Network Security Groups
- ✅ Azure AD integration for RBAC
- ✅ Workload Identity for pod-level permissions
- ✅ Private cluster option
- ✅ Azure Monitor logging

## Cost Estimate

**Medium cluster (5 nodes, Standard_D8s_v3):**
- AKS control plane: Free (included)
- VM nodes: ~$1,400/month (5 × $280)
- Managed disks: ~$50/month
- Load balancer: ~$20/month
- **Total: ~$1,470/month** for ~10-15 clients

**Note:** Azure AKS control plane is free, making it competitive with other cloud providers.

## Troubleshooting

### Check cluster status
```bash
az aks show --resource-group monobase-prod-rg --name monobase-prod
```

### View cluster events
```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Scale node pool manually
```bash
az aks nodepool scale --resource-group monobase-prod-rg --cluster-name monobase-prod --name general --node-count 7
```

### Upgrade Kubernetes version
```bash
# List available upgrades
az aks get-upgrades --resource-group monobase-prod-rg --name monobase-prod

# Upgrade cluster
az aks upgrade --resource-group monobase-prod-rg --name monobase-prod --kubernetes-version 1.29.0
```

## Integration with Monobase

This module creates the Kubernetes cluster. After provisioning:

1. **Configure kubectl** using the `kubeconfig` output
2. **Deploy infrastructure** using Monobase charts:
   - PostgreSQL
   - Longhorn or Azure Disk storage
   - External Secrets (with Azure Key Vault)
   - Gateway API (Envoy Gateway)
3. **Deploy applications** using Monobase charts:
   - Monobase API
   - Monobase Account
   - API Worker

See main repository README for deployment instructions.
