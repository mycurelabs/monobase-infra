# GitOps with ArgoCD

Complete guide to GitOps workflow using ArgoCD for Monobase Infrastructure.

## GitOps Principles

**Git as Single Source of Truth:**
- All desired state in Git
- Declarative configuration
- Automated sync to cluster
- Version controlled deployments
- Easy rollback capabilities

## ArgoCD Architecture

```
Git Repository (client fork)
  ├── charts/ (Helm charts)
  ├── deployments/{client}/ (values files)
  └── argocd/ (Application definitions)
          ↓
    ArgoCD watches repo
          ↓
    Detects changes (auto-sync)
          ↓
    Renders Helm charts
          ↓
    Applies to Kubernetes
          ↓
    Monitors health status
```

## App-of-Apps Pattern

**Root Application deploys everything:**

```
root-app.yaml (bootstrap)
├── Infrastructure Apps (Wave 1)
│   ├── longhorn
│   ├── envoy-gateway
│   ├── external-secrets
│   └── cert-manager
└── Application Apps (Wave 2-3)
    ├── postgresql (Wave 2)
    ├── minio (Wave 2)
    ├── api (Wave 3)
    ├── api-worker (Wave 3)
    └── account (Wave 3)
```

**Sync Waves ensure ordered deployment:**
- Wave 0: Namespace
- Wave 1: Infrastructure
- Wave 2: Data stores
- Wave 3: Applications

## Deployment Workflow

### Initial Deployment

```bash
# 1. Fork template repository
# 2. Create client configuration
./scripts/new-client-config.sh myclient myclient.com

# 3. Customize values
vim deployments/myclient/values-production.yaml

# 4. Commit to your fork
git add deployments/myclient/
git commit -m "Add MyClient configuration"
git push origin main

# 5. Deploy ArgoCD root app
cat argocd/bootstrap/root-app.yaml.template | \
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \
  sed 's|{{ .Values.argocd.repoURL }}|https://github.com/myclient/client-infra.git|g' | \
  kubectl apply -f -

# 6. Watch deployment
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
```

### Update Application

**GitOps way (declarative):**

```bash
# 1. Update configuration in Git
vim deployments/myclient/values-production.yaml
# Change: image.tag: "5.215.2" → "5.216.0"

# 2. Commit and push
git add deployments/myclient/values-production.yaml
git commit -m "Update Monobase API to 5.216.0"
git push origin main

# 3. ArgoCD detects change and syncs automatically
# (if auto-sync enabled)

# 4. Or manually sync
argocd app sync myclient-prod-api
```

**Manual way (for emergencies):**

```bash
# Not recommended - bypasses GitOps!
kubectl set image deployment/api \
  api=ghcr.io/YOUR-ORG/api:5.216.0 \
  -n myclient-prod

# Then update Git to match reality
```

## ArgoCD CLI

### Installation

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

### Common Commands

```bash
# Login
argocd login argocd.myclient.com

# List applications
argocd app list

# Get application details
argocd app get myclient-prod-api

# Sync application
argocd app sync myclient-prod-api

# Rollback to previous version
argocd app rollback myclient-prod-api

# Watch sync status
argocd app wait myclient-prod-api

# View application logs
argocd app logs myclient-prod-api
```

## Sync Policies

### Auto-Sync (Recommended)

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Revert manual changes
```

**Benefits:**
- Changes deployed automatically
- Manual kubectl changes reverted
- Always matches Git state

**Risks:**
- Bad commits deployed immediately
- Need good testing/staging workflow

### Manual Sync (Conservative)

```yaml
syncPolicy:
  automated: null  # Manual sync only
```

**Benefits:**
- Full control over deployments
- Review before applying

**Drawbacks:**
- Manual sync required for every change
- Can drift from Git

## Health Checks

ArgoCD monitors application health:

```bash
# Check health status
argocd app get myclient-prod-api

# Status values:
# - Healthy: All resources healthy
# - Progressing: Deployment in progress
# - Degraded: Some resources unhealthy
# - Suspended: Application suspended
```

## Troubleshooting

### Application OutOfSync

```bash
# Compare Git vs cluster
argocd app diff myclient-prod-api

# Force sync
argocd app sync myclient-prod-api --force

# Hard refresh
argocd app get myclient-prod-api --hard-refresh
```

### Sync Failing

```bash
# Check sync status
argocd app get myclient-prod-api

# View sync errors
kubectl describe application myclient-prod-api -n argocd

# Common issues:
# - Invalid Helm values
# - Missing secrets
# - Resource quotas exceeded
# - RBAC permissions
```

## Best Practices

1. **Always commit before deploying** - Git is source of truth
2. **Use sync waves** - Control deployment order
3. **Enable auto-sync in production** - Fast updates
4. **Use manual sync in critical systems** - More control
5. **Test in staging first** - Validate changes before prod
6. **Monitor ArgoCD notifications** - Configure Slack/email alerts
7. **Regular Git hygiene** - Clean commit messages, tags for releases

For deployment procedures, see [DEPLOYMENT.md](DEPLOYMENT.md).
