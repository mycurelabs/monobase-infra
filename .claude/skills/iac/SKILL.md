---
name: iac
description: Terraform/OpenTofu modules for 6 providers
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Infrastructure as Code Skill

## Available Modules

```
!ls terraform/modules/
```

## Module Overview

| Module | Provider | Key Features | Required CLI |
|--------|----------|--------------|-------------|
| `aws-eks` | AWS | EKS + VPC + IRSA + EBS CSI | `aws` |
| `azure-aks` | Azure | AKS + VNet + Workload Identity | `az` |
| `gcp-gke` | GCP | GKE + VPC + Workload Identity | `gcloud` |
| `do-doks` | DigitalOcean | DOKS + VPC + Spaces | `doctl` |
| `on-prem-k3s` | On-premises | K3s + Longhorn + MetalLB | SSH access |
| `local-k3d` | Local dev | k3d + Gateway API CRDs | `docker` |

All modules share common patterns:
- Deployment profiles: `small`, `medium`, `large` (auto-configures node sizes/counts)
- Outputs: `cluster_name`, `cluster_endpoint`, `configure_kubectl`
- Terraform >= 1.6 required

## Standard Module Structure

```
terraform/modules/{provider}/
  main.tf           # Primary resources
  variables.tf      # Input variables
  outputs.tf        # Output values
  versions.tf       # Provider requirements
  examples/         # Example tfvars files
```

## Provisioning Workflow

```bash
# 1. Copy example tfvars
cp terraform/modules/{provider}/examples/production.tfvars cluster/terraform.tfvars

# 2. Edit configuration
vim cluster/terraform.tfvars

# 3. Initialize
cd terraform/modules/{provider}
terraform init

# 4. Plan (review changes)
terraform plan -var-file=../../../cluster/terraform.tfvars

# 5. Apply
terraform apply -var-file=../../../cluster/terraform.tfvars

# 6. Configure kubectl
eval $(terraform output -raw configure_kubectl)

# 7. Bootstrap GitOps
mise run bootstrap
```

Or use the automated script:
```bash
mise run provision
```

## Validation Commands

```bash
# Validate all Terraform modules
mise run validate-tf

# Lint Terraform files
mise run lint-tf

# Format Terraform code
mise run fmt
```

## Key Variables (Common Across Providers)

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_name` | Cluster identifier | (required) |
| `kubernetes_version` | K8s version | `"1.28"` |
| `deployment_profile` | Size preset | `"small"` |

## Provider-Specific Notes

### AWS EKS
- Requires: VPC CIDR, availability zones, API access CIDRs
- Creates: VPC, subnets, NAT gateway, EKS cluster, managed node groups
- Static IPs: Elastic IPs (one per subnet/AZ) — see `docs/infrastructure/static-ip-aws.md`
- Auth: IRSA (IAM Roles for Service Accounts) for ESO, Velero, cert-manager

### Azure AKS
- Requires: resource group name, location
- Creates: VNet, AKS cluster, node pools, managed identities
- Static IPs: Public IP in node resource group (MC_*) — see `docs/infrastructure/static-ip-azure.md`
- Auth: Workload Identity for ESO, Velero

### GCP GKE
- Requires: project ID, region
- Creates: VPC, GKE cluster, node pools, service accounts
- Static IPs: Regional static IP — see `docs/infrastructure/static-ip-gcp.md`
- Auth: Workload Identity Federation for ESO, Velero, cert-manager

### DigitalOcean DOKS
- Requires: region
- Creates: VPC, DOKS cluster, node pool
- Static IPs: LoadBalancer name or FLIPOP operator — see `docs/infrastructure/static-ip-digitalocean.md`
- Auth: API token for ESO via External Secrets

### On-Prem K3s
- Requires: server IPs, SSH access, K3s token
- Creates: K3s cluster via SSH, optional Longhorn + MetalLB
- HA mode requires 3+ servers

### Local k3d
- Development/testing only
- Creates: k3d cluster with port mappings (8080→80, 8443→443)
- Disables Traefik (uses Envoy Gateway instead)
- Auto-installs Gateway API CRDs

## Teardown (Destructive)

```bash
# Automated (requires confirmation)
mise run teardown

# Manual
cd terraform/modules/{provider}
terraform destroy -var-file=../../../cluster/terraform.tfvars
```
