# Cluster Provisioning Guide

Complete guide for provisioning Kubernetes clusters using OpenTofu modules for Monobase Infrastructure.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Module Selection](#module-selection)
- [Provisioning Workflows](#provisioning-workflows)
- [Configuration Management](#configuration-management)
- [State Management](#state-management)
- [Multi-Cluster Scenarios](#multi-cluster-scenarios)
- [Troubleshooting](#troubleshooting)

---

## Overview

### What This Guide Covers

This guide walks you through:
1. **Choosing the right module** for your deployment target
2. **Setting up credentials** and prerequisites
3. **Creating cluster configurations** using the reference template
4. **Provisioning clusters** with OpenTofu/Terragrunt
5. **Managing state** and multiple clusters
6. **Connecting to clusters** and deploying applications

### Architecture Reminder

```
Layer 1: Infrastructure (THIS GUIDE)
├── terraform/ modules provision clusters
├── Terragrunt manages configurations
└── Creates: VPC, K8s cluster, IAM, networking

Layer 2: Applications (../PLAN.md, ../charts/, ../config/)
├── Helm charts deploy applications
└── ArgoCD manages GitOps
```

---

## Prerequisites

### Required Tools

Install these tools before provisioning:

```bash
# OpenTofu (Terraform alternative)
brew install opentofu

# Terragrunt (optional, for DRY configs)
brew install terragrunt

# kubectl (Kubernetes CLI)
brew install kubectl

# Cloud provider CLI (choose one)
brew install awscli      # AWS
brew install azure-cli   # Azure
brew install google-cloud-sdk  # GCP

# For k3d (local testing)
brew install k3d

# Verify installations
tofu version
terragrunt --version
kubectl version --client
```

### Cloud Provider Authentication

#### AWS (for aws-eks module)

```bash
# Configure AWS credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"

# Verify
aws sts get-caller-identity
```

#### Azure (for azure-aks module)

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "Your Subscription Name"

# Verify
az account show
```

#### GCP (for gcp-gke module)

```bash
# Login to GCP
gcloud auth login
gcloud auth application-default login

# Set project
gcloud config set project your-project-id

# Verify
gcloud config list
```

#### On-Prem / Local (for on-prem-k3s / local-k3d)

No cloud credentials needed!

---

## Module Selection

Choose the right module based on your deployment target:


### Decision Matrix

| Scenario | Module | When to Use |
|----------|--------|-------------|
| **Production AWS** | `aws-eks` | Multi-tenant SaaS in AWS |
| **Production Azure** | `azure-aks` | Multi-tenant SaaS in Azure |
| **Production GCP** | `gcp-gke` | Multi-tenant SaaS in GCP |
| **Healthcare Clinic/Hospital** | `on-prem-k3s` | On-premises, air-gapped |
| **Local Testing** | `local-k3d` | Developer laptop, CI/CD |
| **Staging/Testing** | `local-k3d` or cloud | Pre-production validation |

### Module Comparison

| Feature | aws-eks | azure-aks | gcp-gke | on-prem-k3s | local-k3d |
|---------|---------|-----------|---------|-------------|-----------|
| **Setup Time** | 15-20 min | 15-20 min | 15-20 min | 30-60 min | <1 min |
| **Monthly Cost** | ~$300+ | ~$300+ | ~$300+ | Hardware only | $0 |
| **Managed Control Plane** | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Autoscaling** | ✅ | ✅ | ✅ | ⚠️ Manual | ❌ |
| **Multi-Tenant** | ✅ | ✅ | ✅ | ✅ | ⚠️ Testing only |
| **HIPAA/PHI Ready** | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Workload Identity** | IRSA | Workload Identity | Workload Identity | ❌ | ❌ |
| **Storage** | EBS CSI | Azure Disk | GCP PD | Longhorn/Local | Local |
| **LoadBalancer** | ELB/ALB | Azure LB | GCP LB | MetalLB | Host ports |

---

## Provisioning Workflows

### Workflow 1: Quick Start (AWS EKS Example)

**Goal:** Provision production EKS cluster in 15 minutes

```bash
# 1. Copy reference cluster config
cd /path/to/monobase-infra
cp -r clusters/default-cluster clusters/production-cluster

# 2. Navigate to new cluster
cd clusters/production-cluster

# 3. Edit configuration
vim terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
cluster_name       = "monobase-prod"
region             = "us-east-1"
kubernetes_version = "1.28"

node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]  # 8 vCPU, 32GB RAM
    desired_size   = 5   # Start with 5 nodes
    max_size       = 20  # Scale up to 20 nodes
    min_size       = 3   # Minimum for HA
  }
}

vpc_cidr = "10.0.0.0/16"

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
]

enable_private_endpoint = false  # true for max security

tags = {
  Environment = "production"
  Project     = "monobase-infrastructure"
  ManagedBy   = "opentofu"
  Client      = "multi-tenant"
}
```

```bash
# 4. Configure backend (S3 state storage)
cp backend.tf.example backend.tf
vim backend.tf
```

Edit `backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "your-company-terraform-state"
    key            = "monobase/production-cluster/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

```bash
# 5. Initialize OpenTofu
tofu init

# 6. Review plan
tofu plan

# 7. Provision cluster (15-20 minutes)
tofu apply

# 8. Get kubeconfig
tofu output -raw kubeconfig > ~/.kube/monobase-prod
chmod 600 ~/.kube/monobase-prod
export KUBECONFIG=~/.kube/monobase-prod

# 9. Verify cluster
kubectl get nodes
kubectl get pods -A

# 10. Deploy Monobase applications (see ../charts/, ../config/)
cd ../../../
./scripts/new-client-config.sh client-a client-a.com
```

### Workflow 2: Using Terragrunt (DRY Configuration)

**Goal:** Manage multiple clusters with less duplication

```bash
# 1. Edit root Terragrunt config (if needed)
vim terraform/terragrunt.hcl
```


Root config (already configured):
```hcl
# terraform/terragrunt.hcl

remote_state {
  backend = "s3"
  config = {
    bucket         = "your-company-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

```bash
# 2. Copy default-cluster
cp -r clusters/default-cluster clusters/production-cluster

# 3. Use terragrunt.hcl instead of backend.tf
cd clusters/production-cluster
rm backend.tf backend.tf.example

# 4. Edit cluster config
vim terraform.tfvars  # Same as Workflow 1

# 5. Run with Terragrunt
terragrunt init
terragrunt plan
terragrunt apply

# 6. Get kubeconfig
terragrunt output -raw kubeconfig > ~/.kube/monobase-prod
```

**Benefits:**
- DRY backend configuration
- Shared provider versions
- Easier multi-cluster management

### Workflow 3: Local Testing with k3d

**Goal:** Test Monobase applications locally before cloud deployment

```bash
# 1. Copy k3d config
cp -r clusters/default-cluster clusters/local-test
cd clusters/local-test

# 2. Switch to k3d module
vim main.tf
```

Change module source:
```hcl
module "cluster" {
  source = "../../modules/local-k3d"  # Changed from aws-eks

  cluster_name = "monobase-local"
  servers      = 1
  agents       = 2
}
```

```bash
# 3. Minimal tfvars for k3d
cat > terraform.tfvars <<EOF
cluster_name = "monobase-local"
EOF

# 4. Provision (< 1 minute!)
tofu init
tofu apply

# 5. Get kubeconfig and test
tofu output -raw kubeconfig > ~/.kube/monobase-local
export KUBECONFIG=~/.kube/monobase-local
kubectl get nodes

# 6. Test Monobase deployment
kubectl create namespace test-client
helm install api ../../charts/api -n test-client

# 7. Cleanup when done
tofu destroy
```

### Workflow 4: On-Premises K3s Deployment

**Goal:** Deploy to healthcare clinic/hospital

```bash
# 1. Prepare servers (3+ physical/VM servers)
# - Install Ubuntu 22.04 or RHEL 8+
# - Configure static IPs
# - Open required ports (6443, 8472, 10250, etc.)

# 2. Copy k3s config
cp -r clusters/default-cluster clusters/clinic-onprem
cd clusters/clinic-onprem

# 3. Switch to k3s module
vim main.tf
```

Change module:
```hcl
module "cluster" {
  source = "../../modules/on-prem-k3s"
  
  cluster_name = "clinic-prod"
  
  server_ips = [
    "192.168.1.10",
    "192.168.1.11",
    "192.168.1.12"
  ]
  
  k3s_version      = "v1.28.5+k3s1"
  ha_mode          = true
  metallb_ip_range = "192.168.1.100-192.168.1.110"
}
```

```bash
# 4. Provision with Ansible
tofu init
tofu apply

# This will:
# - Install K3s on all servers
# - Configure HA with embedded etcd
# - Install MetalLB for LoadBalancer
# - Setup Longhorn for storage

# 5. Get kubeconfig
tofu output -raw kubeconfig > ~/.kube/clinic-prod
```

---

## Configuration Management

### Understanding default-cluster/

The `clusters/default-cluster/` is a **reference configuration** (like `config/example.com/` for apps).

**Files:**

```
default-cluster/
├── README.md                 # Customization guide
├── main.tf                   # Module usage
├── variables.tf              # All parameters
├── outputs.tf                # Exported values
├── terraform.tfvars          # Example values
├── terragrunt.hcl            # Terragrunt config (optional)
└── backend.tf.example        # S3 backend template
```

### Customization Guide

#### 1. Cluster Naming

```hcl
# terraform.tfvars

cluster_name = "monobase-{environment}-{region}"
# Examples:
# - "monobase-prod-us"
# - "monobase-staging-eu"
# - "clinic-prod"
```

#### 2. Node Sizing

See [CLUSTER-SIZING.md](../operations/CLUSTER-SIZING.md) for detailed guidance.

**Small (5-10 clients):**
```hcl
node_groups = {
  general = {
    instance_types = ["m6i.xlarge"]  # 4 vCPU, 16GB
    desired_size   = 3
    max_size       = 10
    min_size       = 3
  }
}
```

**Medium (10-20 clients):**
```hcl
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]  # 8 vCPU, 32GB
    desired_size   = 5
    max_size       = 15
    min_size       = 3
  }
}
```

**Large (20-30 clients):**
```hcl
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]
    desired_size   = 8
    max_size       = 20
    min_size       = 5
  }
}
```

#### 3. Networking

```hcl
# Non-overlapping CIDR blocks for multiple clusters
vpc_cidr = "10.0.0.0/16"   # Cluster 1
vpc_cidr = "10.1.0.0/16"   # Cluster 2
vpc_cidr = "10.2.0.0/16"   # Cluster 3

