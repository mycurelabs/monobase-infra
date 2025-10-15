# Infrastructure Provisioning (OpenTofu + Terragrunt)

Provision Kubernetes clusters for Monobase Infrastructure deployments.

## Overview

This directory provides **cluster provisioning** using OpenTofu (open-source Terraform) and Terragrunt.

**Scope:** Creates Kubernetes clusters (EKS, AKS, GKE, DOKS, K3s, k3d)
**Complements:** Application deployment in `../charts/` and `../config/`

## Quick Start

```bash
# 1. Copy reference cluster config
cp -r tofu/clusters/default-cluster tofu/clusters/myclient-cluster

# 2. Customize
cd tofu/clusters/myclient-cluster
vim terraform.tfvars  # Edit cluster name, region, node sizes

# 3. Provision cluster
tofu init
tofu plan
tofu apply

# 4. Get kubeconfig
tofu output -raw kubeconfig > ~/.kube/myclient-cluster
export KUBECONFIG=~/.kube/myclient-cluster
kubectl get nodes

# 5. Deploy applications (use existing Monobase workflow)
cd ../../..
./scripts/new-client-config.sh client-a client-a.com
# Deploy via Helm/ArgoCD
```

## Modules

Choose based on deployment target:

| Module | Use When | Cluster Type |
|--------|----------|--------------|
| **aws-eks** | Deploying to AWS | Managed EKS |
| **azure-aks** | Deploying to Azure | Managed AKS |
| **gcp-gke** | Deploying to GCP | Managed GKE |
| **do-doks** | Deploying to DigitalOcean | Managed DOKS |
| **on-prem-k3s** | On-premises, clinics, hospitals | K3s on bare metal |
| **local-k3d** | Local testing, CI/CD | k3d (K3s in Docker) |

## Multi-Tenant Architecture

**One cluster hosts multiple clients:**

```
Single Cluster (provisioned via tofu/)
├── client-a-prod namespace    ← Deploy via monobase-infra charts
├── client-b-prod namespace    ← Deploy via monobase-infra charts
├── client-c-staging namespace ← Deploy via monobase-infra charts
└── gateway-system (shared)
```

**Cluster sizing:** Autoscales from 3-20 nodes based on client load

## Reference Configuration

**`clusters/default-cluster/`** - Complete reference (like `config/example.com/`)

Contains:
- main.tf - Module usage
- variables.tf - All parameters
- terraform.tfvars - Example values
- terragrunt.hcl - Terragrunt config
- README.md - Customization guide

## Implementation Status

**✅ 100% COMPLETE - All 6 Modules Implemented**

- ✅ **AWS EKS** - Production multi-tenant EKS with IRSA, autoscaling
- ✅ **Azure AKS** - Production AKS with Workload Identity
- ✅ **GCP GKE** - Production GKE with Workload Identity
- ✅ **DigitalOcean DOKS** - Cost-optimized managed Kubernetes (~78% cheaper than EKS)
- ✅ **on-prem-k3s** - Healthcare on-prem with K3s, HA, MetalLB
- ✅ **local-k3d** - Local testing and CI/CD automation
- ✅ **default-cluster** - Complete reference configuration
- ✅ **Terragrunt** - DRY configuration management
- ✅ **Bootstrap script** - new-cluster-config.sh

**Complete multi-cloud support: AWS, Azure, GCP, DigitalOcean, on-prem, local testing!**

## Why OpenTofu (not Terraform)

✅ Open source (Terraform went BSL license)
✅ Linux Foundation project
✅ Drop-in Terraform replacement
✅ No vendor lock-in
✅ Community-driven

## Tools Required

```bash
# Install OpenTofu
brew install opentofu

# Install Terragrunt (optional, for DRY configs)
brew install terragrunt

# Verify
tofu version
terragrunt --version
```

## Next Steps

1. **Read:** [PLAN.md](PLAN.md) for complete architecture
2. **Implement:** Modules as needed (start with aws-eks or local-k3d)
3. **Test:** Use local-k3d module for local testing
4. **Deploy:** Provision production cluster, then deploy Monobase apps

---

**This infrastructure layer complements the existing application deployment template.**
