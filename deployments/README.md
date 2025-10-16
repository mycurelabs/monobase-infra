# Deployment Configurations

Client deployment configurations for Monobase infrastructure.

## Overview

This directory contains **deployment values files** for each client/environment combination.

**What's here:** Client-specific configuration (what you deploy)  
**What deploys you:** Helm charts in `../charts/` (implementation)  
**GitOps:** ArgoCD auto-discovers and deploys from this directory

## Quick Start

### Create New Deployment

```bash
# 1. Create deployment directory
mkdir -p deployments/myclient-prod

# 2. Copy example configuration
cp deployments/example-prod/values.yaml deployments/myclient-prod/values.yaml

# 3. Edit configuration
vim deployments/myclient-prod/values.yaml

# 4. Commit and push (GitOps auto-deploys)
git add deployments/myclient-prod/
git commit -m "feat: add myclient production deployment"
git push
```

ArgoCD automatically discovers and deploys new configurations within minutes.

## Directory Structure

```
deployments/
├── example-prod/       # Production reference config
├── example-staging/    # Staging reference config
├── example-k3d/        # Local k3d reference config
├── myclient-prod/      # Your production deployment
├── myclient-staging/   # Your staging deployment
└── README.md           # This file
```

Each deployment directory contains:
- `values.yaml` - Complete configuration for that environment

## Configuration Guide

### Environment Types

**Production (`*-prod`):**
- HA enabled (3+ replicas)
- Autoscaling enabled
- Backups enabled
- Monitoring recommended
- Pin specific versions

**Staging (`*-staging`):**
- Minimal resources (1-2 replicas)
- Testing latest versions
- Optional backups
- Cost-optimized

**Development/k3d (`*-k3d`, `*-dev`):**
- Minimal config for local testing
- Uses local-path storage
- Mailpit for email testing

---

## Core Parameters

### ArgoCD GitOps Configuration

Required for GitOps auto-discovery.

#### argocd.repoURL
- **Type:** string
- **Required:** Yes
- **Example:** `https://github.com/YOUR-ORG/monobase-infra.git`
- **Description:** Git repository URL for GitOps

#### argocd.targetRevision
- **Type:** string
- **Default:** `main`
- **Options:** `main`, `staging`, specific branch/tag
- **Description:** Branch to deploy from

---

## External Secrets Configuration

Syncs secrets from cloud KMS to Kubernetes.

### externalSecrets.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable External Secrets Operator for KMS integration

### externalSecrets.provider
- **Type:** string
- **Required:** Yes
- **Options:** `aws`, `azure`, `gcp`, `sops`
- **Description:** KMS provider

### externalSecrets.aws.region
- **Type:** string
- **Example:** `us-east-1`
- **Description:** AWS region for Secrets Manager

### externalSecrets.aws.secretStore
- **Type:** string
- **Example:** `myclient-prod-secretstore`
- **Description:** SecretStore resource name

### externalSecrets.azure.vaultUrl
- **Type:** string
- **Example:** `https://myclient-kv.vault.azure.net/`
- **Description:** Azure Key Vault URL

### externalSecrets.gcp.projectId
- **Type:** string
- **Example:** `myclient-prod-123456`
- **Description:** GCP project ID

---

## Network Policy Configuration

Zero-trust networking for production security.

### networkPolicies.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (recommended for security and compliance)
- **Description:** Enable NetworkPolicies for zero-trust networking

### networkPolicies.defaultDeny
- **Type:** boolean
- **Default:** `true`
- **Description:** Default-deny all traffic (explicit allow rules required)

---

## Pod Security Configuration

Enforce Pod Security Standards for compliance.

### podSecurityStandards.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (required)
- **Description:** Enable Pod Security Standards enforcement

### podSecurityStandards.level
- **Type:** string
- **Default:** `restricted`
- **Options:** `privileged`, `baseline`, `restricted`
- **Production:** `restricted` (highest security)
- **Description:** Pod Security Standards enforcement level

---

## Monitoring Configuration

Prometheus, Grafana, and alerting.

### monitoring.enabled
- **Type:** boolean
- **Default:** `false`
- **Production:** `true` (recommended)
- **Staging:** `false` (to save resources)
- **Description:** Enable monitoring stack

### monitoring.prometheus.retention
- **Type:** string
- **Default:** `15d`
- **Description:** Metrics retention period