# Availability zones (high availability)
availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"  # Recommended: 3 AZs
]
```

#### 4. Security

```hcl
# Maximum security (requires VPN/bastion)
enable_private_endpoint = true
enable_public_endpoint  = false

# Balanced (default)
enable_private_endpoint = false
enable_public_endpoint  = true

# Enable all security features
enable_irsa       = true  # For External Secrets
enable_flow_logs  = true  # Network monitoring
```

#### 5. Kubernetes Version

```hcl
# Always use stable versions
kubernetes_version = "1.28"  # Current stable
kubernetes_version = "1.29"  # Newer version

# Check cloud provider for supported versions:
# AWS: aws eks describe-addon-versions
# Azure: az aks get-versions --location eastus
# GCP: gcloud container get-server-config
```

#### 6. Tags

```hcl
tags = {
  Environment = "production"     # production, staging, development
  Project     = "monobase-infrastructure"
  ManagedBy   = "opentofu"
  CostCenter  = "engineering"
  Client      = "multi-tenant"   # or specific client name
  Compliance  = "hipaa"          # For healthcare
}
```

### Switching Cloud Providers

To switch from AWS to Azure or GCP, change the module source:

```hcl
# main.tf

# FROM:
module "cluster" {
  source = "../../modules/aws-eks"
  ...
}

