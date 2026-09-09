# ArgoCD Application Definitions

This directory contains ArgoCD Application resources for GitOps-managed infrastructure and applications.

## Architecture Overview

**Two-Layer GitOps Architecture:**

1. **Cluster-Wide Infrastructure** (bootstrap/infrastructure-root.yaml)
   - Deployed ONCE per cluster
   - Manages: cert-manager, gateways, storage, security, backups
   - Auto-syncs from Git (drift correction enabled)

2. **Per-Client Applications** (bootstrap/applicationset-auto-discover.yaml)
   - Deployed ONCE per cluster
   - Auto-discovers client/env configs in deployments/
   - Creates per-client Applications automatically

## Directory Structure

```
argocd/
├── bootstrap/
│   ├── infrastructure-root.yaml           # Cluster-wide infrastructure
│   └── applicationset-auto-discover.yaml  # Per-client auto-discovery
├── infrastructure/                        # Helm chart for cluster infrastructure
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── cert-manager.yaml             # TLS certificates (Wave 0)
│       ├── nginx-gateway.yaml            # Gateway API (Wave 0)
│       ├── external-secrets.yaml          # Secret management (Wave 0)
│       ├── velero.yaml                   # Backups (Wave 0)
│       ├── longhorn.yaml                 # Storage (Wave 0, optional)
│       ├── kyverno.yaml                  # Policy engine (Wave 0, optional)
│       ├── kyverno-policies.yaml         # Policies (Wave 1, optional)
│       ├── falco.yaml                    # Runtime security (Wave 0, optional)
│       ├── falco-rules.yaml              # Custom rules (Wave 1, optional)
│       └── monitoring.yaml               # Observability (Wave 0, optional)
└── applications/                          # Helm chart for per-client apps
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── namespace.yaml                # Namespace + PSS (Wave -1)
        ├── security-baseline.yaml        # NetworkPolicies + RBAC (Wave 0)
        ├── postgresql.yaml               # Database (Wave 2)
        ├── valkey.yaml                   # Cache (Wave 2)
        ├── minio.yaml                    # Object storage (Wave 2, optional)
        ├── mailpit.yaml                  # Email testing (Wave 2, dev only)
        ├── api.yaml                      # Backend API (Wave 3)
        └── account.yaml                  # Frontend (Wave 3)
```

## Which branch a cluster tracks (one-ref-per-cluster)

**A cluster does not necessarily track `main`.** Each ArgoCD instance follows exactly
one git ref, set by `argocd.targetRevision` in that cluster's
`values/clusters/<cluster>/argocd/bootstrap.yaml`. Everything downstream inherits it —
the `monobase-auto-discover` ApplicationSet, the per-env root Application, and every
Application it generates — because all of them template the same value.

| Cluster | Tracks | Set in |
|---|---|---|
| `mycure-doks-main` | `HEAD` (i.e. `main`) | chart default, `charts/argocd-bootstrap/values.yaml` |
| `mycure-onprem-vanaheim` | `cluster/vanaheim` | `values/clusters/mycure-onprem-vanaheim/argocd/bootstrap.yaml` |

For a cluster on its own branch the flow is:

- **Deploy** — merge into that cluster's branch (`cluster/vanaheim`). This is what the
  cluster reads, so this is the only thing that changes what is running.
- **Promote** — PR the change from the cluster branch to `main`.
- **Keep current** — re-merge `main` into the cluster branch regularly, so the two do
  not drift into a conflicted mess.