### monitoring.prometheus.storage
- **Type:** string
- **Default:** `50Gi`
- **Description:** Prometheus PVC size

### monitoring.grafana.enabled
- **Type:** boolean
- **Default:** `false`
- **Production:** `true`
- **Description:** Enable Grafana dashboards

---

## Backup Configuration

Velero backups to S3-compatible storage.

### backup.enabled
- **Type:** boolean
- **Default:** `false`
- **Production:** `true` (critical for production)
- **Description:** Enable Velero backups

### backup.s3Bucket
- **Type:** string
- **Example:** `myclient-prod-backups`
- **Description:** S3 bucket for Velero backups

### backup.region
- **Type:** string
- **Example:** `us-east-1`
- **Description:** Cloud region for backup storage

### backup.schedules.hourly.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Hourly backups (72h retention)

### backup.schedules.daily.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Daily backups (30d retention)

### backup.schedules.weekly.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Weekly archives (90d retention for compliance)

---

## Compliance Configuration

Audit logging and encryption for regulated industries.

### compliance.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (for regulated industries)
- **Description:** Enable compliance features

### compliance.auditLogging.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable audit logging

### compliance.auditLogging.retention
- **Type:** string
- **Default:** `2555d` (7 years)
- **Description:** Audit log retention period

### compliance.encryption.atRest
- **Type:** string
- **Default:** `required`
- **Options:** `required`, `optional`
- **Description:** Encrypt data at rest

### compliance.encryption.inTransit
- **Type:** string
- **Default:** `required`
- **Description:** Encrypt data in transit (TLS)

---

## Configuration Examples

### Minimal Staging Configuration

```yaml
global:
  domain: myclient.com
  namespace: myclient-staging
  environment: staging

argocd:
  repoURL: https://github.com/YOUR-ORG/monobase-infra.git
  targetRevision: staging

api:
  enabled: true
  replicaCount: 1
  image:
    tag: "latest"

postgresql:
  enabled: true
  replicaCount: 1
  persistence:
    size: 20Gi

externalSecrets:
  enabled: true
  provider: aws
  aws:
    region: us-east-1

monitoring:
  enabled: false

backup:
  enabled: false
```

### Production HA Configuration

```yaml
global:
  domain: myclient.com
  namespace: myclient-prod
  environment: production

argocd:
  repoURL: https://github.com/YOUR-ORG/monobase-infra.git
  targetRevision: main

api:
  enabled: true
  replicaCount: 3
  image:
    tag: "5.215.2"  # Pin version
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10

postgresql:
  enabled: true
  architecture: replicaset
  replicaCount: 3
  persistence:
    size: 100Gi

externalSecrets:
  enabled: true
  provider: aws
  aws:
    region: us-east-1
    secretStore: myclient-prod-secretstore

monitoring:
  enabled: true
  prometheus:
    retention: 30d
    storage: 100Gi
  grafana:
    enabled: true

backup:
  enabled: true
  s3Bucket: myclient-prod-backups
  region: us-east-1
  schedules:
    daily:
      enabled: true
    weekly:
      enabled: true

networkPolicies:
  enabled: true
  defaultDeny: true

podSecurityStandards:
  enabled: true
  level: restricted

compliance:
  enabled: true
  auditLogging:
    enabled: true
    retention: 2555d
```

---

## Related Documentation

- **[../charts/README.md](../charts/README.md)** - Global parameters and chart overview
- **[../charts/api/README.md](../charts/api/README.md)** - API-specific parameters
- **[../charts/account/README.md](../charts/account/README.md)** - Account frontend parameters
- **[../docs/getting-started/CLIENT-ONBOARDING.md](../docs/getting-started/CLIENT-ONBOARDING.md)** - Client onboarding guide
- **[../docs/operations/BACKUP_DR.md](../docs/operations/BACKUP_DR.md)** - Backup and recovery procedures
- **[../docs/operations/MONITORING.md](../docs/operations/MONITORING.md)** - Monitoring setup
- **[../docs/security/SECURITY-HARDENING.md](../docs/security/SECURITY-HARDENING.md)** - Security best practices

## Next Steps

1. **Copy:** Start from `example-prod/` or `example-staging/`
2. **Configure:** Edit values for your client
3. **Commit:** Push to Git for GitOps deployment
4. **Monitor:** Check ArgoCD for deployment status