# TO Azure:
module "cluster" {
  source = "../../modules/azure-aks"
  ...
}

# TO GCP:
module "cluster" {
  source = "../../modules/gcp-gke"
  ...
}
```

Then adjust provider-specific variables in `terraform.tfvars`.

---

## State Management

### Local State (Testing Only)

By default, state is stored locally:

```
clusters/my-cluster/
└── terraform.tfstate  # ⚠️ Do not commit to git
```

**⚠️ WARNING:** Local state is not suitable for:
- Production clusters
- Team collaboration
- CI/CD pipelines

### Remote State (Recommended)

Use S3 backend for production:

#### Step 1: Create S3 Bucket and DynamoDB Table

```bash
# Create S3 bucket for state
aws s3 mb s3://your-company-terraform-state --region us-east-1

# Enable versioning (recover from mistakes)
aws s3api put-bucket-versioning \
  --bucket your-company-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-company-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

#### Step 2: Configure Backend

```hcl
# backend.tf

terraform {
  backend "s3" {
    bucket         = "your-company-terraform-state"
    key            = "monobase/production-cluster/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

#### Step 3: Migrate State (if needed)

```bash
# If you have local state, migrate to S3
tofu init -migrate-state
```

### State Best Practices

✅ **DO:**
- Use remote state for all production clusters
- Enable state locking (DynamoDB)
- Enable versioning on S3 bucket
- Encrypt state at rest
- Use unique state keys per cluster
- Backup state regularly

❌ **DON'T:**
- Commit state files to git (.gitignore them)
- Share state files manually
- Edit state files directly
- Use local state for production

### State File Organization

```
S3 Bucket: your-company-terraform-state
├── monobase/
│   ├── production-cluster/terraform.tfstate
│   ├── staging-cluster/terraform.tfstate
│   ├── eu-cluster/terraform.tfstate
│   └── clinic-onprem/terraform.tfstate
```

---

## Multi-Cluster Scenarios


### Scenario 1: Single Multi-Tenant Cluster (Most Common)

**Goal:** One cluster for all clients (5-30 clients)

```
clusters/
└── shared-prod/       # One cluster, multiple client namespaces
```

**Workflow:**
```bash
# 1. Provision shared cluster
cd clusters/shared-prod
tofu apply

