# Default Cluster - Reference Configuration

REFERENCE cluster configuration (like config/example.com for applications).

## For New Cluster

```bash
# Use bootstrap script
./scripts/new-cluster-config.sh myclient-cluster us-east-1

# Or copy manually
cp -r tofu/clusters/default-cluster tofu/clusters/myclient-cluster
cd tofu/clusters/myclient-cluster
```

## Customize

```bash
vim terraform.tfvars

# Key settings:
# - cluster_name: "monobase-myclient-prod"
# - region: "us-east-1"
# - node_groups.general.instance_types: ["m6i.2xlarge"]
# - node_groups.general.desired_size: 5
# - node_groups.general.max_size: 20
```

## Configure Backend

```bash
cp backend.tf.example backend.tf
vim backend.tf
# Set your S3 bucket name
```

## Provision

```bash
tofu init
tofu plan
tofu apply
```

## Get Kubeconfig

```bash
tofu output -raw kubeconfig > ~/.kube/myclient-cluster
export KUBECONFIG=~/.kube/myclient-cluster
kubectl get nodes
```

## Deploy Applications

```bash
# Use Monobase application workflow
cd ../../..
./scripts/new-client-config.sh client-a client-a.com
# Deploy via Helm/ArgoCD
```

## Multi-Tenant

This cluster is sized for MULTIPLE clients:
- Each client gets their own namespace
- Shared infrastructure
- NetworkPolicies for isolation
- Autoscales from 3-20 nodes as clients grow
