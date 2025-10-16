# Example k3d Local Development Deployment

Local development configuration for testing monobase on k3d.

## Overview

This configuration is optimized for:
- Local development and testing on laptop/workstation
- Minimal resource consumption
- Fast iteration cycles
- Email testing with Mailpit

## Key Features

- Single replica deployments (no HA overhead)
- Minimal resource requests and limits
- k3d's local-path storage
- Mailpit enabled for email testing
- External Secrets disabled (use plain Kubernetes Secrets)
- No backup, monitoring, or MinIO (save resources)

## Prerequisites

- k3d cluster running (see `clusters/example-k3d/`)
- ArgoCD bootstrapped

## Quick Start

1. **Ensure k3d cluster is running:**
   ```bash
   kubectl cluster-info
   ```

2. **This deployment is auto-discovered by ArgoCD** from the `deployments/example-k3d/` directory.

3. **View the deployment:**
   ```bash
   kubectl get applications -n argocd -l app.kubernetes.io/instance=example-k3d
   ```

## Customization

To create your own local deployment:

```bash
cp -r deployments/example-k3d deployments/myproject-dev
cd deployments/myproject-dev
vim values.yaml  # Change domain, namespace, etc.
git add .
git commit -m "Add myproject-dev deployment"
```

ArgoCD will auto-discover the new directory.

## Resource Usage

Typical resource consumption:
- API: 100m CPU, 256Mi RAM
- Account: 50m CPU, 128Mi RAM
- PostgreSQL: 250m CPU, 512Mi RAM
- Valkey: 100m CPU, 128Mi RAM
- Mailpit: 50m CPU, 50Mi RAM

**Total: ~550m CPU, ~1Gi RAM** (laptop-friendly)

## Development Workflow

1. Build and push images locally or use `:latest` tags
2. ArgoCD syncs changes automatically
3. Test email in Mailpit UI: http://mail.local.test
4. View logs: `kubectl logs -n monobase-dev -l app=api`

## Notes

- Uses `.local.test` domain (add to `/etc/hosts` if needed)
- Storage persists in k3d cluster (survives pod restarts)
- External Secrets disabled - use plain Secrets or SOPS
- Network policies disabled for easier testing