> **⚠️ Anything that writes an image tag must target the cluster's branch, not `main`.**
> A bump pushed to `main` for a cluster tracking `cluster/vanaheim` is a **silent
> no-op**: the commit lands, CI goes green, ArgoCD still reports `Synced` (the cluster
> genuinely matches the branch it reads), the pod keeps serving the old image, and
> nothing anywhere reports a failure. The only visible symptom is the running image tag
> not matching what you just built.
>
> This is not hypothetical — it is exactly what happened to
> `monobase-mycure`'s `hapihub-staging-deploy.yml` between 2026-09-08 and 2026-09-09.
> `cluster/vanaheim` was cut in `931ec45` and the cluster repointed at it the same
> minute, but that workflow kept pushing its tag bump to `main`. Two hapihub staging
> builds were published to ghcr and never deployed before anyone noticed
> (monobase-mycure#4192). Automation that bumps a tag here should read the branch from
> the cluster's `bootstrap.yaml` rather than hardcoding a branch name.

## Bootstrap Workflow

```bash
# Step 1: Install ArgoCD (manual, once)
mise run bootstrap

# This installs:
# 1. ArgoCD itself
# 2. Infrastructure Root Application (cluster infrastructure via GitOps)
# 3. ApplicationSet (per-client auto-discovery)

# Step 2: Add client/env configurations
mkdir deployments/myclient-prod
cp values/deployments/mycure-production.yaml values/deployments/myclient-prod.yaml
vim deployments/myclient-prod/values.yaml  # Edit domain, namespace, etc.
git add deployments/myclient-prod/
git commit -m "Add myclient-prod"
git push

# Step 3: ArgoCD auto-discovers and deploys!
# - Infrastructure already deployed (cluster-wide)
# - ApplicationSet creates myclient-prod Applications
# - All synced from Git automatically
```

## Branch Conventions (one ref per cluster)

Which git ref a cluster's ArgoCD tracks is a **per-cluster invariant** — exactly
one ref for *everything* on the cluster (ApplicationSet generator + template,
infrastructure root, every deployment root):

1. **Production / long-lived clusters: `HEAD` only** — regardless of
   provider. Environments are value files under `values/deployments/`, never
   branches. Long-lived env branches drift and rot into cherry-pick hell —
   the standard ArgoCD guidance applies.
2. **Dev/iteration clusters — disposable ones you nuke and rebuild, on any
   provider: a single
   cluster-tracking branch, `cluster/<name>`.** It carries `main` + whatever
   unmerged work is being tested on that cluster. Set it ONCE in the cluster's
   `values/clusters/<name>/argocd/bootstrap.yaml` (`argocd.targetRevision`) so
   a bootstrap re-apply is deterministic — never as ad-hoc `kubectl` pins on
   individual Applications, which the next bootstrap re-apply silently
   clobbers.

The split is by **cluster role** (long-lived vs dev), not by provider or
location — an on-prem k3s cluster serving real users tracks `HEAD` like any
production cluster.

Working with a cluster-tracking branch:

- **Deploy** = merge your feature branch *into* `cluster/<name>` and push.
- **Promote** = PR your feature branch to `main` as usual; the cluster branch
  absorbs it on the next `main` re-merge.
- **Merge-only, no force-push** — the branch is shared by every workstream on
  the cluster.
- **Re-merge `main` regularly**, otherwise the cluster stops receiving
  mainline infra changes (that's the cost of the pin).
- Multiple feature refs pinned across different apps on one cluster is the
  anti-pattern this convention exists to prevent (it accretes one `kubectl
  edit` at a time and makes bootstrap re-applies destructive).

Current state and per-cluster caveats live in each cluster's README
(`values/clusters/<name>/README.md`).

## Deployment Layers

### Layer 1: Cluster Infrastructure (Wave 0-1)

**Managed by:** `charts/argocd-bootstrap/templates/infrastructure-root.yaml`

**Deploys:** Cluster-wide components (ONE instance per cluster)

| Component | Wave | Enabled By Default | Purpose |
|-----------|------|-------------------|---------|
| cert-manager | 0 | ✅ Yes | TLS certificate automation |
| nginx-gateway | 0 | ✅ Yes | Gateway API implementation |
| external-secrets | 0 | ✅ Yes | Secret management |
| velero | 0 | ✅ Yes | Backup and disaster recovery |
| longhorn | 0 | ❌ No | Distributed block storage |
| kyverno | 0 | ❌ No | Policy engine |
| kyverno-policies | 1 | ❌ No | Policy definitions |
| falco | 0 | ❌ No | Runtime security monitoring |
| falco-rules | 1 | ❌ No | Custom security rules |
| monitoring | 0 | ❌ No | Prometheus + Grafana |

**Configuration:** Edit `charts/argocd-infrastructure/values.yaml` to enable/disable components.

**GitOps Benefits:**

- ✅ Drift detection and auto-correction
- ✅ Updates via git push
- ✅ Full visibility in ArgoCD UI
- ✅ Declarative infrastructure as code

### Layer 2: Per-Client Applications (Wave -1 through 3)

**Managed by:** `charts/argocd-bootstrap/templates/applicationset-auto-discover.yaml`

**Deploys:** Per-client/environment resources (ONE set per client/env)

| Component | Wave | Scope | Purpose |
|-----------|------|-------|---------|
| namespace | -1 | Per-client | Namespace with Pod Security Standards |
| security-baseline | 0 | Per-client | NetworkPolicies + RBAC |
| postgresql | 2 | Per-client | Database instance |
| valkey | 2 | Per-client | Redis cache instance |
| minio | 2 | Per-client | Object storage (optional) |
| mailpit | 2 | Per-client | Email testing (dev/staging) |
| api | 3 | Per-client | Backend application |
| account | 3 | Per-client | Frontend application |

**Configuration:** Each client has `deployments/{client-env}/values.yaml`

**GitOps Workflow:**

```bash
# Add new client
mkdir deployments/newclient-prod
cp values/deployments/mycure-production.yaml values/deployments/newclient-prod.yaml
vim deployments/newclient-prod/values.yaml
git add deployments/newclient-prod/ && git commit -m "Add newclient-prod" && git push
# ✓ ArgoCD auto-creates all Applications for newclient-prod

# Update existing client
vim deployments/existingclient-prod/values.yaml
git commit -am "Update existingclient: enable minio" && git push
# ✓ ArgoCD auto-syncs only existingclient-prod
```

## Sync Waves Explained

Sync waves control deployment order. ArgoCD waits for each wave to be healthy before proceeding.

**Infrastructure (Cluster-Wide):**

- Wave 0: Core infrastructure (cert-manager, gateways, storage, secrets, backups)
- Wave 1: Dependent components (policies, custom rules)

**Applications (Per-Client):**

- Wave -1: Namespace creation (Pod Security Standards labels)
- Wave 0: Security baseline (NetworkPolicies, RBAC)
- Wave 2: Data services (PostgreSQL, Valkey, MinIO, Mailpit)
- Wave 3: Applications (API, Account frontend)

**Example Flow for New Client:**

```
1. Wave -1: Create namespace "myclient-prod" with PSS labels
2. Wave 0: Deploy NetworkPolicies and RBAC to "myclient-prod"
3. Wave 2: Deploy PostgreSQL, Valkey to "myclient-prod"
4. Wave 3: Deploy API, Account to "myclient-prod"
   (API waits for PostgreSQL to be healthy)
```

## Managing Infrastructure

### Enable/Disable Components

Edit `charts/argocd-infrastructure/values.yaml`:

```yaml
# Enable Longhorn storage
longhorn:
  enabled: true
  version: 1.6.0

# Enable Kyverno policies
kyverno:
  enabled: true
  version: 3.2.0
  policies:
    enabled: true
```

Git commit and push - ArgoCD auto-syncs!

### Update Component Versions

Edit `charts/argocd-infrastructure/values.yaml`:

```yaml
certManager:
  enabled: true
  version: v1.15.0  # Updated from v1.14.2
```

Git commit and push - ArgoCD upgrades cert-manager!

### View Infrastructure Status

```bash
# View infrastructure Application
kubectl get application infrastructure -n argocd

# View all infrastructure components
kubectl get applications -n argocd -l app.kubernetes.io/component=cluster-infrastructure

# Check sync status
argocd app get infrastructure
```

## Managing Per-Client Applications

### Add New Client/Environment

```bash
mkdir deployments/newclient-staging
cp values/deployments/mycure-preprod.yaml values/deployments/newclient-staging.yaml

# Edit values
vim deployments/newclient-staging/values.yaml

# Commit and push
git add deployments/newclient-staging/
git commit -m "Add newclient-staging environment"
git push

# ArgoCD auto-discovers within ~30 seconds
kubectl get applications -n argocd | grep newclient-staging
```

### Update Existing Client

```bash
# Edit configuration
vim deployments/myclient-prod/values.yaml

# Commit and push
git commit -am "myclient-prod: increase API replicas to 3"
git push

# ArgoCD auto-syncs within seconds
argocd app sync myclient-prod-api
```

### Remove Client/Environment

```bash
git rm -r deployments/oldclient-prod/
git commit -m "Remove oldclient-prod"
git push

# ApplicationSet auto-removes Applications
# (preserveResourcesOnDeletion=true prevents data loss)
```

## Troubleshooting

### Infrastructure Not Deploying

```bash
# Check infrastructure Application status
kubectl get application infrastructure -n argocd -o yaml

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Manually sync
argocd app sync infrastructure
```

### ApplicationSet Not Discovering Configs

```bash
# Check ApplicationSet status
kubectl get applicationset monobase-auto-discover -n argocd -o yaml

# Verify deployments/ directory structure
ls -la deployments/

# Check ApplicationSet logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```

### Application Stuck in Progressing

```bash
# Check specific application
kubectl get application myclient-prod-api -n argocd -o yaml

# View sync status
argocd app get myclient-prod-api

# Check application logs
kubectl logs -n myclient-prod -l app=api
```

## Architecture Benefits

✅ **Full GitOps:** All infrastructure and applications managed via Git  
✅ **Drift Correction:** Auto-healing enabled for all components  
✅ **Scalability:** Add clients via git push, no manual kubectl  
✅ **Visibility:** Single ArgoCD UI for all infrastructure + apps  
✅ **Safety:** Sync waves prevent deployment race conditions  
✅ **Flexibility:** Enable/disable components per cluster or per client  

## References

- Bootstrap script: `mise run bootstrap`
- Infrastructure values: `charts/argocd-infrastructure/values.yaml`
- Application templates: `charts/argocd-applications/templates/`
- Deployment configs: `deployments/*/values.yaml`
