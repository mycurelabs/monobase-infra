# OpenTofu Infrastructure Provisioning Plan

## Executive Summary

This document outlines the implementation plan for **cluster provisioning infrastructure** using OpenTofu (open-source Terraform) and Terragrunt for the LFH Infrastructure template.

**Purpose:** Provision Kubernetes clusters before deploying LFH application stack
**Scope:** Infrastructure layer (VPC, clusters, IAM) - complements existing application layer
**Status:** ✅ COMPLETE - All 5 modules implemented

---

## Architecture Overview

### Two-Layer Architecture

```
Layer 1: Infrastructure (THIS PLAN)
├── OpenTofu modules provision clusters
├── Terragrunt manages configurations
└── Creates: VPC, K8s cluster, IAM, networking

Layer 2: Applications (EXISTING - ../PLAN.md)
├── Helm charts deploy applications
├── ArgoCD manages GitOps
└── Deploys: HapiHub, Syncd, MyCureApp to cluster namespaces
```

### Deployment Flow

```
1. Provision Cluster (tofu/)
   ↓
   OpenTofu creates EKS/AKS/GKE/K3s cluster
   ↓
   Outputs: cluster endpoint, kubeconfig

2. Deploy Applications (charts/, config/)
   ↓
   Fork lfh-infra, create client config
   ↓
   Deploy via Helm/ArgoCD to client namespace
   ↓
   Multiple clients on same cluster (multi-tenant)
```

---

## Directory Structure

