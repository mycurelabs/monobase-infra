# ArgoCD Application Definitions

This directory contains ArgoCD Application resources that define how applications are deployed.

## Structure

```
argocd/
├── bootstrap/
│   └── root-app.yaml.template           # App-of-Apps (deploys everything)
├── infrastructure/
│   ├── namespace.yaml.template          # Namespace + PSS labels (Wave -1)
│   ├── security-baseline.yaml.template  # NetworkPolicies + RBAC (Wave 0)
│   ├── kyverno.yaml.template            # Policy engine (Wave 0, optional)
│   ├── kyverno-policies.yaml.template   # Policies (Wave 1, optional)
│   ├── longhorn.yaml.template           # Storage (Wave 1, conditional)
│   ├── envoy-gateway.yaml.template      # Gateway API (Wave 1)
│   ├── external-secrets.yaml.template   # Secrets (Wave 1)
│   ├── cert-manager.yaml.template       # TLS certificates (Wave 1)
│   ├── velero.yaml.template             # Backups (Wave 1)
│   ├── falco.yaml.template              # Runtime security (Wave 1, optional)
│   └── falco-rules.yaml.template        # Custom rules (Wave 2, optional)
└── applications/
    ├── postgresql.yaml.template         # Database (Wave 2)
    ├── valkey.yaml.template             # Cache (Wave 2)
    ├── minio.yaml.template              # Object storage (Wave 2, optional)
    ├── mailpit.yaml.template            # Email testing (Wave 2, dev only)
    ├── api.yaml.template                # Backend API (Wave 3)
    └── account.yaml.template            # Frontend (Wave 3)
```

## App-of-Apps Pattern

The **root-app** (bootstrap) creates all other applications using the "App-of-Apps" pattern:

```
root-app (bootstrap)
├── Security & Namespace (Sync Wave -1, 0)
│   ├── namespace (Wave -1, with Pod Security Standards)
│   ├── security-baseline (Wave 0, NetworkPolicies + RBAC)
│   └── kyverno (Wave 0, optional policy engine)
├── Infrastructure (Sync Wave 1)
│   ├── kyverno-policies (Wave 1, if Kyverno enabled)
│   ├── longhorn (Wave 1, if storage.provider=longhorn)
│   ├── envoy-gateway (Wave 1)
│   ├── external-secrets (Wave 1)
│   ├── cert-manager (Wave 1)
│   ├── velero (Wave 1, backup controller)
│   └── falco (Wave 1, optional runtime security)
├── Data & Services (Sync Wave 2)
│   ├── falco-rules (Wave 2, if Falco enabled)
│   ├── postgresql (database)
│   ├── valkey (cache)
│   ├── minio (object storage, optional)
│   └── mailpit (email testing, dev/staging only)
└── Applications (Sync Wave 3)
    ├── api (backend)
    └── account (frontend)
```

## Sync Waves

Sync waves ensure ordered deployment. ArgoCD waits for each wave to be healthy before proceeding to the next.

### Wave -1: Namespace & Security Foundation
- **namespace** - Creates namespace with Pod Security Standards labels
  - Labels: `pod-security.kubernetes.io/enforce=restricted`
  - Source: `infrastructure/namespaces/`

### Wave 0: Security Baseline & Policy Engine
- **security-baseline** - NetworkPolicies and RBAC (always deployed)
  - Default-deny NetworkPolicies
  - Least-privilege RBAC roles
  - Source: `infrastructure/security/`
- **kyverno** - Policy engine controller (optional, conditional)
  - Only if `security.kyverno.enabled=true`
  - Admission webhook for policy enforcement
  - Source: Helm chart `kyverno/kyverno:3.2.0`

### Wave 1: Infrastructure Components
- **kyverno-policies** - ClusterPolicies (optional, conditional)
  - Only if `security.kyverno.enabled=true`
  - Pod security, labels, registry restrictions
  - Source: `infrastructure/security-tools/kyverno/policies/`
- **longhorn** - Storage provider (conditional)
  - Only if `global.storage.provider=longhorn`
  - CSI driver for persistent volumes
  - Source: Helm chart `longhorn/longhorn:1.6.0`
- **envoy-gateway** - Gateway API implementation (always deployed)
  - HTTP routing, TLS termination
  - Source: Helm chart `gateway/gateway:v1.0.1`
- **external-secrets** - Secret management (always deployed)
  - Syncs secrets from cloud providers
  - Source: Helm chart `external-secrets/external-secrets:0.9.11`
- **cert-manager** - TLS certificate automation (always deployed)
  - Let's Encrypt integration
  - Source: Helm chart `jetstack/cert-manager:v1.14.2`
- **velero** - Backup controller (always deployed)
  - Cluster-wide backup infrastructure
  - Source: Helm chart `vmware-tanzu/velero:7.1.4`
- **falco** - Runtime security monitoring (optional, conditional)
  - Only if `security.falco.enabled=true`
  - eBPF-based threat detection DaemonSet
  - Source: Helm chart `falcosecurity/falco:4.6.1`

### Wave 2: Data Services & Custom Rules
- **falco-rules** - Custom Falco rules (optional, conditional)
  - Only if `security.falco.enabled=true`
  - API-specific and database-specific rules
  - Source: `infrastructure/security-tools/falco/rules/`
- **postgresql** - Database (always deployed)
  - Primary database for API
  - Source: Helm chart `bitnami/postgresql:14.x`
- **valkey** - Redis cache (always deployed)
  - Session and cache storage
  - Source: Helm chart `bitnami/valkey:7.x`
- **minio** - Object storage (optional, conditional)
  - Only if `minio.enabled=true`
  - S3-compatible storage
  - Source: Helm chart `bitnami/minio:latest`
- **mailpit** - Email testing (dev/staging only)
  - Only if `mailpit.enabled=true`
  - SMTP server for testing
  - Source: Helm chart `jouve/mailpit:latest`

### Wave 3: Applications
- **api** - Monobase API backend (always deployed)
  - Main application backend
  - Includes Velero backup schedules
  - Source: `charts/api/`
- **account** - Monobase Account frontend (always deployed)
  - User-facing frontend
  - Source: `charts/account/`

## Conditional Deployment

Some components deploy conditionally based on configuration:

| Component | Condition | Default (Production) | Default (Staging) |
|-----------|-----------|----------------------|-------------------|
| **kyverno** | `security.kyverno.enabled=true` | `false` | `false` |
| **kyverno-policies** | `security.kyverno.enabled=true` | `false` | `false` |
| **falco** | `security.falco.enabled=true` | `false` | `false` |
| **falco-rules** | `security.falco.enabled=true` | `false` | `false` |
| **longhorn** | `global.storage.provider=longhorn` | `false` (use cloud) | `false` (use cloud) |
| **minio** | `minio.enabled=true` | `false` (use S3) | `false` (use S3) |
| **mailpit** | `mailpit.enabled=true` | `false` (use real SMTP) | `true` |

**Note:** Security baseline (NetworkPolicies, RBAC, PSS), Velero, and core infrastructure are **always deployed** in all environments.

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
