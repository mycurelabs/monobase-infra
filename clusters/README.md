# Cluster Configurations

This directory contains Terraform configurations for provisioning Kubernetes clusters across multiple cloud providers.

## Available Examples

Each example provides a complete, ready-to-use cluster configuration:

| Example | Provider | Use Case |
|---------|----------|----------|
| [example-aws-eks](./example-aws-eks/) | AWS | Production EKS clusters |
| [example-azure-aks](./example-azure-aks/) | Azure | Production AKS clusters |
| [example-gcp-gke](./example-gcp-gke/) | GCP | Production GKE clusters |
| [example-do-doks](./example-do-doks/) | DigitalOcean | Cost-effective DOKS clusters |
| [example-k3d](./example-k3d/) | Local (Docker) | Local development/testing |
| [example-k3s](./example-k3s/) | On-Premises | Bare-metal/VM clusters |

## Quick Start

### 1. Copy an Example

```bash
# Choose your provider
cp -r clusters/example-aws-eks clusters/myclient-eks
# OR
cp -r clusters/example-do-doks clusters/myclient-doks
# OR
cp -r clusters/example-k3d clusters/k3d-local
```

### 2. Customize Configuration

```bash
cd clusters/myclient-eks
vim terraform.tfvars  # Edit cluster name, region, size, etc.
```

### 3. Provision Cluster

```bash
./scripts/provision.sh --cluster myclient-eks
```

The script will:
- Initialize Terraform
- Create the cluster
- Save kubeconfig to `~/.kube/myclient-eks`
- Test connectivity

### 4. Bootstrap GitOps

```bash
# Install ArgoCD and enable auto-discovery
./scripts/bootstrap.sh
```

## Configuration Patterns

### Deployment Profiles

Most modules support size presets:

```hcl
deployment_profile = "small"   # 1-5 clients, 3 nodes
deployment_profile = "medium"  # 5-15 clients, 5 nodes
deployment_profile = "large"   # 15+ clients, 5+ larger nodes
```

### Custom Node Groups

For fine-grained control:

```hcl
node_groups = {
  general = {
    instance_types = ["m6i.xlarge"]  # Or Azure/GCP equivalent
    desired_size   = 3
    min_size       = 3
    max_size       = 10
    disk_size      = 100
  }
}
```

## Module Documentation

Each Terraform module has detailed documentation:

- [aws-eks](../terraform/modules/aws-eks/README.md) - AWS EKS configuration
- [azure-aks](../terraform/modules/azure-aks/README.md) - Azure AKS configuration
- [gcp-gke](../terraform/modules/gcp-gke/README.md) - GCP GKE configuration
- [do-doks](../terraform/modules/do-doks/README.md) - DigitalOcean DOKS configuration
- [local-k3d](../terraform/modules/local-k3d/README.md) - k3d local development
- [on-prem-k3s](../terraform/modules/on-prem-k3s/README.md) - On-premises K3s

## Provider Authentication

### AWS

```bash
aws configure
# OR
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
```

### Azure

```bash
az login
```

### GCP

```bash
gcloud auth application-default login
```

### DigitalOcean

```bash
export DIGITALOCEAN_TOKEN=your-token
```

## Next Steps

After provisioning your cluster:

1. **Bootstrap GitOps:**
   ```bash
   ./scripts/bootstrap.sh
   ```

2. **Create deployment configuration:**
   ```bash
   mkdir deployments/myclient-prod
   cp deployments/templates/production-base.yaml deployments/myclient-prod/values.yaml
   vim deployments/myclient-prod/values.yaml
   ```

3. **Deploy via Git:**
   ```bash
   git add deployments/myclient-prod/
   git commit -m "Add myclient-prod"
   git push  # ArgoCD auto-deploys!
   ```

## Cleanup

To destroy a cluster, manually run terraform destroy in the cluster directory:

```bash
cd clusters/myclient-eks
terraform destroy
```

**⚠️ Warning:** This destroys the cluster and all resources. Ensure you have backups!

## Related Documentation

- [Cluster Provisioning Guide](../docs/getting-started/CLUSTER-PROVISIONING.md)
- [Infrastructure Requirements](../docs/getting-started/INFRASTRUCTURE-REQUIREMENTS.md)
- [GitOps Workflow](../docs/architecture/GITOPS-ARGOCD.md)
