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

## ApplicationSet Auto-Discovery Pattern

Once ArgoCD is installed, it auto-discovers all client/environment configurations using ApplicationSet:

```
ApplicationSet (argocd/bootstrap/applicationset-auto-discover.yaml)
├── Scans config/*/ directories
├── Creates root Application for each config found
│   ├── config/clienta-prod/ → clienta-prod-root
│   ├── config/clientb-staging/ → clientb-staging-root
│   └── ...
└── Each root Application deploys full stack:
    ├── Security & Namespace (Wave -1, 0)
    ├── Infrastructure (Wave 1)
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

## Infrastructure vs GitOps

**Infrastructure (this directory):**
- ArgoCD itself (installed once manually or via bootstrap.sh)
- Cannot be managed by GitOps (chicken-and-egg problem)
- Lives in `infrastructure/argocd/` alongside other infrastructure components

**GitOps (everything else):**
- All infrastructure and applications
- Managed by ArgoCD via ApplicationSet
- Lives in `argocd/bootstrap/` (ApplicationSet) and `argocd/applications/` (templates)
- Auto-syncs from Git

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
