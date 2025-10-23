# TLS Infrastructure

This directory contains TLS-related infrastructure resources.

## ClusterIssuers (Managed via ArgoCD)

ClusterIssuers are now managed via the `cert-manager-issuers` Helm chart deployed through ArgoCD.

**Configuration:** `argocd/infrastructure/values.yaml` → `certManagerIssuers`  
**Chart:** `charts/cert-manager-issuers/`  
**ArgoCD App:** `argocd/infrastructure/templates/cert-manager-issuers.yaml`

### Available ClusterIssuers

| Name | Type | Use Case |
|------|------|----------|
| `letsencrypt-prod` | HTTP-01 | Default for client domains (single domain) |
| `letsencrypt-staging` | HTTP-01 | Testing for client domains |
| `letsencrypt-mycure-cloudflare-prod` | DNS-01 | MyCure platform wildcard certificates |
| `letsencrypt-mycure-cloudflare-staging` | DNS-01 | Testing wildcard certificates |

### View ClusterIssuers

```bash
# List all ClusterIssuers
kubectl get clusterissuer

# Describe specific issuer
kubectl describe clusterissuer letsencrypt-prod
```

## Secrets

This directory contains ExternalSecret definitions that sync secrets from GCP Secret Manager to Kubernetes.

### MyCure Cloudflare API Token

**File:** `cloudflare-token-externalsecret.yaml`  
**Secret Name:** `mycure-cloudflare-api-token`  
**Namespace:** `cert-manager`  
**Used By:** `letsencrypt-mycure-cloudflare-{prod,staging}` ClusterIssuers

```bash
# Check if secret is synced
kubectl get externalsecret mycure-cloudflare-api-token -n cert-manager
kubectl get secret mycure-cloudflare-api-token -n cert-manager
```

## Adding New DNS Providers

To add support for additional DNS providers:

1. **Create provider-specific secret** (if needed) via ExternalSecret
2. **Add issuer to ArgoCD values**:
   ```yaml
   # argocd/infrastructure/values.yaml
   certManagerIssuers:
     issuers:
       - name: letsencrypt-client1-route53-prod
         email: "admin@example.com"
         server: production
         provider: route53
         route53:
           region: us-east-1
           role: arn:aws:iam::123456789012:role/cert-manager
   ```

3. **Supported providers:** http01, cloudflare, route53, azuredns, clouddns, digitalocean

See `charts/cert-manager-issuers/README.md` for detailed configuration examples.

## See Also

- [Certificate Management Operations Guide](../../docs/operations/CERTIFICATE-MANAGEMENT.md)
- [Multi-Domain Gateway Architecture](../../docs/architecture/MULTI-DOMAIN-GATEWAY.md)
- [cert-manager-issuers Chart](../../charts/cert-manager-issuers/README.md)
