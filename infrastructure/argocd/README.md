# ArgoCD GitOps

ArgoCD provides declarative, GitOps-based continuous deployment for Kubernetes.

## Features

- **Git as Source of Truth** - All deployments defined in Git
- **Auto-Sync** - Automatic deployment on Git changes
- **Web UI** - Visual deployment management
- **Rollback** - Easy rollback to previous versions
- **Health Status** - Application health monitoring

## Installation

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Or use Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \\
  --namespace argocd \\
  --create-namespace \\
  --values helm-values.yaml
```

## Files

- `helm-values.yaml` - ArgoCD Helm configuration
- `ingress.yaml.template` - Gateway API HTTPRoute for ArgoCD UI

## App-of-Apps Pattern

ArgoCD uses the "App-of-Apps" pattern:

```
root-app (bootstrap)
├── infrastructure apps
│   ├── longhorn
│   ├── envoy-gateway
│   ├── external-secrets
│   └── cert-manager
└── application apps
    ├── mongodb
    ├── hapihub
    ├── syncd
    └── mycureapp
```

## Access ArgoCD UI

```bash
# Port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \\
  -o jsonpath="{.data.password}" | base64 -d

# Open https://localhost:8080
```

## Phase 3 Implementation

Full implementation includes:
- HA configuration (3 replicas)
- RBAC and SSO integration
- App-of-Apps bootstrap structure
- Sync waves for ordered deployment
- Health checks and notifications