# 2. Deploy multiple clients to different namespaces
cd ../../..
./scripts/new-client-config.sh client-a client-a.com
./scripts/new-client-config.sh client-b client-b.com
./scripts/new-client-config.sh client-c client-c.com

# Each client gets:
# - client-a-prod namespace
# - client-b-prod namespace
# - client-c-prod namespace
```

**Benefits:**
- Cost-effective (shared infrastructure)
- Easier management (one cluster)
- Efficient resource utilization

### Scenario 2: Regional Clusters

**Goal:** Clusters in different regions for latency/compliance

```
clusters/
├── us-east-prod/      # US clients
├── eu-west-prod/      # EU clients (GDPR)
└── ap-south-prod/     # Asia clients
```

**Workflow:**
```bash
# Provision each cluster
for cluster in us-east-prod eu-west-prod ap-south-prod; do
  cd clusters/$cluster
  tofu apply
  cd ../../..
done

# Deploy clients to appropriate regions
./scripts/new-client-config.sh us-client-a us-client-a.com
./scripts/new-client-config.sh eu-client-b eu-client-b.com
```

### Scenario 3: Environment Separation

**Goal:** Separate clusters for production and staging

```
clusters/
├── production/        # Production workloads
└── staging/          # Testing and staging
```

**Workflow:**
```bash
# Provision both clusters
cd clusters/production
tofu apply

cd ../staging
tofu apply

# Deploy to staging first, then production
./scripts/new-client-config.sh client-a-staging client-a.com
# Test thoroughly
./scripts/new-client-config.sh client-a-prod client-a.com
```

### Scenario 4: Dedicated Enterprise Clusters

**Goal:** Large clients get dedicated clusters

```
clusters/
├── shared-prod/              # Small clients (multi-tenant)
└── enterprise-client-a/      # Large client (dedicated)
```

**When to use:**
- Client requires dedicated infrastructure
- Compliance/regulatory requirements
- Very high resource usage
- Custom security requirements

### Managing Multiple Clusters

**Use kubeconfig contexts:**

```bash
# Set up all clusters
tofu -chdir=clusters/us-prod output -raw kubeconfig > ~/.kube/us-prod
tofu -chdir=clusters/eu-prod output -raw kubeconfig > ~/.kube/eu-prod

