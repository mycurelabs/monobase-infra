# ArgoCD Infrastructure

ArgoCD is the GitOps engine that deploys and manages all applications in this repository.

**Important:** ArgoCD is **core infrastructure** - it cannot deploy itself via GitOps. It must be installed first before enabling auto-discovery.

## Purpose

This directory contains ArgoCD installation configuration used by the bootstrap script (`scripts/bootstrap.sh`).

**You should NOT manually install ArgoCD.** Use the bootstrap script instead:

```bash
# Bootstrap GitOps auto-discovery (includes ArgoCD installation)
./scripts/bootstrap.sh
```

## Manual Installation (Not Recommended)

If you need to install ArgoCD manually (e.g., for debugging):

```bash
# Install ArgoCD via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values infrastructure/argocd/helm-values.yaml \
  --wait
```

## Files

- **`helm-values.yaml`** - ArgoCD Helm chart configuration
  - HA setup (2-3 replicas for server, repo-server, application-controller)
  - ApplicationSet controller enabled (required for auto-discovery!)
  - Resource limits
  - RBAC settings
  - Used by `scripts/bootstrap.sh`

## GitOps Architecture

Once ArgoCD is installed, it manages TWO layers:

### Layer 1: Cluster-Wide Infrastructure (GitOps)

```
Infrastructure Root (argocd/bootstrap/infrastructure-root.yaml)
├── Deployed ONCE per cluster
└── Manages cluster-wide components via GitOps:
    ├── cert-manager (TLS certificates)
    ├── envoy-gateway (Gateway API)
    ├── external-secrets (Secret management)
    ├── velero (Backups)
    ├── longhorn (Storage, optional)
    ├── kyverno (Policy engine, optional)
    └── monitoring (Observability, optional)
```

**Benefits:** Drift correction, updates via git push, full ArgoCD visibility

### Layer 2: Per-Client Applications (GitOps Auto-Discovery)

```
ApplicationSet (argocd/bootstrap/applicationset-auto-discover.yaml)
├── Scans deployments/*/ directories
├── Creates Applications for each client/env found
│   ├── deployments/clienta-prod/ → clienta-prod-*
│   ├── deployments/clientb-staging/ → clientb-staging-*
│   └── ...
└── Each client gets full stack:
    ├── Namespace + Security (Wave -1, 0)
    ├── Data Services (Wave 2)
    └── Applications (Wave 3)
```

**True GitOps**: Just add config directory + git push → ArgoCD deploys automatically!

## Access ArgoCD UI

After bootstrap completes:

```bash
# Port-forward to access UI
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Open browser
open https://localhost:8080

# Login
# Username: admin
# Password: (from command above)
```

Or via Gateway API (if configured):

```
https://argocd.yourdomain.com
```

## Bootstrap vs GitOps

**Bootstrap (Manual, Once):**
- ArgoCD itself (installed via bootstrap.sh)
- Cannot be managed by GitOps (chicken-and-egg problem)
- Configuration: `infrastructure/argocd/helm-values.yaml`

**GitOps (Managed by ArgoCD):**
- Cluster-wide infrastructure (cert-manager, gateways, storage, etc.)
  - Configuration: `argocd/infrastructure/values.yaml`
  - Application: `argocd/bootstrap/infrastructure-root.yaml`
- Per-client applications (namespace, security, databases, apps)
  - Configuration: `deployments/*/values.yaml`
  - ApplicationSet: `argocd/bootstrap/applicationset-auto-discover.yaml`

After bootstrap, **only ArgoCD itself** requires manual management. Everything else is GitOps!

## Configuration

ArgoCD configuration in `helm-values.yaml`:

- **HA Mode:** 3 replicas for high availability
- **Resources:** Optimized for production workloads
- **RBAC:** Admin access by default
- **Sync:** Auto-sync disabled (require manual approval)
- **Notifications:** Disabled (can enable via values)

## Troubleshooting

**ArgoCD pods not starting:**
```bash
kubectl get pods -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

**CRDs not installed:**
```bash
kubectl get crds | grep argoproj.io
```

**Reset admin password:**
```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
kubectl -n argocd rollout restart deployment argocd-server
```

## See Also

- [Bootstrap Script](../../scripts/bootstrap.sh) - E2E cluster bootstrap
- [Deployment Guide](../../docs/getting-started/DEPLOYMENT.md) - Complete deployment instructions
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/) - Official ArgoCD docs