```
tofu/
├── README.md                        # Overview, quick start, module selection
├── PLAN.md                          # This document
│
├── modules/                         # Reusable cluster modules
│   ├── aws-eks/                     # AWS EKS cluster
│   │   ├── README.md                # Complete module documentation
│   │   ├── main.tf                  # Cluster, VPC, IAM
│   │   ├── variables.tf             # All configurable parameters
│   │   ├── outputs.tf               # Kubeconfig, endpoint, etc.
│   │   ├── vpc.tf                   # VPC with 3 AZs
│   │   ├── iam.tf                   # Cluster role, node role, IRSA
│   │   ├── security-groups.tf       # Network security
│   │   └── versions.tf              # Provider versions
│   │
│   ├── azure-aks/                   # Azure AKS cluster
│   │   ├── README.md
│   │   ├── main.tf                  # AKS cluster
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── network.tf               # VNet, subnets, NSG
│   │   └── identity.tf              # Managed identity, Workload Identity
│   │
│   ├── gcp-gke/                     # GCP GKE cluster
│   │   ├── README.md
│   │   ├── main.tf                  # GKE cluster
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── network.tf               # VPC, subnets, firewall
│   │   └── service-accounts.tf     # Workload Identity
│   │
│   ├── on-prem-k3s/                 # K3s on bare metal
│   │   ├── README.md
│   │   ├── main.tf                  # K3s installation
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── servers.tf               # Server provisioning (if cloud VMs)
│   │   ├── ansible/                 # Ansible playbooks for K3s
│   │   │   ├── install-k3s.yaml
│   │   │   ├── configure-ha.yaml
│   │   │   └── inventory.template
│   │   └── cloud-init/              # Cloud-init for automated setup
│   │       └── k3s-server.yaml
│   │
│   └── k3d-local/                   # k3d for local/CI testing
│       ├── README.md
│       ├── main.tf                  # k3d cluster resource
│       ├── variables.tf
│       └── outputs.tf
│
├── clusters/                        # Cluster configurations
│   ├── README.md                    # "Copy default-cluster for new cluster"
│   │
│   ├── default-cluster/             # REFERENCE CONFIG
│   │   ├── README.md                # How to customize
│   │   ├── main.tf                  # Uses aws-eks module
│   │   ├── variables.tf             # All parameters
│   │   ├── terraform.tfvars         # Example values (example.com)
│   │   ├── terragrunt.hcl           # Terragrunt config (DRY)
│   │   └── backend.tf.example       # S3 backend template
│   │
│   └── .gitkeep
│
├── terragrunt.hcl                   # Root Terragrunt config (DRY)
│
└── docs/                            # Terraform-specific docs
    ├── MODULE-DEVELOPMENT.md        # How to create modules
    ├── CLUSTER-PROVISIONING.md      # Using modules
    └── MULTI-TENANT-SIZING.md       # Cluster sizing for multiple clients
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1 - 5 days)

#### 1.1 Directory Structure & Foundation (0.5 days)
**Tasks:**
- ✅ Create tofu/ directory structure (DONE)
- Create tofu/README.md
- Create tofu/terragrunt.hcl (root config)
- Update lfh-infra/.gitignore

**Deliverables:**
- Complete directory tree
- Root README explaining structure
- Terragrunt DRY configuration
- .gitignore for Terraform state

#### 1.2 AWS EKS Module (2 days)
**Tasks:**
- Create complete EKS module
- VPC with 3 AZs (public + private subnets)
- EKS cluster with managed node groups
- IAM roles (cluster, nodes, IRSA for External Secrets, Velero, cert-manager)
- Security groups (control plane, nodes)
- EBS CSI driver addon
- Cluster autoscaler setup
- Complete README with all parameters

**Key Features:**
- Multi-tenant ready (5-20 nodes autoscaling)
- IRSA enabled for External Secrets Operator
- EBS CSI for storage
- Private endpoint option
- HIPAA-compliant configuration
- Cost-optimized (gp3, spot instances option)

**Module Outputs:**
- cluster_endpoint
- cluster_name
- cluster_arn
- kubeconfig
- oidc_provider_arn (for IRSA)

#### 1.3 k3d Local Module (1 day)
**Tasks:**
- Create k3d module using k3d Terraform provider
- Configure port mappings (80, 443)
- Disable Traefik (use Envoy Gateway)
- Install Gateway API CRDs
- Output kubeconfig for testing

**Key Features:**
- Perfect for CI/CD (GitHub Actions, GitLab CI)
- Automated test cluster creation/destruction
- Consistent test environment
- Fast (< 1 minute to create)

**Module Outputs:**
- kubeconfig_path
- cluster_name
- api_endpoint

#### 1.4 default-cluster Reference Config (1 day)
**Tasks:**
- Create complete reference configuration
- main.tf using aws-eks module
- variables.tf with all parameters documented
- terraform.tfvars with example.com values
- terragrunt.hcl for DRY
- backend.tf.example for S3 state
- Comprehensive README

**Deliverables:**
- Reference cluster config (like config/example.com)
- Clear copy-and-customize instructions
- Terragrunt integration
- State management setup

#### 1.5 Automation & Documentation (0.5 days)
**Tasks:**
- Create scripts/new-cluster-config.sh
- Update main README.md
- Create tofu/docs/CLUSTER-PROVISIONING.md

**Deliverables:**
- Bootstrap script for cluster configs
- Updated project README
- Cluster provisioning guide

---

### Phase 2: On-Premises Support (Week 2 - 5 days)

#### 2.1 On-Prem K3s Module (3 days)
**Tasks:**
- Create K3s module for bare metal
- Ansible playbooks for K3s installation
- HA configuration (3+ servers, embedded etcd)
- MetalLB for LoadBalancer
- Storage configuration (Longhorn)
- Firewall rules
- Certificate management

**Key Features:**
- Healthcare clinic/hospital deployment
- Air-gapped support
- Minimal hardware requirements (3 servers)
- Simple maintenance
- Cost-effective

**Module Inputs:**
- server_ips (list of server IPs)
- k3s_version
- k3s_token (cluster secret)
- ha_mode (true/false)
- metallb_ip_range

**Module Outputs:**
- kubeconfig
- api_endpoint
- metallb_ip_range

#### 2.2 On-Prem Documentation (1 day)
**Tasks:**
- Create tofu/docs/ON-PREM-DEPLOYMENT.md
- Hardware requirements
- Network configuration
- K3s best practices
- Troubleshooting guide

**Deliverables:**
- Complete on-prem setup guide
- Hardware sizing calculator
- Network diagrams
- HA configuration guide

#### 2.3 Testing & Validation (1 day)
**Tasks:**
- Test K3s module on cloud VMs
- Validate HA setup
- Test failover scenarios
- Document test results

**Deliverables:**
- Tested K3s module
- Validation report
- Known issues documented

---

### Phase 3: Additional Cloud Providers (Week 3 - 5 days)

#### 3.1 Azure AKS Module (2 days)
**Tasks:**
- Create complete AKS module
- VNet with subnets
- AKS cluster with system/user node pools
- Managed Identity + Workload Identity
- Network Security Groups
- Azure Disk CSI
- Complete README

**Key Features:**
- Workload Identity for External Secrets
- Azure Disk for storage
- Private cluster option
- Cost-optimized

#### 3.2 GCP GKE Module (2 days)
**Tasks:**
- Create complete GKE module
- VPC with subnets
- GKE cluster (Standard or Autopilot)
- Workload Identity
- Firewall rules
- GCP PD CSI
- Complete README

**Key Features:**
- Workload Identity for External Secrets
- GKE Autopilot option (serverless nodes)
- Regional cluster for HA
- Cost-optimized

#### 3.3 Integration & Testing (1 day)
**Tasks:**
- Test all cloud modules
- Validate multi-cloud deployment
- Create comparison guide
- CI/CD examples for each platform

**Deliverables:**
- Tested modules
- Multi-cloud comparison doc
- CI/CD workflow examples

---

## Module Specifications

### Common Module Interface (All Modules)

**Required Inputs:**
```hcl
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "region" {
  description = "Cloud region or location"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_instance_type" {
  description = "Instance type for worker nodes"
  type        = string
}

