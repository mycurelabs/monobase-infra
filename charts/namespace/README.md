# Namespace Helm Chart

Helm chart for creating namespaces with Pod Security Standards labels and optional resource quotas.

## Purpose

This chart is used by ArgoCD to create client/environment namespaces with:
- **Pod Security Standards** labels (enforce, audit, warn)
- **Environment labels** for identification
- **Optional ResourceQuota** for multi-tenant clusters

## Usage

This chart is deployed automatically by ArgoCD via the `namespace` Application.

Values are passed inline from `charts/argocd-applications/templates/namespace.yaml`:

```yaml
source:
  path: infrastructure/namespaces
  helm:
    values: |
      namespace:
        name: myclient-prod
        labels:
          app.kubernetes.io/name: myclient-prod
          app.kubernetes.io/environment: production
          pod-security.kubernetes.io/enforce: restricted
          pod-security.kubernetes.io/audit: restricted
          pod-security.kubernetes.io/warn: restricted
      
      resourceQuota:
        enabled: false  # Enable for multi-tenant clusters
```

## Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `namespace.name` | Namespace name | `default` |
| `namespace.labels` | Namespace labels | `{}` |
| `namespace.annotations` | Namespace annotations | `{}` |
| `resourceQuota.enabled` | Enable resource quotas | `false` |
| `resourceQuota.limits.cpu` | CPU limit | `"10"` |
| `resourceQuota.limits.memory` | Memory limit | `"20Gi"` |
| `resourceQuota.limits.persistentvolumeclaims` | PVC limit | `"10"` |
| `resourceQuota.limits.pods` | Pod limit | `"50"` |

## Resource Quota Parameters

Resource quotas limit resource consumption in multi-tenant clusters.

### resourceQuotas.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (for multi-tenant clusters)
- **Description:** Enable ResourceQuotas for namespace

### resourceQuotas.limits.cpu
- **Type:** string
- **Default:** `"50"`
- **Description:** Total CPU limit for namespace

### resourceQuotas.limits.memory
- **Type:** string
- **Default:** `"100Gi"`
- **Description:** Total memory limit for namespace

### resourceQuotas.limits.persistentvolumeclaims
- **Type:** string
- **Default:** `"20"`
- **Description:** Maximum number of PVCs in namespace

### resourceQuotas.limits.pods
- **Type:** string
- **Default:** `"100"`
- **Description:** Maximum number of pods in namespace

## Files

- `Chart.yaml` - Helm chart metadata
- `values.yaml` - Default values (overridden by ArgoCD)
- `templates/namespace.yaml` - Namespace resource
- `templates/resourcequota.yaml` - ResourceQuota resource (conditional)
