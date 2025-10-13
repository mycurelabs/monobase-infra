# Azure AKS Module

Production-ready AKS cluster for multi-tenant LFH Infrastructure.

## Features

- ✅ Multi-tenant ready (3-20 node autoscaling)
- ✅ Workload Identity for External Secrets
- ✅ Azure Disk CSI driver
- ✅ Network Security Groups
- ✅ VNet integration
- ✅ Auto-scaling enabled
- ✅ RBAC enabled

## Usage

```hcl
module "aks_cluster" {
  source = "../../modules/azure-aks"
  
  cluster_name        = "lfh-prod"
  resource_group_name = "lfh-prod-rg"
  location            = "eastus"
  kubernetes_version  = "1.28"
  
  vnet_cidr = "10.0.0.0/16"
  
  node_pools = {
    general = {
      vm_size      = "Standard_D8s_v3"  # 8 vCPU, 32GB
      node_count   = 5
      min_count    = 3
      max_count    = 20
      os_disk_size = 100
    }
  }
  
  enable_workload_identity = true
  enable_azure_disk_csi    = true
}
```

## Outputs

- `cluster_name`, `cluster_endpoint`, `kubeconfig`
- `external_secrets_identity_client_id` - For External Secrets
- `velero_identity_client_id` - For Velero
- `cert_manager_identity_client_id` - For cert-manager

## Get Kubeconfig

```bash
az aks get-credentials --resource-group lfh-prod-rg --name lfh-prod
kubectl get nodes
```

Complete multi-tenant AKS cluster ready for LFH deployments.
