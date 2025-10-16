# Terraform/OpenTofu Modules

Reusable infrastructure-as-code modules for provisioning Kubernetes clusters.

## Overview

This directory contains **reusable Terraform/OpenTofu modules** for cluster provisioning.

**What's here:** Infrastructure modules (internal implementation)
**What you deploy:** Cluster configurations in `../clusters/` (root level)
**Complements:** Application deployment in `../charts/` and `../config/`

## Quick Start

**Note:** You typically work with cluster configs in `../clusters/`, not these modules directly.

```bash
# Cluster configs are at root level now:
../clusters/
├── default-cluster/     # Reference template
├── k3d-local/           # Local dev
└── your-cluster/        # Your clusters (gitignored)

# Use the provision script:
./scripts/provision.sh --cluster your-cluster

# Or manually:
cd ../clusters/your-cluster
terraform init
terraform plan
terraform apply
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
Single Cluster (provisioned via ../clusters/)
├── client-a-prod namespace    ← Deploy via monobase-infra charts
├── client-b-prod namespace    ← Deploy via monobase-infra charts
├── client-c-staging namespace ← Deploy via monobase-infra charts
└── gateway-system (shared)
```

**Cluster sizing:** Autoscales from 3-20 nodes based on client load

## Reference Configuration

**`../clusters/default-cluster/`** - Complete reference template (at root level)

Contains:
- main.tf - Module usage (references modules from this directory)
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

## Documentation

Comprehensive cluster provisioning documentation is available in the main docs:

- **[Cluster Provisioning Guide](../docs/getting-started/CLUSTER-PROVISIONING.md)** - Complete provisioning workflows for all platforms
- **[Cluster Sizing Guide](../docs/operations/CLUSTER-SIZING.md)** - Multi-tenant capacity planning and cost analysis
- **[Module Development Guide](../docs/development/MODULE-DEVELOPMENT.md)** - Create custom OpenTofu modules

## Next Steps

1. **Read:** [Cluster Provisioning Guide](../docs/getting-started/CLUSTER-PROVISIONING.md) for complete workflows
2. **Implement:** Modules as needed (start with aws-eks or local-k3d)
3. **Test:** Use local-k3d module for local testing
4. **Deploy:** Provision production cluster, then deploy Monobase apps

---

**This infrastructure layer complements the existing application deployment template.**
