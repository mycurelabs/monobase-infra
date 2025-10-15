# ArgoCD Application Definitions

This directory contains ArgoCD Application resources that define how applications are deployed.

## Structure

```
argocd/
├── bootstrap/
│   └── root-app.yaml.template    # App-of-Apps (deploys everything)
├── infrastructure/
│   ├── longhorn.yaml.template
│   ├── envoy-gateway.yaml.template
│   ├── external-secrets.yaml.template
│   └── cert-manager.yaml.template
└── applications/
    ├── postgresql.yaml.template  # Database (Wave 2)
    ├── valkey.yaml.template      # Cache (Wave 2)
    ├── minio.yaml.template       # Object storage (Wave 2, optional)
    ├── mailpit.yaml.template     # Email testing (Wave 2, dev only)
    ├── api.yaml.template         # Backend API (Wave 3)
    └── account.yaml.template     # Frontend (Wave 3)
```

## App-of-Apps Pattern

The **root-app** (bootstrap) creates all other applications using the "App-of-Apps" pattern:

```
root-app (bootstrap)
├── Infrastructure (Sync Wave 1)
│   ├── longhorn
│   ├── envoy-gateway
│   ├── external-secrets
│   └── cert-manager
├── Data & Services (Sync Wave 2)
│   ├── postgresql (database)
│   ├── valkey (cache)
│   ├── minio (object storage, optional)
│   └── mailpit (email testing, dev/staging only)
└── Applications (Sync Wave 3)
    ├── api (backend)
    └── account (frontend)
```

## Sync Waves

Sync waves ensure ordered deployment:

1. **Wave 0:** Namespace creation
2. **Wave 1:** Infrastructure (Longhorn, Gateway, Secrets, Cert-Manager)
3. **Wave 2:** Data & Services (PostgreSQL, Valkey, MinIO, Mailpit)
4. **Wave 3:** Applications (Monobase API, Monobase Account)

All dependencies are deployed as **separate ArgoCD Applications**, not as Helm chart sub-charts. This provides:
- Independent lifecycle management
- Better observability in ArgoCD UI
- Granular sync policies (e.g., `prune: false` for databases)
- Ability to deploy databases before applications

## Template Variables

All `.template` files contain placeholders:

- `{{ .Values.global.domain }}` → Client's domain
- `{{ .Values.global.namespace }}` → Client's namespace
- `{{ .Release.Name }}` → Release name

Use `scripts/render-templates.sh` to render with client values.

## Deployment

```bash
# 1. Render templates with client values
./scripts/render-templates.sh \\
  --values config/myclient/values-production.yaml \\
  --output rendered/myclient/

# 2. Deploy root app (deploys everything)
kubectl apply -f rendered/myclient/argocd/root-app.yaml

# 3. Watch progress in ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
```

## Phase 3 Implementation

Full implementation includes:
- Complete Application templates with sync waves
- Health checks and sync policies
- Auto-sync configuration
- Rollback procedures
- Multi-environment support