# Merge into single kubeconfig
export KUBECONFIG=~/.kube/us-prod:~/.kube/eu-prod
kubectl config view --flatten > ~/.kube/config

# Switch between clusters
kubectl config get-contexts
kubectl config use-context us-prod
kubectl config use-context eu-prod

# Or use kubectx tool
brew install kubectx
kubectx us-prod
kubectx eu-prod
```

---

## Troubleshooting

### Issue 1: Authentication Failure

**Symptom:**
```
Error: error configuring Terraform AWS Provider: no valid credential sources
```

**Solution:**
```bash
# Verify credentials
aws sts get-caller-identity    # AWS
az account show                # Azure
gcloud config list             # GCP

# Re-authenticate if needed
aws configure
az login
gcloud auth application-default login
```

### Issue 2: Insufficient Permissions

**Symptom:**
```
Error: creating EKS Cluster: AccessDeniedException
```

**Solution:**
Check IAM permissions. Required AWS permissions:
- `eks:*`
- `ec2:*`
- `iam:CreateRole`, `iam:AttachRolePolicy`
- `logs:CreateLogGroup`

### Issue 3: Quota Limits

**Symptom:**
```
Error: creating EKS Node Group: LimitExceededException
```

**Solution:**
```bash
# Check AWS service quotas
aws service-quotas get-service-quota \
  --service-code eks \
  --quota-code L-1194D53C  # Max nodes per node group

# Request quota increase via AWS Console
```

### Issue 4: State Lock

**Symptom:**
```
Error: acquiring the state lock
Lock Info:
  ID:        abc123...
```

**Solution:**
```bash
# If you're sure no one else is running tofu:
tofu force-unlock abc123

# Or check who has the lock in DynamoDB
aws dynamodb get-item \
  --table-name terraform-locks \
  --key '{"LockID": {"S": "your-state-path"}}'
```

### Issue 5: Cluster Creation Timeout

**Symptom:**
```
Error: timeout while waiting for cluster to become active
```

**Solution:**
- Check AWS/Azure/GCP console for error messages
- Verify VPC/subnet configuration
- Check IAM role trust relationships
- Increase timeout in provider config:

```hcl
resource "aws_eks_cluster" "main" {
  # ...
  
  timeouts {
    create = "30m"  # Increase from default 15m
    delete = "30m"
  }
}
```

### Issue 6: Node Group Not Joining

**Symptom:**
Cluster created but no nodes visible in `kubectl get nodes`

**Solution:**
```bash
# Check node group status in cloud console
aws eks describe-nodegroup --cluster-name my-cluster --nodegroup-name general

# Check node IAM role has required policies
# - AmazonEKSWorkerNodePolicy
# - AmazonEKS_CNI_Policy
# - AmazonEC2ContainerRegistryReadOnly

# Check security groups allow communication
```

### Issue 7: kubectl Can't Connect

**Symptom:**
```
Unable to connect to the server: dial tcp: lookup xyz.eks.amazonaws.com: no such host
```

**Solution:**
```bash
# Verify kubeconfig
cat ~/.kube/config

# Re-generate kubeconfig
cd clusters/my-cluster
tofu output -raw kubeconfig > ~/.kube/my-cluster
export KUBECONFIG=~/.kube/my-cluster

# For AWS EKS, use AWS CLI
aws eks update-kubeconfig --name my-cluster --region us-east-1
```

### Issue 8: Module Not Found

**Symptom:**
```
Error: Module not installed
```

**Solution:**
```bash
# Re-initialize to download modules
tofu init