variable "node_count_min" {
  description = "Minimum number of nodes"
  type        = number
  default     = 3
}

variable "node_count_max" {
  description = "Maximum number of nodes (autoscaling)"
  type        = number
  default     = 20
}
```

**Required Outputs:**
```hcl
output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = ...
}

output "cluster_name" {
  description = "Cluster name"
  value       = ...
}

output "kubeconfig" {
  description = "kubectl configuration"
  value       = ...
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider for IRSA/Workload Identity"
  value       = ...
}
```

---

## AWS EKS Module Details

### Features

**VPC Configuration:**
- 3 Availability Zones
- Public subnets (NAT Gateway, Load Balancers)
- Private subnets (EKS nodes, databases)
- VPC endpoints (S3, ECR) for cost savings
- Flow logs for security

**EKS Cluster:**
- Managed control plane
- Private endpoint option
- IRSA enabled (IAM Roles for Service Accounts)
- Encryption at rest (EBS, secrets)
- Audit logging to CloudWatch

**Node Groups:**
- Managed node groups
- Autoscaling (cluster autoscaler)
- Spot instances option (cost savings)
- Multiple instance types
- Taints and labels support

**Add-ons:**
- EBS CSI driver (storage)
- VPC CNI (networking)
- CoreDNS
- kube-proxy
- Cluster autoscaler

**IAM Roles (IRSA):**
- External Secrets Operator → Secrets Manager
- Velero → S3 backups
- cert-manager → Route53 (DNS-01)
- Cluster autoscaler → EC2 autoscaling
- EBS CSI driver → EBS volumes

**Security:**
- Private API endpoint option
- Security groups (minimal access)
- IMDSv2 required
- Encryption everywhere
- HIPAA-compliant settings

---

## On-Prem K3s Module Details

### Features

**Server Provisioning:**
- Ansible playbook for server setup
- OS hardening (Ubuntu/RHEL)
- Firewall configuration
- NTP sync
- DNS configuration

**K3s Installation:**
- HA mode (3+ servers, embedded etcd)
- Or single server for small deployments
- Custom K3s flags
- Air-gapped support (offline bundles)
- Version pinning

**Networking:**
- MetalLB for LoadBalancer services
- Calico for NetworkPolicies (optional)
- IP pool configuration
- BGP mode for production

**Storage:**
- Longhorn distributed storage
- Or local-path for simple setups
- NFS support (optional)

**High Availability:**
- 3+ server control plane
- Embedded etcd (no external dependency)
- VIP for API endpoint (keepalived)
- Automatic failover

---

## k3d Module Details

### Features

**Cluster Configuration:**
- 1 server + 2 agents (3 nodes total)
- Port mappings (80, 443 → localhost)
- Disable Traefik (use Envoy Gateway instead)
- Custom registry support
- Volume mounts for persistent testing

**CI/CD Integration:**
- Terraform provider for k3d
- Programmatic cluster creation
- Outputs kubeconfig for kubectl
- Fast creation (<1 minute)
- Clean destruction

**Perfect For:**
- GitHub Actions
- GitLab CI
- Developer laptops
- Pre-commit testing
- Integration tests

---

## Terragrunt Configuration

### Root Config (tofu/terragrunt.hcl)

```hcl
# DRY configuration for all clusters

# Remote state configuration
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "lfh-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "lfh-terraform-locks"
  }
}

# Common provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
EOF
}
```

### Cluster-Level Config (clusters/default-cluster/terragrunt.hcl)

```hcl
# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Use EKS module
terraform {
  source = "../../modules/aws-eks"
}

