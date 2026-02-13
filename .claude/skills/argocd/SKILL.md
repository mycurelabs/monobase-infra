---
name: argocd
description: GitOps deployment management with ApplicationSet auto-discovery
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# ArgoCD GitOps Deployment Skill

## Current Deployments

```
!ls values/deployments/*.yaml
```

## Auto-Discovery Mechanism

The `monobase-auto-discover` ApplicationSet (in `argocd/bootstrap/applicationset-auto-discover.yaml`) uses a **Git Files Generator** to scan `values/deployments/*.yaml`:

1. Scans `values/deployments/*.yaml` (excludes `example-*.yaml`)
2. For each file (e.g., `mycure-production.yaml`):
   - Creates a root Application named `{filename}-root` (e.g., `mycure-production-root`)
   - Deploys to namespace matching filename (e.g., `mycure-production`)
   - Uses the YAML file as Helm values
3. Each root Application renders `argocd/applications/` templates → deploys full stack

## Two-Level App-of-Apps Pattern

```
ApplicationSet (monobase-auto-discover)
  └── Per-deployment root Application (e.g., mycure-production-root)
        ├── namespace chart
        ├── hapihub chart
        ├── mycure chart
        ├── syncd chart
        ├── mongodb (bitnami subchart)
        └── ... (all enabled charts)

Application (infrastructure)
  ├── cert-manager
  ├── envoy-gateway
  ├── external-secrets
  ├── monitoring (prometheus + grafana)
  ├── gateway chart
  └── ... (all enabled infra components)
```

## Common Operations

### Add New Deployment
```bash
# 1. Copy from existing deployment or example
cp values/deployments/mycure-staging.yaml values/deployments/{client}-{env}.yaml

# 2. Edit values (domain, namespace, images, resources, secrets)
# Key fields to update:
#   global.domain, global.namespace, global.environment, global.nodePool
#   Each app's image.tag, gateway.hostname, enabled flags

# 3. Commit and push — ArgoCD auto-discovers and deploys
git add values/deployments/{client}-{env}.yaml
git commit -m "feat: add {client}-{env} deployment"
git push
```

### Update Existing Deployment
```bash
# Edit values file
# e.g., update image tag, change replicas, enable/disable components
vim values/deployments/{client}-{env}.yaml

# Commit and push — ArgoCD auto-syncs
git add values/deployments/{client}-{env}.yaml
git commit -m "chore: bump hapihub to v10.12.0 in {client}-{env}"
git push
```

### Remove Deployment
```bash
# Remove values file — ArgoCD removes the Application
# Note: preserveResourcesOnDeletion=true prevents data loss
git rm values/deployments/{client}-{env}.yaml
git commit -m "chore: remove {client}-{env} deployment"
git push
```

### Check Sync Status
```bash
# Via kubectl (requires argocd CLI or kubectl)
kubectl get applications -n argocd
kubectl describe application {name}-root -n argocd

# Via ArgoCD CLI
argocd app list
argocd app get {name}-root

# Via port-forward to UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Then open https://localhost:8080
```

### Force Sync
```bash
# Via ArgoCD CLI
argocd app sync {name}-root

# Force sync with prune
argocd app sync {name}-root --prune

# Hard refresh (re-read from Git)
argocd app get {name}-root --hard-refresh
```

### Troubleshoot Sync Failure
```bash
# Check application status
kubectl get application {name}-root -n argocd -o yaml

# Check sync result and conditions
argocd app get {name}-root

# Check ArgoCD controller logs
kubectl logs -n argocd deployment/argocd-application-controller --tail=100

# Check repo server logs (for Git/Helm errors)
kubectl logs -n argocd deployment/argocd-repo-server --tail=100
```

## Sync Policies

- **Automated sync**: Git push triggers automatic deployment
- **Self-heal**: Manual kubectl changes are reverted
- **Prune**: Resources deleted from Git are removed from cluster
- **Retry**: 5 retries with exponential backoff (5s to 3m)
- **preserveResourcesOnDeletion**: Removing a deployment file does NOT delete namespace resources

## Bootstrap Operations

Initial cluster setup (one-time):
```bash
# Full bootstrap (installs ArgoCD, deploys infrastructure, enables auto-discover)
mise run bootstrap

# Manual bootstrap steps:
# 1. Install ArgoCD
# 2. kubectl apply -f argocd/bootstrap/infrastructure-root.yaml
# 3. kubectl apply -f argocd/bootstrap/applicationset-auto-discover.yaml
```

## Infrastructure vs Deployment Values

- `values/infrastructure/main.yaml` — Cluster-wide infrastructure config (cert-manager, gateway, monitoring, etc.)
- `values/deployments/*.yaml` — Per-client/environment application config
- Infrastructure is managed by `infrastructure` Application (separate from per-deployment apps)