# Or force update
tofu init -upgrade
```

### Issue 9: Provider Version Conflict

**Symptom:**
```
Error: Incompatible provider version
```

**Solution:**
```bash
# Remove lock file and re-initialize
rm .terraform.lock.hcl
tofu init
```

### Getting Help

If issues persist:

1. **Check module README**: `terraform/modules/{module}/README.md`
2. **Review module code**: `terraform/modules/{module}/main.tf`
3. **Enable debug logging**:
   ```bash
   export TF_LOG=DEBUG
   tofu apply
   ```
4. **Check cloud provider logs**: CloudWatch, Azure Monitor, Cloud Logging
5. **OpenTofu community**: https://discuss.opentofu.org/

---

## Post-Provisioning Checklist

After successfully provisioning a cluster:

### Immediate Tasks

- [ ] **Verify cluster access**
  ```bash
  kubectl get nodes
  kubectl get pods -A
  ```

- [ ] **Test core functionality**
  ```bash
  # Test DNS
  kubectl run test --image=busybox --rm -it -- nslookup kubernetes.default
  
  # Test storage
  kubectl apply -f - <<EOF
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: test-pvc
  spec:
    accessModes: [ReadWriteOnce]
    resources:
      requests:
        storage: 1Gi
  EOF
  ```

- [ ] **Document cluster details**
  - Cluster name
  - Region
  - Endpoint URL
  - OIDC provider ARN (for IRSA/Workload Identity)
  - Node sizes and counts

### Deploy Monobase Applications

- [ ] **Install core infrastructure**
  ```bash
  # Install Envoy Gateway
  helm install eg oci://docker.io/envoyproxy/gateway-helm \
    --version v1.0.0 -n envoy-gateway-system --create-namespace
  
  # Install External Secrets Operator
  helm install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace
  
  # Install Velero (backups)
  # See ../charts/velero/
  ```

- [ ] **Create first client namespace**
  ```bash
  ./scripts/new-client-config.sh client-a client-a.com
  ```

- [ ] **Deploy Monobase API, API Worker, Monobase**
  ```bash
  helm install api charts/api -f config/client-a/values-production.yaml
  # etc.
  ```

### Monitoring & Observability

- [ ] **Verify metrics collection**
  - CloudWatch (AWS)
  - Azure Monitor (Azure)
  - Cloud Monitoring (GCP)

- [ ] **Set up alerts**
  - Node health
  - Pod failures
  - Resource utilization

### Security Hardening

- [ ] **Review security groups / firewall rules**
- [ ] **Enable audit logging**
- [ ] **Configure network policies**
- [ ] **Set up resource quotas per namespace**
- [ ] **Review IAM/RBAC permissions**


### Cost Optimization

- [ ] **Enable autoscaling**
  - Cluster Autoscaler (installed by modules)
  - Horizontal Pod Autoscaler
  
- [ ] **Review instance types**
  - Use latest generation (m6i vs m5)
  - Consider Spot instances for dev/staging

- [ ] **Configure resource requests/limits**
  - Right-size applications
  - Avoid over-provisioning

---

## Command Reference

### Common OpenTofu Commands

```bash
# Initialize (download providers, modules)
tofu init

# Format code
tofu fmt

# Validate syntax
tofu validate

# Plan changes (dry-run)
tofu plan

# Apply changes
tofu apply

# Show current state
tofu show

# List resources
tofu state list

# Get output value
tofu output cluster_endpoint
tofu output -raw kubeconfig > ~/.kube/config

# Destroy cluster (⚠️ DANGEROUS)
tofu destroy

# Import existing resource
tofu import aws_eks_cluster.main my-cluster-name
```

### Common kubectl Commands

```bash
# View cluster info
kubectl cluster-info
kubectl get nodes
kubectl get namespaces

# Create namespace
kubectl create namespace client-a-prod

# View resources
kubectl get pods -A
kubectl get svc -A
kubectl get pvc -A

# Describe resource
kubectl describe node <node-name>
kubectl describe pod <pod-name> -n <namespace>

# View logs
kubectl logs <pod-name> -n <namespace>

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Port forward
kubectl port-forward svc/<service-name> 8080:80 -n <namespace>

# Apply manifest
kubectl apply -f manifest.yaml

# Delete resource
kubectl delete pod <pod-name> -n <namespace>
```

---

## Additional Resources

- **Module Development**: [MODULE-DEVELOPMENT.md](../development/MODULE-DEVELOPMENT.md)
- **Cluster Sizing**: [CLUSTER-SIZING.md](../operations/CLUSTER-SIZING.md)
- **Architecture**: [ARCHITECTURE.md](../architecture/ARCHITECTURE.md)
- **Main README**: [../README.md](../README.md)

---

**Ready to provision your first cluster? Start with Workflow 1 (Quick Start) above!**
