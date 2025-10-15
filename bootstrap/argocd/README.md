# ArgoCD Bootstrap

ArgoCD is the GitOps engine that deploys and manages all applications in this repository.

**Important:** ArgoCD is **bootstrap infrastructure** - it cannot deploy itself via GitOps. It must be installed first before deploying the root-app (App-of-Apps).

## Purpose

This directory contains ArgoCD installation configuration used by the bootstrap script (`scripts/bootstrap.sh`).

**You should NOT manually install ArgoCD.** Use the bootstrap script instead:

```bash
# Bootstrap entire stack (includes ArgoCD + all apps)
./scripts/bootstrap.sh --client myclient --env production
```

## Manual Installation (Not Recommended)

If you need to install ArgoCD manually (e.g., for debugging):

```bash
# Install ArgoCD via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values bootstrap/argocd/helm-values.yaml \
  --wait
```

## Files

- **`helm-values.yaml`** - ArgoCD Helm chart configuration
  - HA setup (3 replicas for server, repo-server, application-controller)
  - Resource limits
  - RBAC settings
  - Used by `scripts/bootstrap.sh`

- **`httproute.yaml.template`** - Gateway API HTTPRoute for ArgoCD UI
  - Exposes ArgoCD web interface
  - Rendered and deployed by root-app
  - Path: `argocd.{domain}`

## App-of-Apps Pattern

Once ArgoCD is installed, it deploys everything else using the "App-of-Apps" pattern:

```
root-app (argocd/bootstrap/root-app.yaml.template)
├── Security & Namespace (Wave -1, 0)
│   ├── namespace
│   ├── security-baseline
│   └── kyverno (optional)
├── Infrastructure (Wave 1)
│   ├── longhorn (conditional)
│   ├── envoy-gateway
│   ├── external-secrets
│   ├── cert-manager
│   ├── velero
│   └── falco (optional)
├── Data Services (Wave 2)
│   ├── postgresql
│   ├── valkey
│   ├── minio (optional)
│   └── mailpit (dev/staging)
└── Applications (Wave 3)
    ├── api
    └── account
```

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

**Bootstrap (this directory):**
- ArgoCD itself (installed once manually or via bootstrap.sh)
- Cannot be managed by GitOps (chicken-and-egg problem)
- Lives in `bootstrap/argocd/`

**GitOps (everything else):**
- All infrastructure and applications
- Managed by ArgoCD
- Lives in `argocd/infrastructure/` and `argocd/applications/`
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
