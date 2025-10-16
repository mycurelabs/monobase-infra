# Example Azure AKS Cluster

Reference configuration for Azure Kubernetes Service.

## Quick Start

```bash
# 1. Copy this directory
cp -r clusters/example-azure-aks clusters/myclient-aks

# 2. Customize
cd clusters/myclient-aks
vim terraform.tfvars

# 3. Provision
./scripts/provision.sh --cluster myclient-aks
```

## Module Documentation

See [terraform/modules/azure-aks/README.md](../../terraform/modules/azure-aks/README.md) for:
- Full configuration options
- Azure-specific setup
- RBAC and networking
- Cost optimization

## Prerequisites

- Azure account
- Azure CLI (`az login`)
- Terraform >= 1.6