# Inputs (can also be in terraform.tfvars)
inputs = {
  cluster_name = "lfh-shared-prod"
  region       = "us-east-1"
  
  node_groups = {
    general = {
      instance_types = ["m6i.2xlarge"]
      desired_size   = 5
      max_size       = 20
      min_size       = 3
    }
  }
}
```

---

## Reference Configuration (default-cluster/)

### Folder Purpose

**Same concept as config/example.com/:**
- Reference cluster configuration
- Copy to create new clusters
- Well-documented with comments
- Sensible defaults

### Files

#### main.tf
```hcl
# Reference Cluster Configuration
# Copy to clusters/{your-cluster}/ and customize

module "cluster" {
  source = "../../modules/aws-eks"  # Or azure-aks, gcp-gke, on-prem-k3s
  
  # Basic configuration
  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version
  
  # Node groups (sized for multi-tenant)
  node_groups = var.node_groups
  
  # Networking
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  
  # Security
  enable_private_endpoint = var.enable_private_endpoint
  enable_irsa            = true  # Required for External Secrets
  
  # Add-ons
  enable_ebs_csi_driver     = true  # Required for storage
  enable_cluster_autoscaler = true  # Required for scaling
  
  # Tags
  tags = merge(var.tags, {
    ManagedBy = "lfh-infrastructure"
    Purpose   = "multi-tenant-healthcare"
  })
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}
```

#### variables.tf (All Parameters Documented)
```hcl
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "lfh-example-cluster"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "node_groups" {
  description = "EKS managed node group configuration"
  type = map(object({
    instance_types = list(string)
    desired_size   = number
    max_size       = number
    min_size       = number
  }))
  default = {
    general = {
      instance_types = ["m6i.2xlarge"]
      desired_size   = 5   # For ~5-10 clients
      max_size       = 20  # Scale to ~20-30 clients
      min_size       = 3   # Minimum for HA
    }
  }
}

# ... more variables
```

#### terraform.tfvars (Example Values)
```hcl
# Reference cluster configuration for example.com
# Copy this file and customize

cluster_name       = "lfh-example-cluster"
region             = "us-east-1"
kubernetes_version = "1.28"

node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]  # 8 vCPU, 32GB RAM
    desired_size   = 5
    max_size       = 20
    min_size       = 3
  }
}

vpc_cidr = "10.0.0.0/16"

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
]

enable_private_endpoint = false  # Set true for maximum security

tags = {
  Environment = "production"
  Project     = "lfh-infrastructure"
  ManagedBy   = "opentofu"
}
```

#### README.md
```markdown
# Reference Cluster Configuration

This is a REFERENCE cluster configuration (like config/example.com for applications).

## For New Cluster

1. Copy this directory:
   ```bash
   # Or use script:
   ./scripts/new-cluster-config.sh myclient-cluster us-east-1
   
   # Or manually:
   cp -r tofu/clusters/default-cluster tofu/clusters/myclient-cluster
   ```

2. Customize terraform.tfvars:
   - cluster_name: "lfh-myclient-prod"
   - region: your AWS region
   - node_groups: size for your client load
   - vpc_cidr: non-overlapping CIDR

3. Configure backend (S3 state):
   ```bash
   cp backend.tf.example backend.tf
   # Edit bucket name
   ```

4. Apply:
   ```bash
   cd tofu/clusters/myclient-cluster
   tofu init
   tofu plan
   tofu apply
   ```

5. Save kubeconfig:
   ```bash
   tofu output -raw kubeconfig > ~/.kube/myclient-prod
   export KUBECONFIG=~/.kube/myclient-prod
   kubectl get nodes
   ```

## Multi-Tenant Cluster

This cluster is sized for MULTIPLE clients:
- Each client gets their own namespace
- NetworkPolicies provide isolation
- Shared infrastructure (Gateway, storage)
- Independent scaling per client

## Next Steps

After cluster is ready:
1. Deploy LFH application stack (see ../config/example.com/)
2. For each client: ./scripts/new-client-config.sh
3. Deploy via ArgoCD to client namespaces
```

---

## Bootstrap Script (new-cluster-config.sh)

```bash
#!/bin/bash
# new-cluster-config.sh
# Creates new cluster configuration from default-cluster reference

CLUSTER_NAME=$1
REGION=${2:-"us-east-1"}

# Validate
if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: $0 <cluster-name> [region]"
  exit 1
