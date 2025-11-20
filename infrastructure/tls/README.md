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

### View ClusterIssuers

```bash
# List all ClusterIssuers
kubectl get clusterissuer

# Describe specific issuer
kubectl describe clusterissuer letsencrypt-prod
```

## Secrets

This directory contains ExternalSecret definitions that sync secrets from GCP Secret Manager to Kubernetes.

## Note on DNS Providers

Currently, only HTTP-01 challenge is supported for certificate issuance. DNS-01 challenges (including Cloudflare) have been removed from this infrastructure.

For HTTP-01 configuration examples, see `charts/cert-manager-issuers/README.md`.

## See Also

- [Certificate Management Operations Guide](../../docs/operations/CERTIFICATE-MANAGEMENT.md)
- [Multi-Domain Gateway Architecture](../../docs/architecture/MULTI-DOMAIN-GATEWAY.md)
- [cert-manager-issuers Chart](../../charts/cert-manager-issuers/README.md)
