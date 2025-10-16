# Example Production Deployment

Reference configuration for production monobase deployment.

## Overview

This is a **complete reference example** showing all production configuration options. Copy this as a starting point for your own production deployments.

## Key Features

- High availability (2+ replicas for critical services)
- Production resource limits and requests
- PostgreSQL replication (1 primary + 1 replica)
- Valkey (Redis) with persistence
- Backup enabled with Velero
- Security hardening (NetworkPolicies, PSS restricted)
- Optional: Kyverno and Falco (disabled by default)

## Quick Start

To create your own production deployment:

```bash
# 1. Copy this directory
cp -r deployments/example-prod deployments/myclient-prod

# 2. Customize configuration
cd deployments/myclient-prod
vim values.yaml

# Required changes:
# - global.domain: example.com → yourclient.com
# - global.namespace: example-prod → myclient-prod
# - argocd.repoURL: YOUR-ORG/monobase-infra.git
# - image tags: "latest" → specific versions (e.g., "5.215.2")
# - backup.bucket: "" → "myclient-prod-backups"
# - backup.region: "" → "us-east-1" (or your region)

# 3. Commit and push
git add deployments/myclient-prod/
git commit -m "Add myclient production deployment"
git push
```

ArgoCD will auto-discover the new deployment from the `deployments/` directory.

## Configuration Highlights

### Minimal Changes Needed

Most settings have sensible defaults. You only need to change:

1. **Domain and namespace** (lines 6-7)
2. **Git repository URL** (line 22)
3. **Image tags** (pin specific versions, not "latest")
4. **Backup bucket and region** (lines 178-179)

### Optional Components

```yaml
# MinIO (object storage)
minio.enabled: false  # Use cloud S3 by default

# Monitoring
monitoring.enabled: false  # Enable when needed

# Security tools
security.kyverno.enabled: false   # Enable for policy enforcement
security.falco.enabled: false     # Enable for runtime security
```

## Resource Requirements

Estimated minimum cluster resources:

- **CPU**: ~4 vCPU (API: 2, PostgreSQL: 2, Account: 0.5, Valkey: 0.5)
- **Memory**: ~8GB (API: 2Gi, PostgreSQL: 4Gi, Account: 512Mi, Valkey: 1Gi)
- **Storage**: ~60GB (PostgreSQL: 50Gi, Valkey: 8Gi)

Scale up based on traffic and data volume.

## Security

Production security is enabled by default:

- **NetworkPolicies**: Default deny, explicit allow rules
- **Pod Security Standards**: Restricted level
- **TLS**: Automatic via cert-manager
- **Secrets**: Managed by External Secrets Operator

Optional security tools (enable as needed):

- **Kyverno**: Policy enforcement (multi-team environments)
- **Falco**: Runtime security monitoring (compliance requirements)

## Backup Strategy

Daily backups enabled by default:

```yaml
backup:
  schedules:
    daily:
      enabled: true
      schedule: "0 2 * * *"  # 2 AM daily
      retention: 720h        # 30 days
```

Optional: Enable hourly or weekly schedules for stricter RPO/compliance.

## High Availability

Production uses HA configuration:

- **API**: 2 replicas + autoscaling (2-5 pods)
- **Account**: 2 replicas
- **PostgreSQL**: 1 primary + 1 replica
- **Valkey**: Master-replica architecture

## Next Steps

1. ✅ Copy this directory to `deployments/yourclient-prod/`
2. ✅ Update domain, namespace, and image tags
3. ✅ Configure backup bucket and region
4. ✅ Commit and push to your fork
5. ✅ ArgoCD will auto-deploy the new application

See [DEPLOYMENT.md](../../docs/getting-started/DEPLOYMENT.md) for detailed instructions.
