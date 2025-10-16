# Helm Charts

Reusable Helm charts for deploying Monobase applications.

## Overview

This directory contains **Helm charts** for all Monobase components:

- **api** - Monobase API backend service
- **account** - Monobase Account frontend application  
- **namespace** - Namespace creation with Pod Security Standards

**What's here:** Application Helm charts (internal implementation)  
**What you deploy:** Client configurations in `../deployments/` (root level)  
**Complements:** Infrastructure in `../infrastructure/` and cluster provisioning in `../clusters/`

## Quick Start

**Note:** You typically work with deployment configs in `../deployments/`, not these charts directly.

```bash
# Deployment configs use these charts:
deployments/
├── example-prod/       # Production deployment
├── example-staging/    # Staging deployment
└── example-k3d/        # Local k3d testing

# Deploy via ArgoCD (GitOps):
git add deployments/myclient-prod/values.yaml
git commit -m "feat: add myclient production config"
git push
# ArgoCD auto-discovers and deploys

# Or manually with Helm:
helm install myclient-api ./charts/api -f deployments/myclient-prod/values.yaml
```

## Charts

| Chart | Description | Dependencies |
|-------|-------------|--------------|
| **api** | Monobase API backend | PostgreSQL, Valkey, optional MinIO |
| **account** | Monobase Account frontend | None (calls API) |
| **namespace** | Namespace + Pod Security | None |

## Global Parameters

Global parameters are shared across all charts and must be configured in your deployment values file.

### global.domain
- **Type:** string
- **Required:** Yes
- **Example:** `myclient.com`
- **Description:** Base domain for all services
- **Pattern:** Valid domain name

### global.namespace
- **Type:** string
- **Required:** Yes
- **Example:** `myclient-prod`
- **Description:** Kubernetes namespace for deployment
- **Pattern:** `{client}-{env}` (lowercase alphanumeric with hyphens)

### global.environment
- **Type:** string
- **Required:** Yes
- **Options:** `development`, `staging`, `production`
- **Description:** Environment identifier

### global.gateway.name
- **Type:** string
- **Default:** `shared-gateway`
- **Description:** Name of shared Gateway resource

### global.gateway.namespace
- **Type:** string
- **Default:** `gateway-system`
- **Description:** Namespace where shared Gateway is deployed

### global.storage.provider
- **Type:** string
- **Options:** `cloud-default`, `longhorn`, `local-path`
- **Default:** `cloud-default`
- **Description:** Storage provider (see `../docs/operations/STORAGE.md`)

### global.storage.className
- **Type:** string
- **Default:** `""` (auto-detect)
- **Description:** StorageClass name (empty = use provider default)

## Chart-Specific Documentation

Each chart has detailed parameter documentation:

- **[api/README.md](api/README.md)** - Monobase API configuration, resources, dependencies
- **[account/README.md](account/README.md)** - Account frontend configuration
- **[namespace/README.md](namespace/README.md)** - Namespace and resource quota configuration

## Deployment Configuration

For complete deployment configuration guides, see:

- **[../deployments/README.md](../deployments/README.md)** - How to configure deployments
- **[../docs/getting-started/CLIENT-ONBOARDING.md](../docs/getting-started/CLIENT-ONBOARDING.md)** - New client setup

## Example Global Configuration

### Minimal (Staging)

```yaml
global:
  domain: myclient.com
  namespace: myclient-staging
  environment: staging
  storage:
    provider: cloud-default
    className: ""
```

### Production (HA)

```yaml
global:
  domain: myclient.com
  namespace: myclient-prod
  environment: production
  gateway:
    name: shared-gateway
    namespace: gateway-system
  storage:
    provider: longhorn  # Or cloud-default for EKS/AKS/GKE
    className: longhorn
```

## Development

### Chart Structure

Each chart follows standard Helm conventions:

```
charts/{chart-name}/
├── Chart.yaml           # Chart metadata
├── values.yaml          # Default values
├── values.schema.json   # JSON schema (validation)
├── README.md            # Chart documentation
└── templates/           # Kubernetes manifests
    ├── deployment.yaml
    ├── service.yaml
    ├── httproute.yaml
    └── ...
```

### Testing Charts Locally

```bash
# Lint chart
helm lint ./charts/api

# Dry-run install
helm install --dry-run --debug myclient-api ./charts/api -f deployments/example-prod/values.yaml

# Render templates
helm template myclient-api ./charts/api -f deployments/example-prod/values.yaml
```

### Chart Dependencies

Dependencies are managed in `Chart.yaml`:

```yaml
# Example: charts/api/Chart.yaml
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled
```

Update dependencies:

```bash
cd charts/api
helm dependency update
```

## Next Steps

1. **Read:** Chart-specific READMEs for detailed parameter documentation
2. **Configure:** Create deployment values in `../deployments/`
3. **Deploy:** Use ArgoCD GitOps or manual Helm install
4. **Monitor:** See `../docs/operations/MONITORING.md`
