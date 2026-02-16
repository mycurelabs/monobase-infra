# Namespace Conventions

## Naming Pattern

### Tenant Namespaces
Format: `{client}-{environment}`

Examples:
- `mycure-production` — MyCure production environment
- `mycure-staging` — MyCure staging environment

Each tenant namespace contains:
- Application deployments (hapihub, mycure, syncd, etc.)
- Database StatefulSets (MongoDB, PostgreSQL)
- Cache (Valkey/Redis)
- Object storage (MinIO)
- Email testing (Mailpit)
- ExternalSecrets for the tenant
- Services, ConfigMaps, PVCs

### Infrastructure Namespaces

| Namespace | Purpose | Managed By |
|-----------|---------|------------|
| `gateway-system` | Shared Envoy Gateway | Infrastructure ArgoCD App |
| `envoy-gateway-system` | Envoy Gateway controller | Infrastructure ArgoCD App |
| `external-dns` | Automatic DNS management | Infrastructure ArgoCD App |
| `longhorn-system` | Distributed block storage (optional) | Infrastructure ArgoCD App |
| `argocd` | ArgoCD GitOps controller | Bootstrap (manual) |
| `monitoring` | Prometheus + Grafana | Infrastructure ArgoCD App |
| `cert-manager` | TLS certificate automation | Infrastructure ArgoCD App |
| `external-secrets-system` | External Secrets Operator | Infrastructure ArgoCD App |
| `velero` | Backup and disaster recovery | Infrastructure ArgoCD App |
| `kyverno` | Policy engine (optional) | Infrastructure ArgoCD App |
| `falco` | Runtime security (optional) | Infrastructure ArgoCD App |
| `external-dns` | Automatic DNS management | Infrastructure ArgoCD App |

### System Namespaces (Kubernetes)

| Namespace | Purpose |
|-----------|---------|
| `kube-system` | Core K8s components |
| `kube-public` | Public cluster info |
| `kube-node-lease` | Node heartbeats |
| `default` | Default (unused) |

## Resource Types Per Tenant Namespace

A typical tenant namespace (`mycure-production`) contains:

**Applications:**
- Deployments: hapihub, mycure, mycurelocal, mycurev8, mycure-myaccount, mycure-deploydash, dentalemon, dentalemon-myaccount, dentalemon-website, syncd, api, account
- Each with: Service, HTTPRoute, ConfigMap

**Data stores:**
- StatefulSet: mongodb (replicaset), postgresql (standalone)
- StatefulSet: valkey (standalone), minio (standalone)

**Secrets:**
- ExternalSecrets → Kubernetes Secrets (synced from GCP Secret Manager)
- Database credential secrets (mongodb, postgresql, minio)

**Networking:**
- HTTPRoutes (one per exposed app, referencing shared-gateway)
- NetworkPolicies (if security-baseline chart enabled)

**Scaling & Reliability:**
- HorizontalPodAutoscalers (hapihub, syncd)
- PodDisruptionBudgets (when enabled)

## Creating a New Namespace

Namespaces are created automatically by ArgoCD when a deployment file is added:

```bash
# 1. Create deployment values file
cp values/deployments/mycure-staging.yaml values/deployments/{client}-{env}.yaml

# 2. Update global.namespace to match filename
# global:
#   namespace: {client}-{env}

# 3. Git push — ArgoCD creates namespace via syncOptions.CreateNamespace=true
```

The `namespace` chart can also be used for additional namespace configuration:
- Pod Security Standards enforcement (`podSecurityStandards.level: restricted`)
- Resource quotas
- Label policies
