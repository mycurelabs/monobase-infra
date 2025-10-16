# Example DigitalOcean DOKS Cluster

Reference configuration for DigitalOcean Kubernetes.

## Quick Start

```bash
# 1. Copy to your cluster name
cp -r clusters/example-do-doks clusters/myclient-doks

# 2. Customize configuration
cd clusters/myclient-doks
vim terraform.tfvars

# 3. Provision
./scripts/provision.sh --cluster myclient-doks
```

## Configuration

See `terraform.tfvars` for all options. Key settings:

- **deployment_profile**: small/medium/large presets
- **region**: sgp1 (Singapore), nyc1 (New York), etc.
- **ha_control_plane**: Enable for production

## Module Documentation

See [terraform/modules/do-doks/README.md](../../terraform/modules/do-doks/README.md)

## Prerequisites

- DigitalOcean account
- DO API token: `export DIGITALOCEAN_TOKEN=your-token`
- Terraform >= 1.6