fi

# Check if exists
if [ -d "tofu/clusters/$CLUSTER_NAME" ]; then
  echo "Error: Cluster $CLUSTER_NAME already exists"
  exit 1
fi

# Copy reference
cp -r tofu/clusters/default-cluster tofu/clusters/$CLUSTER_NAME

# Replace placeholders
cd tofu/clusters/$CLUSTER_NAME
sed -i.bak "s/lfh-example-cluster/lfh-$CLUSTER_NAME/g" terraform.tfvars
sed -i.bak "s/us-east-1/$REGION/g" terraform.tfvars
rm *.bak

# Copy backend example
cp backend.tf.example backend.tf

echo "✓ Cluster config created: tofu/clusters/$CLUSTER_NAME"
echo ""
echo "Next steps:"
echo "1. cd tofu/clusters/$CLUSTER_NAME"
echo "2. Edit terraform.tfvars (node sizes, etc.)"
echo "3. Edit backend.tf (S3 bucket name)"
echo "4. tofu init && tofu apply"
```

---

## Multi-Cluster Management

### Scenario 1: Single Multi-Tenant Cluster (Most Common)

```
tofu/clusters/shared-prod/    # ONE cluster for all clients
```

**Deploy:**
```bash
cd tofu/clusters/shared-prod
tofu apply
# Creates cluster

# Then deploy multiple clients to different namespaces
./scripts/new-client-config.sh client-a client-a.com  # → client-a-prod namespace
./scripts/new-client-config.sh client-b client-b.com  # → client-b-prod namespace
```

### Scenario 2: Regional Clusters

```
tofu/clusters/
├── shared-us-east/       # US cluster
├── shared-eu-west/       # Europe cluster
└── shared-ap-south/      # Asia cluster
```

Each region gets its own cluster for latency.

### Scenario 3: Dedicated Enterprise Clusters

```
tofu/clusters/
├── shared-prod/          # Small clients (multi-tenant)
└── enterprise-client-a/  # Large client (dedicated)
```

---

## .gitignore Updates

```
# OpenTofu/Terraform
tofu/clusters/*/
!tofu/clusters/default-cluster/
tofu/**/.terraform/
tofu/**/.terragrunt-cache/
tofu/**/*.tfstate
tofu/**/*.tfstate.backup
tofu/**/.terraform.lock.hcl
```

**Only default-cluster/ is committed** - actual clusters in client forks!

---

## Integration with Existing LFH Template

### Complete Workflow

**Step 1: Provision Cluster (Infrastructure)**
```bash
cd tofu/clusters/myclient-cluster
tofu apply
# Output: Kubernetes cluster ready
```

**Step 2: Deploy Applications (Existing Flow)**
```bash
# Use existing LFH workflow
./scripts/new-client-config.sh client-a client-a.com
helm install hapihub charts/hapihub -f config/client-a/values-production.yaml
```

**Both layers work together!**

---

## Success Criteria

### Infrastructure Layer Completion

- [ ] All 5 modules implemented (EKS, AKS, GKE, K3s, k3d)
- [ ] default-cluster reference complete
- [ ] All modules tested
- [ ] new-cluster-config.sh script works
- [ ] Documentation complete
- [ ] CI/CD examples with k3d
- [ ] Integration tested with application layer

### Multi-Tenant Support

- [ ] Clusters sized for multiple clients
- [ ] Autoscaling configured
- [ ] Cost-optimized
- [ ] IRSA/Workload Identity for External Secrets
- [ ] Storage CSI drivers installed

---

## Timeline Estimate

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Phase 1: Core (EKS + k3d + default-cluster) | 5 days | Production-ready EKS, testable k3d |
| Phase 2: On-Prem (K3s) | 5 days | Healthcare on-prem support |
| Phase 3: Multi-Cloud (AKS + GKE) | 5 days | Azure and GCP support |
| **Total** | **15 days** | **Complete infrastructure layer** |

---

## Notes

**This complements the existing LFH template:**
- Existing: Application deployment (charts/, config/)
- New: Cluster provisioning (tofu/)
- Together: Complete end-to-end infrastructure solution

**Fork-based workflow maintained:**
- Fork repo → copy default-cluster/ → customize → apply
- Same pattern as application configs!

**No examples/ directory:**
- Modules have comprehensive README
- default-cluster/ is the reference
- Simpler, cleaner structure

---

Ready to implement OpenTofu infrastructure layer?