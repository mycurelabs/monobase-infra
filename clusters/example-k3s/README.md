# Example On-Prem K3s Cluster

Reference configuration for on-premises K3s deployment.

## Quick Start

```bash
# 1. Copy this directory
cp -r clusters/example-k3s clusters/myclient-k3s

# 2. Customize
cd clusters/myclient-k3s
vim terraform.tfvars

# 3. Provision
./scripts/provision.sh --cluster myclient-k3s
```

## Module Documentation

See [terraform/modules/on-prem-k3s/README.md](../../terraform/modules/on-prem-k3s/README.md) for:
- Full configuration options
- SSH access requirements
- Server inventory setup
- High availability

## Prerequisites

- Bare-metal or VM servers
- SSH access
- Terraform >= 1.6
