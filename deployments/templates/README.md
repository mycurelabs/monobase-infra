# Configuration Profiles

This directory contains **base configuration profiles** that provide production-ready defaults for different environments and deployment sizes.

## Profile Types

### Environment Profiles (Recommended Starting Point)

| Profile | Use For | Key Characteristics |
|---------|---------|---------------------|
| `production-base.yaml` | All production deployments | HA, backups, security hardened, 2+ replicas |
| `staging-base.yaml` | Staging/UAT environments | Single replicas, Mailpit enabled, lower resources |
| `base.yaml` | Shared defaults | Gateway config, storage defaults, resource tiers |

### Size Profiles (Alternative Approach)

| Profile | Target Scale | Cluster Size | Monthly Cost |
|---------|--------------|--------------|--------------|
| `production-small.yaml` | 1-5 clients, <50k users, <500GB | 3 × m6i.xlarge (4 vCPU, 16GB) | ~$500-700 |
| `production-medium.yaml` | 5-20 clients, <200k users, <2TB | 5 × m6i.2xlarge (8 vCPU, 32GB) | ~$1500-2000 |
| `production-large.yaml` | 20+ clients, <1M users, <10TB | 10 × m6i.4xlarge (16 vCPU, 64GB) | ~$4000-5000 |

## Recommended Workflow

### Option 1: Copy Base Profile (Simplest, Most Maintainable)

**For Production:**
```bash
# 1. Copy the base profile
cp deployments/profiles/production-base.yaml deployments/myclient/values-production.yaml

# 2. Edit only what's different
vim deployments/myclient/values-production.yaml
# Change:
# - global.domain: myclient.com
# - global.namespace: myclient-prod
# - api.image.tag: "5.215.2" (pin version)
# - account.image.tag: "1.0.0" (pin version)
# - postgresql.persistence.size: 200Gi (if needed)

# 3. Delete sections you don't need to override
# Keep your config minimal (~60 lines instead of 430!)
```

**For Staging:**
```bash
cp deployments/profiles/staging-base.yaml deployments/myclient/values-staging.yaml
vim deployments/myclient/values-staging.yaml
# Change:
# - global.domain: staging.myclient.com
# - global.namespace: myclient-staging
```

**Result:**
- ✅ Production config: ~60 lines (vs 430 lines)
- ✅ Staging config: ~40 lines (vs 270 lines)
- ✅ Only document what's different from defaults
- ✅ Easier to maintain and review

### Option 2: Start from Size Profile

If your needs align with a specific size profile:

```bash
cp deployments/profiles/production-medium.yaml deployments/myclient/values-production.yaml
vim deployments/myclient/values-production.yaml
# Only change domain and namespace
```

## What to Override in Your Client Config

### Always Override (Required)
```yaml
global:
  domain: myclient.com
  namespace: myclient-prod
```

### Commonly Overridden (Recommended)
```yaml
# Pin specific versions
api:
  image:
    tag: "5.215.2"  # Not "latest"

account:
  image:
    tag: "1.0.0"

# Adjust database size
postgresql:
  persistence:
    size: 100Gi  # Based on actual data volume

# Scale for traffic
api:
  replicas: 3
  autoscaling:
    maxReplicas: 10
```

### Sometimes Overridden
```yaml
# Enable optional components
minio:
  enabled: true

monitoring:
  enabled: true

# Change storage provider
global:
  storage:
    provider: longhorn  # For on-premises

# Use different secrets provider
externalSecrets:
  provider: azure
```

## Inheritance Rules

Since Helm doesn't support YAML anchors across files, the pattern is:

1. **Copy** the base profile to your client config
2. **Delete** all sections you don't need to override
3. **Keep** only the values that differ from the base

This creates a small, maintainable config file that documents only what's special about this client.

## Example Comparison

### Before (Traditional Approach)
```yaml
# deployments/myclient/values-production.yaml (430 lines)
global:
  domain: myclient.com
  ...

api:
  enabled: true
  replicas: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2
      memory: 2Gi
  livenessProbe:
    enabled: true
    path: /health
    initialDelaySeconds: 30
    ...
  readinessProbe:
    enabled: true
    ...
  podDisruptionBudget:
    enabled: true
    minAvailable: 1
  autoscaling:
    enabled: true
    minReplicas: 2
    ...
  # ... 400 more lines of boilerplate
```

### After (Profile-Based Approach)
```yaml
# deployments/myclient/values-production.yaml (60 lines)
global:
  domain: myclient.com
  namespace: myclient-prod

api:
  image:
    tag: "5.215.2"  # Only override what's different

postgresql:
  persistence:
    size: 200Gi  # Larger than default 50Gi

# Everything else inherits from production-base.yaml
```

**Savings:** -370 lines (~86% reduction)

## Migration Guide

To migrate existing configs to use profiles:

```bash
# 1. Backup existing config
cp deployments/myclient/values-production.yaml deployments/myclient/values-production.yaml.backup

# 2. Start fresh from base profile
cp deployments/profiles/production-base.yaml deployments/myclient/values-production.yaml

# 3. Merge in your specific overrides
# Compare the backup file and add only what's different

# 4. Verify the config works
helm template api charts/api -f deployments/myclient/values-production.yaml

# 5. Delete the backup once verified
rm deployments/myclient/values-production.yaml.backup
```

## See Also

- `deployments/example.com/values-production-minimal.yaml` - Minimal production example (60 lines)
- `deployments/example.com/values-staging-minimal.yaml` - Minimal staging example (40 lines)
- `deployments/example.com/values-production.yaml` - Full reference config (430 lines)
- `helm-dependencies/*.yaml` - Database/service configuration options
- `charts/*/values.yaml` - All available chart options
