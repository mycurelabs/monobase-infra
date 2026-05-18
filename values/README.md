# Values Directory

This directory contains all actual configuration values used to deploy infrastructure and applications. Everything outside this directory should be treated as templates or examples.

## Directory Structure

```
values/
├── infrastructure/          # Infrastructure configuration
│   ├── main.yaml           # Main infrastructure config (cert-manager, gateway, etc.)
│   ├── external-dns.yaml   # External DNS configuration
│   └── argocd.yaml         # ArgoCD Helm values
└── deployments/            # Application deployment configurations
    ├── acme-staging.yaml     # Acme staging environment
    └── acme-production.yaml  # Acme production environment
```

## Usage

### Infrastructure Configuration

Infrastructure values are referenced by ArgoCD applications in `argocd/infrastructure/`:

```yaml
# charts/argocd-bootstrap/templates/infrastructure-root.yaml
helm:
  valueFiles:
    - ../../values/infrastructure/main.yaml
```

### Deployment Configuration

Deployment values are automatically discovered by the ApplicationSet in `charts/argocd-bootstrap/templates/applicationset-auto-discover.yaml`.

The ApplicationSet uses a **Git Files Generator** to scan `values/deployments/*.yaml` files:

```yaml
generators:
  - git:
      files:
        - path: "values/deployments/*.yaml"
```

Each YAML file discovered creates a corresponding ArgoCD Application.

## Adding New Deployments

To add a new client deployment:

1. Create a new values file: `values/deployments/{client}-{env}.yaml`
2. Copy from existing deployment or example
3. Customize for your client
4. Commit and push - ArgoCD will auto-discover

Example:
```bash
cp values/deployments/acme-staging.yaml values/deployments/newclient-staging.yaml
# Edit values/deployments/newclient-staging.yaml
git add values/deployments/newclient-staging.yaml
git commit -m "feat: add newclient staging deployment"
git push
```

## Configuration Guidelines

### Naming Convention

- **Infrastructure**: single-file `main.yaml` (folds in the previously-separate argocd + external-dns blocks)
- **Deployments**: `{client}-{environment}.yaml` (e.g., `acme-staging.yaml`)

### Secrets

**Never commit secrets to this directory.** Use External Secrets Operator (ESO) to sync secrets from:
- GCP Secret Manager
- AWS Secrets Manager
- Azure Key Vault

See `charts/external-secrets-stores/`, `charts/external-dns/templates/externalsecret-*.yaml`, `charts/cert-manager-issuers/templates/externalsecret-*.yaml`, and `charts/velero-resources/templates/externalsecret-*.yaml` for ExternalSecret definitions.

### Structure

Keep values files flat and well-commented:

```yaml
# Good
global:
  domain: example.com
  namespace: app-staging

postgresql:
  enabled: true
  auth:
    database: myapp

# Avoid deep nesting
```

## Migration from Old Structure

Layered consolidation across two migrations:
- `argocd/infrastructure/values.yaml` → `values/infrastructure/main.yaml`
- `infrastructure/*/values.yaml` → `values/infrastructure/{component}.yaml`
- `deployments/{client}-{env}/values.yaml` → `values/deployments/{client}-{env}.yaml`
- `values/infrastructure/{argocd,external-dns}.yaml` → folded into `values/infrastructure/main.yaml` (medicard-shape migration)
- New: `values/cluster/` for Terraform module call (DOKS provisioning)

The old `argocd/` and `infrastructure/` top-level directories have been removed. All ArgoCD/Helm definitions now live under `charts/argocd-*` and `charts/*-resources`. ApplicationSet scans `values/deployments/*.yaml` (excluding `example-*.yaml`) for auto-discovery.
