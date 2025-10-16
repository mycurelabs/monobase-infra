# Example Staging Deployment

Reference configuration for staging/testing monobase deployment.

## Overview

This is a **complete reference example** for staging environments. Copy this as a starting point for your own staging/testing deployments.

## Key Features

- Single replica deployments (lower cost, faster iteration)
- Reduced resource requirements vs. production
- PostgreSQL standalone mode (no replication)
- Valkey with no persistence (ephemeral cache)
- Mailpit enabled for email testing
- Backup disabled by default
- Security policies enabled (test production settings)

## Quick Start

To create your own staging deployment:

```bash
# 1. Copy this directory
cp -r deployments/example-staging deployments/myclient-staging

# 2. Customize configuration
cd deployments/myclient-staging
vim values.yaml

# Required changes:
# - global.domain: staging.example.com → staging.yourclient.com
# - global.namespace: example-staging → myclient-staging
# - argocd.repoURL: YOUR-ORG/monobase-infra.git
# - image tags: use "latest" or branch builds for testing

# 3. Commit and push
git add deployments/myclient-staging/
git commit -m "Add myclient staging deployment"
git push
```

ArgoCD will auto-discover the new deployment from the `deployments/` directory.

## Configuration Highlights

### Optimized for Testing

Staging environment uses:

- **Single replicas** (API, Account, PostgreSQL)
- **Lower resource limits** (~50% of production)
- **Smaller storage** (20Gi PostgreSQL vs. 50Gi prod)
- **No persistence for Valkey** (faster cleanup)
- **Always pull images** (test latest builds)

### Email Testing

Mailpit is enabled by default:

```yaml
mailpit:
  enabled: true
  gateway:
    hostname: mail.{global.domain}
```

Access at: `http://mail.staging.example.com`

### Image Tags

Use `latest` or branch builds for rapid testing:

```yaml
api:
  image:
    tag: "latest"
    pullPolicy: Always  # Always pull for staging
```

## Resource Requirements

Estimated minimum cluster resources:

- **CPU**: ~2 vCPU (API: 1, PostgreSQL: 1, Account: 0.5, Valkey: 0.25)
- **Memory**: ~4GB (API: 2Gi, PostgreSQL: 4Gi, Account: 512Mi, Valkey: 256Mi)
- **Storage**: ~20GB (PostgreSQL only, Valkey ephemeral)

About 50% of production resource requirements.

## Testing Workflow

1. **Deploy feature branches** using `latest` or branch-specific tags
2. **Test email flows** via Mailpit UI
3. **Verify database migrations** in standalone PostgreSQL
4. **Validate configurations** before promoting to production
5. **Test API integrations** with realistic data

## Security Testing

Staging mirrors production security settings:

- **NetworkPolicies**: Enabled (test connectivity rules)
- **Pod Security Standards**: Restricted (validate compliance)
- **TLS**: Automatic via cert-manager

Optional tools are disabled by default to save resources:

```yaml
security:
  kyverno.enabled: false   # Disable unless testing policies
  falco.enabled: false     # Disable unless testing runtime security
```

## Differences from Production

| Feature | Staging | Production |
|---------|---------|------------|
| Replicas | 1 | 2-3 |
| Resources | ~50% | 100% |
| PostgreSQL | Standalone | Replication |
| Valkey persistence | Disabled | Enabled |
| Mailpit | Enabled | **NEVER** |
| Backup | Disabled | Enabled |
| Monitoring | Disabled | Optional |

## Next Steps

1. ✅ Copy this directory to `deployments/yourclient-staging/`
2. ✅ Update domain and namespace
3. ✅ Configure for your testing workflow
4. ✅ Commit and push to your fork
5. ✅ ArgoCD will auto-deploy the new application

See [DEPLOYMENT.md](../../docs/getting-started/DEPLOYMENT.md) for detailed instructions.
