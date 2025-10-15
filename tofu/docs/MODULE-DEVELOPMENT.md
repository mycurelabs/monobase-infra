# Module Development Guide

Comprehensive guide for creating new OpenTofu modules for Monobase Infrastructure.

## Table of Contents

- [Overview](#overview)
- [Module Structure](#module-structure)
- [Standard Interface](#standard-interface)
- [Development Process](#development-process)
- [Best Practices](#best-practices)
- [Testing](#testing)
- [Documentation](#documentation)
- [Examples](#examples)

---

## Overview

### What is a Module?

An OpenTofu module is a reusable package of infrastructure code that:
- Provisions a complete Kubernetes cluster (EKS, AKS, GKE, K3s, k3d)
- Provides consistent interface (inputs/outputs)
- Encapsulates complexity
- Can be versioned and tested independently

### Module Goals for Monobase Infrastructure

1. **Multi-tenant Ready** - Support 5-30 clients per cluster
2. **Healthcare Compliant** - HIPAA/PHI-ready configurations
3. **Cost Optimized** - Right-sized resources, autoscaling
4. **Security First** - Encryption, IAM, network policies
5. **Easy to Use** - Sensible defaults, clear documentation

---

## Module Structure

### Standard File Layout

```
modules/
└── {provider}-{service}/
    ├── README.md              # Complete module documentation
    ├── main.tf                # Primary cluster resources
    ├── variables.tf           # All input parameters
    ├── outputs.tf             # Exported values
    ├── versions.tf            # Provider version constraints
    ├── {resource}.tf          # Logical groupings (vpc.tf, iam.tf, etc.)
    └── examples/              # Optional: Usage examples
        └── basic/
            ├── main.tf
            └── terraform.tfvars
```

### File Descriptions

**README.md**
- Module purpose and features
- Requirements (tools, credentials)
- Quick start example
- Input variables reference
- Output values reference
- Cost estimates
- Known limitations

**main.tf**
- Primary cluster resource (EKS cluster, AKS cluster, k3d cluster, etc.)
- Core dependencies
- Module dependencies
- Data sources (availability zones, AMIs, etc.)

**variables.tf**
- All configurable parameters
- Type definitions
- Default values
- Validation rules
- Clear descriptions

**outputs.tf**
- Cluster endpoint
- Kubeconfig
- OIDC/Workload Identity provider
- Networking details
- All sensitive values marked

**versions.tf**
- Terraform/OpenTofu version constraint
- Provider versions (pinned to major versions)

**{resource}.tf** (optional splits)
- `vpc.tf` - VPC, subnets, routing
- `iam.tf` - IAM roles, policies
- `network.tf` - Network configuration
- `security-groups.tf` - Firewall rules
- etc.

---

## Standard Interface

All modules MUST implement this common interface for consistency.

### Required Inputs

```hcl
# variables.tf

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "region" {
  description = "Cloud region or location (e.g., us-east-1, eastus, us-central1)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g., 1.28, 1.29)"
  type        = string
  default     = "1.28"
}

variable "node_instance_type" {
  description = "Instance type for worker nodes (e.g., m6i.2xlarge, Standard_D4s_v5)"
  type        = string
}

variable "node_count_min" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
  validation {
    condition     = var.node_count_min >= 1
    error_message = "Minimum node count must be at least 1"
  }
}

variable "node_count_max" {
  description = "Maximum number of worker nodes (for autoscaling)"
  type        = number
  default     = 20
  validation {
    condition     = var.node_count_max >= var.node_count_min
    error_message = "Maximum node count must be >= minimum node count"
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

### Required Outputs

```hcl
# outputs.tf

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = ...
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = var.cluster_name
}

output "cluster_id" {
  description = "Unique identifier for the cluster"
  value       = ...
}

output "kubeconfig" {
  description = "Kubectl configuration for cluster access"
  value       = ...
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA/Workload Identity (empty if not applicable)"
  value       = try(..., "")
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = ...
  sensitive   = true
}

output "region" {
  description = "Region where cluster is deployed"
  value       = var.region
}
```

### Optional but Recommended Outputs

```hcl
output "node_security_group_id" {
  description = "Security group ID for worker nodes"
  value       = try(..., "")
}

output "vpc_id" {
  description = "VPC ID where cluster is deployed"
  value       = try(..., "")
}

output "subnet_ids" {
  description = "Subnet IDs used by the cluster"
  value       = try(..., [])
}
```

---

## Development Process

### Step 1: Research Provider Requirements

Before creating a module, understand:

1. **Provider resources** - Check Terraform Registry docs
2. **Authentication** - How to authenticate (env vars, config files)
3. **Networking** - VPC/VNet requirements
4. **IAM/RBAC** - Permission models
5. **Storage** - CSI drivers, storage classes
6. **Workload Identity** - IRSA (AWS), Workload Identity (Azure/GCP)

**Resources:**
- [Terraform Registry](https://registry.terraform.io/browse/providers)
- Provider documentation
- Cloud provider best practices

### Step 2: Create Directory Structure

```bash
cd tofu/modules
mkdir -p {provider}-{service}
cd {provider}-{service}

# Create base files
touch README.md main.tf variables.tf outputs.tf versions.tf
```

### Step 3: Define versions.tf

Lock provider versions to prevent breaking changes:

```hcl
# versions.tf

terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {  # or azurerm, google, k3d, etc.
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Major version lock
    }
  }
}
```

### Step 4: Design Variables Interface

Start with the standard interface, then add provider-specific variables:

```hcl
# variables.tf

# Standard interface (required)
variable "cluster_name" { ... }
variable "region" { ... }
variable "kubernetes_version" { ... }
variable "node_instance_type" { ... }
variable "node_count_min" { ... }
variable "node_count_max" { ... }
variable "tags" { ... }

# Provider-specific variables
variable "vpc_cidr" {
  description = "CIDR block for VPC (AWS/GCP) or VNet (Azure)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_private_endpoint" {
  description = "Enable private cluster endpoint"
  type        = bool
  default     = false
}

# Feature flags
variable "enable_workload_identity" {
  description = "Enable Workload Identity/IRSA for service accounts"
  type        = bool
  default     = true
}

variable "enable_autoscaling" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}
```

**Guidelines:**
- Use `description` for all variables
- Provide sensible `default` values
- Use `validation` blocks for constraints
- Group related variables together
- Comment complex configurations

### Step 5: Implement Core Resources

Create the primary cluster resource:

```hcl
# main.tf

# Data sources for dynamic lookups
data "aws_availability_zones" "available" {
  state = "available"
}

# Main cluster resource
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = var.enable_private_endpoint
    endpoint_public_access  = !var.enable_private_endpoint
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(var.tags, {
    Name      = var.cluster_name
    ManagedBy = "opentofu"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# Managed node groups
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = each.value.instance_types
  
  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  tags = var.tags
}
```

### Step 6: Add Supporting Resources

Split complex resources into separate files:

**vpc.tf** - Networking
```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpc"
  })
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}
```

**iam.tf** - IAM Roles
```hcl
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}
```

### Step 7: Define Outputs

Export all necessary values:

```hcl
# outputs.tf

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "kubeconfig" {
  description = "Kubectl configuration"
  value = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name = aws_eks_cluster.main.name
    endpoint     = aws_eks_cluster.main.endpoint
    ca_cert      = aws_eks_cluster.main.certificate_authority[0].data
  })
  sensitive = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = try(aws_iam_openid_connect_provider.cluster[0].arn, "")
}
```

### Step 8: Write Comprehensive README

See [Documentation](#documentation) section below.

---

## Best Practices

### Code Organization

✅ **DO:**
- Split large files logically (vpc.tf, iam.tf, security-groups.tf)
- Use consistent naming conventions
- Group related resources together
- Add comments for complex logic
- Use data sources for dynamic lookups
- Tag all resources consistently

❌ **DON'T:**
- Hardcode values that should be variables
- Create overly complex modules (split if needed)
- Mix different resource types in one file randomly
- Leave provider credentials in code

### Variable Design

✅ **DO:**
- Provide sensible defaults for most variables
- Use validation blocks for constraints
- Document each variable clearly
- Use descriptive names
- Support optional features with boolean flags

❌ **DON'T:**
- Require too many mandatory variables
- Use vague variable names (e.g., `enable_feature`)
- Mix units (use seconds OR milliseconds, not both)

### Security

✅ **DO:**
- Enable encryption by default
- Mark sensitive outputs as `sensitive = true`
- Use IAM least privilege
- Enable audit logging
- Use private endpoints when possible

❌ **DON'T:**
- Disable security features by default
- Store secrets in variables
- Use overly permissive security groups

### Multi-Tenant Considerations

For Monobase Infrastructure, modules must support multiple clients per cluster:

✅ **DO:**
- Size for 5-30 clients per cluster
- Enable autoscaling (3-20 nodes)
- Support namespace isolation
- Enable resource quotas
- Configure network policies
- Use appropriate instance sizes (m6i.2xlarge or larger)

❌ **DON'T:**
- Size for single client only
- Disable autoscaling
- Use small instance types (t3.medium)
- Skip network isolation features

### Cost Optimization

✅ **DO:**
- Use spot instances where appropriate
- Enable autoscaling
- Use gp3 volumes (AWS) instead of gp2
- Configure VPC endpoints (AWS) for data transfer savings
- Right-size instances
- Enable cluster autoscaler

❌ **DON'T:**
- Use on-demand instances only
- Over-provision resources
- Use older generation instance types
- Leave unused resources running

### Healthcare/HIPAA Compliance

For healthcare deployments:

✅ **DO:**
- Enable encryption at rest
- Enable encryption in transit
- Configure audit logging
- Use private endpoints
- Enable VPC flow logs
- Implement network segmentation
- Tag resources for compliance tracking

---

## Testing

### Manual Testing Checklist

Before considering a module complete:

1. **Provision Test Cluster**
   ```bash
   cd tofu/modules/{your-module}
   tofu init
   tofu plan -var-file=test.tfvars
   tofu apply -var-file=test.tfvars
   ```

2. **Verify Cluster Access**
   ```bash
   tofu output -raw kubeconfig > ~/.kube/test-cluster
   export KUBECONFIG=~/.kube/test-cluster
   kubectl get nodes
   kubectl get pods -A
   ```

3. **Test Core Features**
   - [ ] Cluster accessible via kubectl
   - [ ] Nodes are healthy and ready
   - [ ] CoreDNS is running
   - [ ] CNI is working (pod networking)
   - [ ] Storage class available
   - [ ] LoadBalancer service type works (if applicable)

4. **Test Multi-Tenant Features**
   ```bash
   # Create test namespace
   kubectl create namespace test-client
   
   # Deploy sample workload
   kubectl run nginx --image=nginx -n test-client
   kubectl expose pod nginx --port=80 --type=LoadBalancer -n test-client
   ```

5. **Test Workload Identity (if supported)**
   ```bash
   # Verify OIDC provider (AWS)
   aws eks describe-cluster --name test-cluster --query "cluster.identity.oidc.issuer"
   
   # Or Workload Identity (GCP/Azure)
   ```

6. **Test Autoscaling (if enabled)**
   ```bash
   # Deploy resource-intensive workload
   kubectl run stress --image=polinux/stress -- stress --cpu 8
   
   # Watch nodes scale up
   kubectl get nodes -w
   ```

7. **Clean Up**
   ```bash
   tofu destroy -var-file=test.tfvars
   ```

### Automated Testing (Advanced)

For production modules, consider:

**Terratest (Go)**
```go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestEKSModule(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../modules/aws-eks",
        Vars: map[string]interface{}{
            "cluster_name": "test-cluster",
            "region":       "us-east-1",
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
    assert.NotEmpty(t, clusterEndpoint)
}
```

**Kitchen-Terraform**
- Test infrastructure with InSpec
- Verify compliance requirements
- Test multiple scenarios

---

## Documentation

Every module MUST have comprehensive README.md:

### README.md Template

```markdown
# {Provider} {Service} Module

Brief description of what this module does.

## Features

- ✅ Feature 1
- ✅ Feature 2
- ✅ Feature 3

## Requirements

- OpenTofu >= 1.6
- {Provider} CLI configured
- Appropriate cloud credentials

## Quick Start

\`\`\`hcl
module "cluster" {
  source = "../../modules/{provider}-{service}"
  
  cluster_name       = "my-cluster"
  region             = "us-east-1"
  kubernetes_version = "1.28"
  
  # ... other configuration
}
\`\`\`

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of cluster | string | - | yes |
| region | Cloud region | string | - | yes |
| kubernetes_version | K8s version | string | "1.28" | no |

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| cluster_endpoint | API endpoint | no |
| kubeconfig | Kubectl config | yes |
| oidc_provider_arn | OIDC provider | no |

## Cost Estimates

Approximate monthly costs (based on defaults):
- Control plane: $X
- Worker nodes: $Y
- Networking: $Z
- **Total: ~$XXX/month**

## Known Limitations

- Limitation 1
- Limitation 2

## Examples

See `examples/` directory for complete examples.

## Support

For issues, see [main repository](../../README.md).
```

### Documentation Best Practices

✅ **DO:**
- Document every variable and output
- Provide cost estimates
- Include complete examples
- List all prerequisites
- Document limitations
- Add troubleshooting section

❌ **DON'T:**
- Assume users know the cloud provider
- Skip examples
- Leave outdated documentation
- Forget to document breaking changes

---

## Examples

### Example 1: Minimal AWS EKS Module

```hcl
# modules/aws-eks/main.tf (simplified)

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.subnet_ids
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name  = aws_eks_cluster.main.name
  node_role_arn = aws_iam_role.node.arn
  subnet_ids    = var.subnet_ids

  scaling_config {
    desired_size = var.node_count_min
    max_size     = var.node_count_max
    min_size     = var.node_count_min
  }

  instance_types = [var.node_instance_type]
}
```

### Example 2: k3d Local Module

```hcl
# modules/local-k3d/main.tf

terraform {
  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = "~> 0.0.6"
    }
  }
}

resource "k3d_cluster" "main" {
  name    = var.cluster_name
  servers = 1
  agents  = 2

  port {
    host_port      = 80
    container_port = 80
    node_filters   = ["loadbalancer"]
  }

  k3s {
    extra_args {
      arg          = "--disable=traefik"
      node_filters = ["server:*"]
    }
  }
}

output "kubeconfig" {
  value     = k3d_cluster.main.credentials[0].raw
  sensitive = true
}
```

### Example 3: Provider-Agnostic Interface Usage

```hcl
# clusters/my-cluster/main.tf

module "cluster" {
  source = "../../modules/aws-eks"  # Or azure-aks, gcp-gke, etc.
  
  # Standard interface (works with all modules)
  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version
  
  # Provider-specific variables
  vpc_cidr                = "10.0.0.0/16"
  enable_private_endpoint = false
  
  tags = {
    Environment = "production"
    ManagedBy   = "opentofu"
  }
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}
```

---

## Checklist for New Modules

Use this checklist when creating a new module:

### Planning
- [ ] Research provider requirements and best practices
- [ ] Review existing modules for consistency
- [ ] Design variable interface (standard + provider-specific)
- [ ] Plan resource organization (main.tf vs split files)

### Implementation
- [ ] Create directory structure
- [ ] Define versions.tf with provider constraints
- [ ] Implement variables.tf with validation
- [ ] Create core resources in main.tf
- [ ] Add supporting resources (VPC, IAM, etc.)
- [ ] Implement all required outputs
- [ ] Add provider-specific features
- [ ] Tag all resources appropriately

### Testing
- [ ] Test module provisioning with test.tfvars
- [ ] Verify cluster access with kubectl
- [ ] Test core features (DNS, networking, storage)
- [ ] Test multi-tenant capabilities
- [ ] Test autoscaling (if enabled)
- [ ] Test workload identity (if supported)
- [ ] Document test results
- [ ] Clean up test resources

### Documentation
- [ ] Write comprehensive README.md
- [ ] Document all variables with descriptions
- [ ] Document all outputs
- [ ] Provide quick start example
- [ ] Add cost estimates
- [ ] Document known limitations
- [ ] Include troubleshooting section
- [ ] Add usage examples

### Security & Compliance
- [ ] Enable encryption at rest
- [ ] Enable encryption in transit
- [ ] Configure audit logging
- [ ] Use IAM least privilege
- [ ] Mark sensitive outputs
- [ ] Enable private endpoints (optional)
- [ ] Configure network policies
- [ ] Tag for compliance tracking

### Multi-Tenant Requirements
- [ ] Size for 5-30 clients
- [ ] Enable autoscaling (3-20 nodes)
- [ ] Use appropriate instance sizes
- [ ] Support namespace isolation
- [ ] Configure resource quotas
- [ ] Enable network policies

### Finalization
- [ ] Run `tofu fmt` on all files
- [ ] Run `tofu validate`
- [ ] Update main tofu/README.md with new module
- [ ] Test module from clusters/default-cluster
- [ ] Create PR with module
- [ ] Update PLAN.md status

---

## Common Pitfalls

### Pitfall 1: Hardcoding Values

❌ **Bad:**
```hcl
resource "aws_subnet" "private" {
  cidr_block = "10.0.1.0/24"  # Hardcoded
}
```

✅ **Good:**
```hcl
resource "aws_subnet" "private" {
  cidr_block = cidrsubnet(var.vpc_cidr, 4, 1)  # Calculated
}
```

### Pitfall 2: Missing Validation

❌ **Bad:**
```hcl
variable "node_count_min" {
  type = number
}
```

✅ **Good:**
```hcl
variable "node_count_min" {
  type = number
  validation {
    condition     = var.node_count_min >= 1
    error_message = "Minimum node count must be at least 1"
  }
}
```

### Pitfall 3: Forgetting Dependencies

❌ **Bad:**
```hcl
resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name
  # Missing depends_on for IAM policy attachment
}
```

✅ **Good:**
```hcl
resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name
  
  depends_on = [
    aws_iam_role_policy_attachment.node_policy
  ]
}
```

### Pitfall 4: Exposing Sensitive Data

❌ **Bad:**
```hcl
output "kubeconfig" {
  value = local.kubeconfig
}
```

✅ **Good:**
```hcl
output "kubeconfig" {
  value     = local.kubeconfig
  sensitive = true
}
```

### Pitfall 5: Poor Resource Naming

❌ **Bad:**
```hcl
resource "aws_vpc" "vpc" {
  # Name collision risk
}
```

✅ **Good:**
```hcl
resource "aws_vpc" "main" {
  tags = {
    Name = "${var.cluster_name}-vpc"  # Clear, unique name
  }
}
```

---

## Reference Modules

Study these well-implemented modules:

1. **tofu/modules/aws-eks/** - Complete production EKS
2. **tofu/modules/local-k3d/** - Simple, focused k3d
3. **tofu/modules/azure-aks/** - Azure Workload Identity pattern
4. **tofu/modules/gcp-gke/** - GCP Autopilot option

---

## Additional Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Terraform Registry](https://registry.terraform.io/) (compatible)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Azure AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [GCP GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)

---

## Getting Help

- Review existing modules in `tofu/modules/`
- Check PLAN.md for architecture overview
- See CLUSTER-PROVISIONING.md for usage patterns
- Consult MULTI-TENANT-SIZING.md for capacity planning

---

**Ready to create a new module? Follow this guide step-by-step and refer to existing modules for examples.**
