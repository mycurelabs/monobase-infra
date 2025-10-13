# AWS EKS Module

Production-ready EKS cluster for multi-tenant LFH Infrastructure deployments.

## Features

- ✅ **Multi-tenant ready** - Sized for multiple clients (3-20 nodes autoscaling)
- ✅ **High availability** - 3 AZs, multi-node groups
- ✅ **IRSA enabled** - IAM roles for External Secrets, Velero, cert-manager
- ✅ **EBS CSI driver** - Storage provisioning
- ✅ **Cluster autoscaler** - Automatic node scaling
- ✅ **Encryption** - Secrets encrypted with KMS
- ✅ **Audit logging** - CloudWatch logs (90-day retention)
- ✅ **HIPAA-compliant** - All security controls enabled
- ✅ **VPC** - 3 AZs with public/private subnets
- ✅ **Cost-optimized** - Appropriate instance types, single NAT option

## Usage

```hcl
module "eks_cluster" {
  source = "../../modules/aws-eks"
  
  cluster_name       = "lfh-prod"
  region             = "us-east-1"
  kubernetes_version = "1.28"
  
  # VPC configuration
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  # Node groups (multi-tenant sizing)
  node_groups = {
    general = {
      instance_types = ["m6i.2xlarge"]  # 8 vCPU, 32GB RAM
      desired_size   = 5   # ~5-10 clients
      max_size       = 20  # ~20-30 clients
      min_size       = 3   # HA minimum
      disk_size      = 100
    }
  }
  
  # Add-ons (required for LFH)
  enable_ebs_csi_driver     = true  # Storage
  enable_cluster_autoscaler = true  # Auto-scaling
  enable_irsa               = true  # External Secrets, Velero
  
  tags = {
    Environment = "production"
    ManagedBy   = "opentofu"
  }
}
```

## Outputs

### Cluster Outputs
- `cluster_name` - EKS cluster name
- `cluster_endpoint` - API server endpoint
- `cluster_arn` - Cluster ARN
- `kubeconfig` - Complete kubectl configuration

### IRSA Role ARNs (for LFH components)
- `external_secrets_role_arn` - For External Secrets Operator
- `velero_role_arn` - For Velero backups
- `cert_manager_role_arn` - For cert-manager Route53 DNS-01
- `cluster_autoscaler_role_arn` - For cluster autoscaler

### Network Outputs
- `vpc_id` - VPC ID
- `private_subnet_ids` - Private subnet IDs
- `public_subnet_ids` - Public subnet IDs

## Configuration

### Multi-Tenant Sizing

**Small (5-10 clients):**
```hcl
node_groups = {
  general = {
    instance_types = ["m6i.xlarge"]   # 4 vCPU, 16GB
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
    max_size       = 20
    min_size       = 3
  }
}
```

**Large (20+ clients):**
```hcl
node_groups = {
  general = {
    instance_types = ["m6i.4xlarge"]  # 16 vCPU, 64GB
    desired_size   = 10
    max_size       = 30
    min_size       = 5
  }
}
```

### Private Cluster

```hcl
enable_private_endpoint = true
enable_public_endpoint  = false  # Requires bastion/VPN
```

### Cost Optimization

```hcl
# Use spot instances for non-critical workloads
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]
    capacity_type  = "ON_DEMAND"  # Or "SPOT" for 70% savings
    # ...
  }
}

# Or use single NAT gateway (not HA)
# Edit vpc.tf: single_nat_gateway = true
```

## After Provisioning

### Get kubeconfig

```bash
# Via Terraform output
tofu output -raw kubeconfig > ~/.kube/lfh-prod
export KUBECONFIG=~/.kube/lfh-prod

# Or via AWS CLI
aws eks update-kubeconfig --region us-east-1 --name lfh-prod

# Verify
kubectl get nodes
```

### Configure kubectl for IRSA

Service accounts will automatically use IRSA when annotated:

```yaml
# External Secrets Operator
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: external-secrets-system
  annotations:
    eks.amazonaws.com/role-arn: <external_secrets_role_arn>
```

### Deploy LFH Application Stack

```bash
# Use existing LFH workflow
cd ../../..
./scripts/new-client-config.sh client-a client-a.com

# Deploy via ArgoCD or Helm
helm install hapihub charts/hapihub -f config/client-a/values-production.yaml
```

## Requirements

- AWS account with appropriate permissions
- OpenTofu >= 1.6
- AWS CLI configured

## Resources Created

- EKS cluster (control plane)
- VPC with 3 AZs
- 6 subnets (3 public, 3 private)
- 3 NAT Gateways (HA)
- Internet Gateway
- Route tables
- Security groups
- IAM roles (cluster, nodes, IRSA)
- KMS key (encryption)
- CloudWatch log group (audit logs)
- EKS add-ons (EBS CSI, VPC CNI, CoreDNS, kube-proxy)

## Security

- ✅ Secrets encrypted with KMS
- ✅ Audit logs enabled (90-day retention)
- ✅ Private subnets for nodes
- ✅ Security groups (least privilege)
- ✅ IRSA for pod-level permissions
- ✅ IMDSv2 required
- ✅ VPC flow logs enabled

## Cost Estimate

**Medium cluster (5 nodes, m6i.2xlarge):**
- EKS control plane: ~$73/month
- EC2 nodes: ~$700/month (5 × $140)
- NAT Gateways: ~$100/month (3 × $33)
- EBS volumes: ~$50/month
- **Total: ~$920/month** for ~10-15 clients

## Troubleshooting

See module source code for detailed implementation.
