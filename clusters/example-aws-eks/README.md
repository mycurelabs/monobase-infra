# Example AWS EKS Cluster

This is a reference configuration for provisioning an EKS cluster on AWS.

## Prerequisites

- AWS account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Terraform >= 1.6

## Quick Start

```bash
# 1. Copy this directory
cp -r clusters/example-aws-eks clusters/myclient-eks

# 2. Edit configuration
cd clusters/myclient-eks
vim terraform.tfvars  # Customize cluster_name, region, etc.

# 3. Provision (recommended - uses unified script)
./scripts/provision.sh --cluster myclient-eks

# OR provision manually:
terraform init
terraform plan
terraform apply

# 4. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name myclient-eks
```

## Configuration Options

### Deployment Profiles

Use pre-configured size profiles:

- **small** (default): 3 nodes, m6i.xlarge (4 vCPU, 16GB RAM)
- **medium**: 5 nodes, m6i.xlarge
- **large**: 5+ nodes, m6i.2xlarge (8 vCPU, 32GB RAM)

```hcl
deployment_profile = "small"
```

### Custom Node Groups

For more control, define custom node groups:

```hcl
node_groups = {
  general = {
    instance_types = ["m6i.xlarge"]
    desired_size   = 3
    min_size       = 3
    max_size       = 10
    disk_size      = 100
    labels         = { role = "general" }
    taints         = []
  }
}
```

### Security

Restrict API access in production:

```hcl
api_access_cidrs = ["203.0.113.0/24"]  # Your office/VPN CIDR
```

Scope IAM permissions:

```hcl
velero_backup_bucket = "myclient-eks-velero-backups"
route53_zone_arns    = ["arn:aws:route53:::hostedzone/Z1234567890ABC"]
```

## Post-Provisioning

After the cluster is created:

1. **Bootstrap GitOps:**
   ```bash
   ./scripts/bootstrap.sh
   ```

2. **Create deployment config:**
   ```bash
   mkdir deployments/myclient-prod
   cp deployments/templates/production-base.yaml deployments/myclient-prod/values.yaml
   vim deployments/myclient-prod/values.yaml  # Edit domain, namespace, etc.
   ```

3. **Deploy via GitOps:**
   ```bash
   git add deployments/myclient-prod/
   git commit -m "Add myclient-prod deployment"
   git push
   ```

## Outputs

After provisioning, Terraform outputs:

- `cluster_endpoint` - EKS API endpoint
- `kubeconfig_command` - Command to configure kubectl
- `oidc_provider_arn` - For IAM Roles for Service Accounts (IRSA)
- `vpc_id` - VPC created for the cluster

## Cost Optimization

- Use `deployment_profile = "small"` for testing
- Enable cluster autoscaler to scale down during off-hours
- Use Spot instances for non-production workloads (requires custom node_groups)

## Cleanup

```bash
# Destroy cluster and all resources
terraform destroy
```

**⚠️ Warning:** This will delete the cluster and all resources. Ensure you have backups!

## Next Steps

- [Bootstrap GitOps](../../docs/getting-started/CLUSTER-PROVISIONING.md)
- [Deploy Applications](../../docs/getting-started/DEPLOYMENT.md)
- [Configure Backups](../../docs/operations/BACKUP_DR.md)
