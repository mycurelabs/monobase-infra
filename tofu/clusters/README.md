# Cluster Configurations

This directory contains cluster provisioning configurations.

## Structure

```
clusters/
├── default-cluster/    # REFERENCE config (like config/example.com)
└── your-cluster/       # Your actual cluster (created by copying default)
```

## Quick Start

### Create New Cluster Config

```bash
# Use the bootstrap script
./scripts/new-cluster-config.sh myclient-cluster us-east-1

# Or copy manually
cp -r tofu/clusters/default-cluster tofu/clusters/myclient-cluster
cd tofu/clusters/myclient-cluster
```

### Customize Configuration

```bash
# Edit cluster parameters
vim terraform.tfvars

# Key settings:
# - cluster_name: "lfh-myclient-prod"
# - region: "us-east-1"
# - node_instance_type: "m6i.2xlarge"
# - node_count_min: 3
# - node_count_max: 20

# Configure state backend
cp backend.tf.example backend.tf
vim backend.tf  # Set your S3 bucket name
```

### Provision Cluster

```bash
# Initialize
tofu init

# Plan (review changes)
tofu plan

# Apply (create cluster)
tofu apply

# Get kubeconfig
tofu output -raw kubeconfig > ~/.kube/myclient-cluster
export KUBECONFIG=~/.kube/myclient-cluster
kubectl get nodes
```

## Multi-Tenant Architecture

**One cluster hosts multiple clients:**

Each client gets:
- Separate namespace (client-a-prod, client-b-prod)
- Isolated via NetworkPolicies
- Independent ArgoCD applications
- Shared infrastructure (Gateway, storage)

**Cluster sizing:**
- Start: 3-5 nodes
- Autoscale: Up to 20 nodes
- Per client: ~1-2 nodes worth of resources

## Reference Configuration

See `default-cluster/` for complete reference with:
- All parameters documented
- Sensible defaults
- Multi-tenant sizing
- Cost-optimized settings
- HIPAA-compliant configuration

## .gitignore

Only `default-cluster/` is committed to base template.
Actual cluster configs go in client forks.

```
tofu/clusters/*/           # Ignored
!tofu/clusters/default-cluster/  # Committed
```
