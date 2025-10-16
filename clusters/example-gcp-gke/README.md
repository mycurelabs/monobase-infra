# Example GCP GKE Cluster

Reference configuration for Google Kubernetes Engine.

## Quick Start

```bash
# 1. Copy this directory
cp -r clusters/example-gcp-gke clusters/myclient-gke

# 2. Customize
cd clusters/myclient-gke
vim terraform.tfvars

# 3. Provision
./scripts/provision.sh --cluster myclient-gke
```

## Module Documentation

See [terraform/modules/gcp-gke/README.md](../../terraform/modules/gcp-gke/README.md) for:
- Full configuration options
- GCP-specific setup
- Workload Identity
- Cost optimization

## Prerequisites

- GCP project
- gcloud CLI configured
- Terraform >= 1.6
