# cert-manager-issuers

Helm chart for managing multiple cert-manager ClusterIssuers with support for various DNS providers and HTTP-01 challenges.

## Overview

This chart enables centralized management of ClusterIssuers for automatic TLS certificate provisioning via Let's Encrypt ACME protocol. It supports:

- **HTTP-01 Challenge**: No DNS provider needed, requires port 80 access
- **DNS-01 Challenge**: Supports Cloudflare, AWS Route53, Azure DNS, Google Cloud DNS, DigitalOcean

## Supported Providers

| Provider | Challenge Type | Use Case |
|----------|---------------|----------|
| `http01` | HTTP-01 | Default, client-owned domains with A record only |
| `cloudflare` | DNS-01 | Cloudflare-managed domains, wildcard support |
| `route53` | DNS-01 | AWS Route53 domains, wildcard support |
| `azuredns` | DNS-01 | Azure DNS domains, wildcard support |
| `clouddns` | DNS-01 | Google Cloud DNS domains, wildcard support |
| `digitalocean` | DNS-01 | DigitalOcean DNS domains, wildcard support |

## Installation

This chart is deployed via ArgoCD as part of the infrastructure stack.

```bash
# Standalone installation (for testing)
helm install cert-manager-issuers ./charts/cert-manager-issuers \
  --namespace cert-manager \
  -f values.yaml
```

## Configuration

### HTTP-01 Issuer (Default)

HTTP-01 is the recommended default for client-owned domains where only DNS A records can be created.

```yaml
issuers:
  - name: letsencrypt-prod
    email: "admin@example.com"
    server: production  # or staging
    provider: http01
```

**Limitations:**
- Cannot issue wildcard certificates
- Requires port 80 accessible from internet
- Domain must resolve to Gateway LoadBalancer IP

### Cloudflare DNS-01 Issuer

For Cloudflare-managed domains with wildcard certificate support.

```yaml
issuers:
  - name: letsencrypt-mycure-cloudflare-prod
    email: "admin@example.com"
    server: production
    provider: cloudflare
    cloudflare:
      dnsZones:
        - "mycureapp.com"
      apiTokenSecretRef:
        name: mycure-cloudflare-api-token
        key: api-token
```

**Secret Format:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mycure-cloudflare-api-token
  namespace: cert-manager
stringData:
  api-token: "your-cloudflare-api-token"
```

### AWS Route53 DNS-01 Issuer

For Route53-managed domains with IAM role authentication.

```yaml
issuers:
  - name: letsencrypt-client1-route53-prod
    email: "admin@example.com"
    server: production
    provider: route53
    route53:
      region: us-east-1
      hostedZoneID: Z1234567890ABC  # Optional
      role: arn:aws:iam::123456789012:role/cert-manager  # For IRSA
```

### Azure DNS Issuer

For Azure DNS with Managed Identity authentication.

```yaml
issuers:
  - name: letsencrypt-client2-azure-prod
    email: "admin@example.com"
    server: production
    provider: azuredns
    azuredns:
      subscriptionID: "12345678-1234-1234-1234-123456789012"
      resourceGroupName: dns-rg
      hostedZoneName: client2.com
      managedIdentityClientID: "87654321-4321-4321-4321-210987654321"
```

### Google Cloud DNS Issuer

For Cloud DNS with service account authentication.

```yaml
issuers:
  - name: letsencrypt-client3-clouddns-prod
    email: "admin@example.com"
    server: production
    provider: clouddns
    clouddns:
      project: my-gcp-project
      serviceAccountSecretRef:
        name: clouddns-service-account
        key: key.json
```

### DigitalOcean DNS Issuer

For DigitalOcean DNS.

```yaml
issuers:
  - name: letsencrypt-client4-do-prod
    email: "admin@example.com"
    server: production
    provider: digitalocean
    digitalocean:
      apiTokenSecretRef:
        name: digitalocean-api-token
        key: api-token
```

## Parameters

### Global Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `issuers` | Array of ClusterIssuer configurations | `[]` |

### Issuer Parameters

| Parameter | Description | Required |
|-----------|-------------|----------|
| `name` | ClusterIssuer name | Yes |
| `email` | ACME account email | Yes |
| `server` | ACME server (`production`, `staging`, or custom URL) | Yes |
| `provider` | Provider type | Yes |

### Provider-Specific Parameters

See the configuration examples above for required fields per provider.

## Usage in Certificates

Reference the ClusterIssuer in Certificate resources:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-tls
  namespace: gateway-system
spec:
  secretName: example-tls
  issuerRef:
    name: letsencrypt-prod  # HTTP-01
    kind: ClusterIssuer
  dnsNames:
    - example.com
```

For wildcard certificates, use DNS-01 issuer:

```yaml
spec:
  issuerRef:
    name: letsencrypt-mycure-cloudflare-prod
  dnsNames:
    - "*.mycureapp.com"
    - mycureapp.com
```

## Troubleshooting

### Check ClusterIssuer Status

```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

### Check ACME Account Registration

```bash
kubectl get secret letsencrypt-prod-account-key -n cert-manager
```

### Test Certificate Issuance

```bash
# Check certificate status
kubectl get certificate -A
kubectl describe certificate example-tls -n gateway-system

# Check certificate request
kubectl get certificaterequest -A
kubectl describe certificaterequest <name> -n gateway-system
```

## See Also

- [Certificate Management](../../docs/operations/CERTIFICATE-MANAGEMENT.md)
- [Multi-Domain Gateway](../../docs/architecture/MULTI-DOMAIN-GATEWAY.md)
- [cert-manager Documentation](https://cert-manager.io/docs/)
