# Static IP Prerequisites for the Gateway LoadBalancer

## Overview

This document covers creating static IP addresses for the gateway LoadBalancer (NGINX Gateway Fabric) across all supported Kubernetes providers. A static IP ensures that your gateway's IP address doesn't change, which is essential for:

- Stable DNS records
- SSL/TLS certificate validation
- Third-party integrations
- Firewall whitelisting

## Supported Cloud Providers

- **DigitalOcean DOKS** - DigitalOcean Kubernetes (current live cluster)
- **AWS EKS** - Amazon Elastic Kubernetes Service
- **Azure AKS** - Azure Kubernetes Service
- **GCP GKE** - Google Kubernetes Engine

## How Configuration Lands

NGINX Gateway Fabric provisions the LoadBalancer Service for each Gateway. Provider-specific Service annotations are set via the Gateway's `infrastructure.annotations`, which NGF propagates onto the provisioned data-plane Service:

```yaml
# values/infrastructure/main.yaml
nginxGatewayResources:
  gateway:
    name: nginx-shared-gateway
    infrastructure:
      annotations:
        # provider-specific static-IP annotations go here, e.g.
        service.beta.kubernetes.io/do-loadbalancer-name: "production-gateway-lb"
```

Template: `charts/nginx-gateway/templates/gateway.yaml`. ArgoCD syncs the change automatically.

## Quick Start

1. Choose your cloud provider from the list below
2. Follow the provider-specific guide to reserve the IP
3. Add the provider's Service annotations under `infrastructure.annotations` in `values/infrastructure/main.yaml`
4. Let ArgoCD sync, then point DNS at the static IP

## Provider-Specific Guides

### DigitalOcean (DOKS) — current live cluster

See: [DigitalOcean Static IP Guide](./static-ip-digitalocean.md)

**Quick Summary:**

- Option 1: LoadBalancer name annotation (simple, IP survives in-place updates)
- Option 2: FLIPOP operator with a reserved IP (true static IP)

### AWS EKS

See: [AWS Static IP Guide](./static-ip-aws.md)

**Quick Summary:**

- Allocate Elastic IPs (one per subnet/AZ)
- Requires: EIP Allocation IDs (comma-separated)
- Uses Network Load Balancer (NLB)

### Azure AKS

See: [Azure Static IP Guide](./static-ip-azure.md)

**Quick Summary:**

- Create Static Public IP in the node resource group (`MC_*`)
- Requires: Public IP name and node resource group
- Option to preserve an existing IP or create a new one

### Google Cloud (GKE)

See: [GCP Static IP Guide](./static-ip-gcp.md)

**Quick Summary:**

- Reserve a regional static IP
- Requires: IP name (must match cluster region)

## Annotations Per Provider

```yaml
# DigitalOcean
service.beta.kubernetes.io/do-loadbalancer-name: "production-gateway-lb"

# AWS (NLB via AWS Load Balancer Controller)
service.beta.kubernetes.io/aws-load-balancer-type: "external"
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
service.beta.kubernetes.io/aws-load-balancer-eip-allocations: "eipalloc-xxx,eipalloc-yyy,eipalloc-zzz"

# Azure
service.beta.kubernetes.io/azure-pip-name: "production-gateway-ip"
service.beta.kubernetes.io/azure-load-balancer-resource-group: "MC_your-rg_your-cluster_region"

# GCP
networking.gke.io/load-balancer-ip-addresses: "production-gateway-ip"
```

## Important Notes

1. **Costs**: Static IPs typically incur small hourly charges when reserved but not in use
2. **Regions**: Static IPs must be in the same region as your Kubernetes cluster
3. **High Availability**: AWS requires multiple EIPs for HA (one per availability zone)
4. **Permissions**: You'll need appropriate cloud provider permissions to create/manage IPs
5. **DNS**: After the static IP is configured, update your DNS records to point to it
