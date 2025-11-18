# Static IP Prerequisites for Envoy Gateway

## Overview

This document provides instructions for creating static IP addresses for the Envoy Gateway LoadBalancer across all supported Kubernetes providers. A static IP ensures that your gateway's IP address doesn't change, which is essential for:

- Stable DNS records
- SSL/TLS certificate validation
- Third-party integrations
- Firewall whitelisting

## Supported Cloud Providers

- **Azure AKS** - Azure Kubernetes Service
- **AWS EKS** - Amazon Elastic Kubernetes Service
- **GCP GKE** - Google Kubernetes Engine
- **DigitalOcean DOKS** - DigitalOcean Kubernetes

## Quick Start

1. Choose your cloud provider from the list below
2. Follow the provider-specific guide
3. Save the required configuration values
4. Provide these values to your DevOps team for deployment configuration

## Provider-Specific Guides

### Azure AKS (Current Environment)

See: [Azure Static IP Guide](./static-ip-azure.md)

**Quick Summary:**
- Create Static Public IP in node resource group
- Requires: Public IP Name and Node Resource Group
- Option to preserve existing IP or create new one

### AWS EKS

See: [AWS Static IP Guide](./static-ip-aws.md)

**Quick Summary:**
- Allocate Elastic IPs (one per subnet/AZ)
- Requires: EIP Allocation IDs (comma-separated)
- Uses Network Load Balancer (NLB)

### Google Cloud (GKE)

See: [GCP Static IP Guide](./static-ip-gcp.md)

**Quick Summary:**
- Reserve Regional Static IP
- Requires: IP Address or Name
- Must match cluster region

### DigitalOcean (DOKS)

See: [DigitalOcean Static IP Guide](./static-ip-digitalocean.md)

**Quick Summary:**
- Option 1: Use LoadBalancer Name (simple)
- Option 2: Use FLIPOP Operator with Reserved IP (recommended)

## Configuration Values Needed

After completing the prerequisite steps for your cloud provider, you'll need to provide the following information to your DevOps team:

### For Azure AKS:
```yaml
cloudProvider: azure
azure:
  publicIpName: "your-gateway-ip-name"
  resourceGroup: "MC_your-rg_your-cluster_region"
```

### For AWS EKS:
```yaml
cloudProvider: aws
aws:
  eipAllocations: "eipalloc-xxx,eipalloc-yyy,eipalloc-zzz"
```

### For GCP GKE:
```yaml
cloudProvider: gcp
gcp:
  staticIpAddress: "35.123.456.789"
```

### For DigitalOcean DOKS:
```yaml
cloudProvider: digitalocean
digitalocean:
  loadBalancerName: "your-gateway-lb"
  # OR with FLIPOP:
  # loadBalancerId: "lb-xxx-yyy-zzz"
```

## Important Notes

1. **Costs**: Static IPs typically incur small hourly charges when reserved but not in use
2. **Regions**: Static IPs must be in the same region as your Kubernetes cluster
3. **High Availability**: AWS requires multiple EIPs for HA (one per availability zone)
4. **Permissions**: You'll need appropriate cloud provider permissions to create/manage IPs
5. **DNS**: After static IP is configured, update your DNS records to point to the new IP

## Support

For provider-specific questions or issues:
- See the detailed guides linked above
- Consult your cloud provider's documentation
- Contact your DevOps team for assistance

## Next Steps

1. Complete the prerequisite steps for your cloud provider
2. Save the configuration values
3. Provide values to DevOps team
4. DevOps team will update infrastructure configuration
5. ArgoCD will automatically deploy the changes
6. Update DNS records to point to the static IP
7. Verify connectivity and SSL/TLS certificates
