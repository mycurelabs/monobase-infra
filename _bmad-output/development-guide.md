# Development Guide - monobase-infra

## Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| **mise** | Latest | `curl https://mise.run \| sh` |
| **kubectl** | 1.31+ | Via mise: `mise install kubectl` |
| **helm** | 3.16+ | Via mise: `mise install helm` |
| **terraform** | 1.9+ | Via mise: `mise install terraform` |
| **k3d** | 5.8+ | Via mise: `mise install k3d` |
| **bun** | Latest | Via mise: `mise install bun` |

### Quick Setup with mise

```bash
# Install mise (tool version manager)
curl https://mise.run | sh

# Install all tools defined in mise.toml
cd monobase-infra
mise install

# Verify installations
mise list
```

## Local Development Setup

### 1. Create Local Kubernetes Cluster

**Option A: Using provision script (recommended)**
```bash
# Create k3d cluster with all defaults
mise run provision -- --cluster k3d-local

# This will:
# - Create k3d cluster named "k3d-local"
# - Configure kubeconfig
# - Install Gateway API CRDs
```

**Option B: Manual k3d**
```bash
# Create cluster manually
k3d cluster create monobase-dev \
  --api-port 6550 \
  -p "8080:80@loadbalancer" \
  -p "8443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:*"

# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

### 2. Bootstrap GitOps

```bash
# Run bootstrap script
mise run bootstrap

# Or with Bun directly
bun scripts/bootstrap.ts

# This will:
# - Install ArgoCD
# - Deploy infrastructure-root Application
# - Deploy ApplicationSet for auto-discovery
# - Output ArgoCD UI access info
```

### 3. Deploy Example Application

```bash
# Copy example deployment
cp -r deployments/example-k3d deployments/dev-local

# Edit configuration
vim deployments/dev-local/values.yaml
# Change:
#   - global.namespace: dev-local
#   - global.domain: localhost

# For local development, create the values file in the right location
mkdir -p values/deployments
cp deployments/dev-local/values.yaml values/deployments/dev-local.yaml

# Commit and push (or apply directly for local testing)
git add values/deployments/dev-local.yaml
git commit -m "Add dev-local deployment"
```

## Common Tasks

### Run All Linters

```bash
mise run lint

# Individual linters:
mise run lint-tf      # Terraform
mise run lint-yaml    # YAML files
mise run lint-shell   # Shell scripts
mise run lint-helm    # Helm charts
mise run lint-md      # Markdown
```

### Validate Configurations

```bash
mise run validate

# Individual validations:
mise run validate-tf    # Terraform modules
mise run validate-helm  # Helm charts
```

### Format Code

```bash
mise run fmt          # Format Terraform
mise run fix          # Auto-fix Terraform and Markdown
```

### Access Admin UIs

```bash
# Port-forward to admin interfaces
mise run admin

# Or specific services:
mise run admin -- argocd    # ArgoCD UI
mise run admin -- grafana   # Grafana dashboards
mise run admin -- prometheus # Prometheus
```

### Manage Secrets

```bash
# Configure secrets
mise run secrets

# Validate secrets
mise run validate-secrets
```

## Directory-Specific Workflows

### Working with Terraform

```bash
cd terraform/modules/local-k3d

# Initialize
terraform init

# Plan changes
terraform plan -var="cluster_name=test"

# Apply
terraform apply -var="cluster_name=test"

# Destroy
terraform destroy -var="cluster_name=test"
```

### Working with Helm Charts

```bash
cd charts/api

# Lint chart
helm lint .

# Template locally (see rendered YAML)
helm template test . --values values.yaml

# Template with custom values
helm template test . -f ../../deployments/example-k3d/values.yaml

# Install directly (for testing)
helm install test . --namespace test --create-namespace

# Upgrade
helm upgrade test . --namespace test

# Uninstall
helm uninstall test --namespace test
```

### Working with ArgoCD

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access: https://localhost:8080
# Username: admin
# Password: (from above)

# CLI: Sync an application
argocd app sync myapp-prod

# CLI: Get app status
argocd app get myapp-prod
```

## Testing

### Helm Unit Tests

```bash
# Install helm-unittest plugin
helm plugin install https://github.com/helm-unittest/helm-unittest

# Run tests
mise run test-helm
```

### Integration Testing

```bash
# Deploy to local k3d cluster
# 1. Ensure k3d cluster is running
k3d cluster list

# 2. Deploy via ArgoCD (GitOps way)
# Push changes to Git, ArgoCD syncs automatically

# 3. Or deploy directly (for rapid testing)
helm install api charts/api --namespace test --create-namespace

# 4. Test endpoints
kubectl port-forward svc/api -n test 7213:7213
curl http://localhost:7213/health
```

### Security Scanning

```bash
# Scan for secrets in codebase
mise run detect-secrets

# Scan Helm charts for misconfigurations (optional: install tools)
# helm plugin install https://github.com/bridgecrewio/checkov
# checkov -d charts/
```

## Troubleshooting

### k3d Cluster Issues

```bash
# List clusters
k3d cluster list

# Check cluster status
kubectl cluster-info

# View k3d logs
docker logs k3d-monobase-dev-server-0

# Delete and recreate
k3d cluster delete monobase-dev
k3d cluster create monobase-dev ...
```

### ArgoCD Issues

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# View ArgoCD logs
kubectl logs -n argocd deployment/argocd-server

# Force sync
argocd app sync myapp --force

# Refresh from Git
argocd app get myapp --refresh
```

### Helm Issues

```bash
# List releases
helm list -A

# Get release status
helm status myrelease -n mynamespace

# View release history
helm history myrelease -n mynamespace

# Rollback
helm rollback myrelease 1 -n mynamespace
```

## Environment Variables

### Local Development (.env.local)

```bash
# Create local env file (gitignored)
cat > .env.local << 'EOF'
# Kubernetes context
KUBECONFIG=~/.kube/k3d-monobase-dev

# ArgoCD
ARGOCD_SERVER=localhost:8080

# Development mode
NODE_ENV=development
EOF
```

## Git Workflow

### Branch Strategy

```
main              # Production-ready
├── feature/*     # New features
├── fix/*         # Bug fixes
└── docs/*        # Documentation updates
```

### Commit Convention

```bash
# Format: type(scope): description

feat(charts): add HPA to api chart
fix(terraform): correct VPC CIDR range
docs(readme): update quick start guide
chore(deps): update Helm to 3.16.2
```

### Pre-commit Checks

```bash
# Run all checks before committing
mise run check

# This runs:
# - lint (all linters)
# - validate (Terraform + Helm)
```

## Cleanup

```bash
# Delete local k3d cluster
k3d cluster delete monobase-dev

# Clean Terraform state
mise run clean

# Remove all generated files
rm -rf .terraform
rm -rf terraform/modules/*/.terraform
```
