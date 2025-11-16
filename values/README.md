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
    ├── philcare-staging.yaml     # PhilCare staging environment
    └── philcare-production.yaml  # PhilCare production environment
```

## Usage

### Infrastructure Configuration

Infrastructure values are referenced by ArgoCD applications in `argocd/infrastructure/`:

```yaml
# argocd/bootstrap/infrastructure-root.yaml
helm:
  valueFiles:
    - ../../values/infrastructure/main.yaml
```

### Deployment Configuration

Deployment values are automatically discovered by the ApplicationSet in `argocd/bootstrap/applicationset-auto-discover.yaml`.

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
cp values/deployments/philcare-staging.yaml values/deployments/newclient-staging.yaml
# Edit values/deployments/newclient-staging.yaml
git add values/deployments/newclient-staging.yaml
git commit -m "feat: add newclient staging deployment"
git push
```

## Configuration Guidelines

### Naming Convention

- **Infrastructure**: `{component}.yaml` (e.g., `main.yaml`, `argocd.yaml`)
- **Deployments**: `{client}-{environment}.yaml` (e.g., `philcare-staging.yaml`)

### Secrets

**Never commit secrets to this directory.** Use External Secrets Operator (ESO) to sync secrets from:
- GCP Secret Manager
- AWS Secrets Manager
- Azure Key Vault

See `infrastructure/external-secrets/` for ExternalSecret definitions.

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

This directory was created to consolidate configurations previously scattered across:
- `argocd/infrastructure/values.yaml` → `values/infrastructure/main.yaml`
- `infrastructure/*/values.yaml` → `values/infrastructure/{component}.yaml`
- `deployments/{client}-{env}/values.yaml` → `values/deployments/{client}-{env}.yaml`

The old `deployments/` marker directories have been removed. ApplicationSet now directly scans YAML files in `values/deployments/` for auto-discovery.
