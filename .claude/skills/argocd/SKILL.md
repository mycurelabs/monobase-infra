---
name: argocd
description: GitOps deployment management with ApplicationSet auto-discovery
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# ArgoCD GitOps Deployment Skill

## Kubeconfig Resolution

**Always run the `kubectl-access` skill first** to resolve `--kubeconfig` and `--context`. Every `kubectl` / `argocd` command in this skill assumes those flags are passed explicitly; they are omitted below for readability. Do **not** `export KUBECONFIG` and do **not** `kubectl config use-context`.

---

## The hard rule: Health > Sync

**"Healthy + OutOfSync" is a normal steady state** for cert-manager, gateway controllers, external-secrets, and other apps with controller-managed resources. ArgoCD has known bugs (#21308, #18344, #9678) where `ignoreDifferences` doesn't fully suppress drift on these.

Therefore:

- **Always report Health first, Sync second.**
- **Never** suggest a force-sync just because something is `OutOfSync`. Only suggest sync when:
  - Health is `Degraded` or `Missing`, **or**
  - The user explicitly wants to apply a fresh git commit (i.e. they pushed and want it live now).
- When listing apps, group by Health, not by Sync.

## Refresh vs Sync

A **refresh** is cheap: it re-reads manifests from git and does **not** touch the cluster. It is the right first move 90% of the time — especially when someone just pushed.

```bash
# Normal refresh — re-fetches manifests from git
kubectl -n argocd annotate app <name> argocd.argoproj.io/refresh=normal --overwrite

# Hard refresh — also busts the manifest cache. Use when you suspect cache poisoning
# or after a chart dependency update that ArgoCD didn't notice.
kubectl -n argocd annotate app <name> argocd.argoproj.io/refresh=hard --overwrite
```

A **sync** applies to the cluster. Do not reach for it until a refresh has been attempted or the user explicitly asks.

## Sync safety preamble

Before issuing any sync, check the app name. If it matches any of these, **stop and confirm with the user** before proceeding:

- `*-namespace` (Wave -1)
- `*-security-baseline` (Wave 0)
- `cert-manager`, `external-secrets`, `external-dns`, `gateway-resources` (Wave 0 infra)
- `infrastructure` (the cluster-wide root)

These have `PruneLast=true` / `preserveResourcesOnDeletion: true` protections for good reason; an unintended sync can cascade.

---

## Quick Operations

### sync — Force sync application (bypass 3-min polling cycle)
```bash
# Sync single application
argocd app sync {app-name}

# Sync with prune (remove deleted resources)
argocd app sync {app-name} --prune

# Sync with force (replace changed resources)
argocd app sync {app-name} --force

# Examples:
argocd app sync mycure-staging-root
argocd app sync mycure-production-root --prune
```

### diff — Preview pending changes before sync
```bash
# Show what would change on next sync
argocd app diff {app-name}

# Examples:
argocd app diff mycure-staging-root
argocd app diff infrastructure
```

### status — Check sync/health status
```bash
# List all applications with status
argocd app list -o wide

# Get detailed status for specific app
argocd app get {app-name}

# Show operation history
argocd app get {app-name} --show-operation

# Via kubectl (no argocd CLI needed)
kubectl get applications -n argocd
kubectl get applications -n argocd -o wide

# Examples:
argocd app list
argocd app get mycure-staging-root
```

### rollback — Rollback to previous revision ⚠️ DESTRUCTIVE
```bash
# ⚠️ CONFIRM BEFORE EXECUTING - this reverts to a previous state

# Show revision history
argocd app history {app-name}

# Rollback to specific revision
argocd app rollback {app-name} {revision}

# Examples:
argocd app history mycure-staging-root
argocd app rollback mycure-staging-root 5
```

**Stateful safety:** Rollback only undoes the manifest sync, not data migrations. Before rolling back any app whose name matches `*mongodb*`, `*postgres*`, `*valkey*`, `*minio*`, or `*migrator*`, **stop and confirm with the user** that they understand a schema/data migration may have already run forward and will not be reversed.

### pause — Pause/resume auto-sync for maintenance
```bash
# Pause auto-sync (for manual maintenance)
kubectl patch application {app-name} -n argocd --type merge \
  -p '{"spec":{"syncPolicy":null}}'

# Resume auto-sync
kubectl patch application {app-name} -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

# Examples:
kubectl patch application mycure-staging-root -n argocd --type merge -p '{"spec":{"syncPolicy":null}}'
```

### refresh — Hard refresh from Git (re-read manifests)
```bash
argocd app get {app-name} --hard-refresh

# Examples:
argocd app get mycure-staging-root --hard-refresh
```

---

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

## Verify a deployment is *actually* done

A deploy is "done" only when **all five** of these are true. Run the composite block below and report each line:

```bash
APP=<app-name>         # e.g. mycure-staging-hapihub
NS=<target-namespace>  # e.g. mycure-staging

# 1. Health status
kubectl -n argocd get app "$APP" -o jsonpath='{.status.health.status}{"\n"}'

# 2. Synced revision matches what the Application targets
kubectl -n argocd get app "$APP" -o jsonpath='target={.spec.source.targetRevision} synced={.status.sync.revision}{"\n"}'

# 3. All Deployments + StatefulSets fully available
kubectl -n "$NS" get deploy,statefulset \
  -o custom-columns=KIND:.kind,NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas

# 4. No Warning events in the last few minutes
kubectl -n "$NS" get events --field-selector type=Warning --sort-by=.lastTimestamp | tail -20

# 5. HTTPRoutes accepted (only if the app exposes one)
kubectl -n "$NS" get httproute -o json 2>/dev/null \
  | jq -r '.items[] | "\(.metadata.name): " + ([.status.parents[].conditions[] | select(.type=="Accepted") | .status] | join(","))'
```

A "Healthy" app whose `synced revision` is **older** than the `targetRevision` means the deploy is still in flight, not done — keep watching.

## Decision recipes

| User says | Do |
|---|---|
| "is mycure-staging healthy?" | `kubectl -n argocd get app ...` grouped by Health first, Sync second |
| "X is OutOfSync, fix it" | First check Health. If Healthy, explain the Health>Sync rule and ask whether they actually want a sync. |
| "I just pushed, deploy it" | `refresh=normal` annotation, then watch with `kubectl -n argocd get app <name> -w` |
| "the chart cache is stale" | `refresh=hard` annotation |
| "force-sync X" | Apply the sync safety preamble (Wave -1/0 confirm), then `argocd app sync` |
| "is the deploy done?" | Run the 5-check block above |
| "I rotated the DB password" | Annotate the relevant ExternalSecret with `force-sync=$(date +%s)` (see `k8s` skill) |
| "rollback X" | `argocd app history` + `argocd app rollback`, with stateful-safety check for db/migrator apps |
| "bring up a fresh cluster" | `mise run bootstrap` |
