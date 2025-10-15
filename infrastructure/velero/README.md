# Velero Kubernetes Backup Solution

Velero provides Kubernetes-native backup and restore for disaster recovery.

## Architecture

**Cluster-Wide Installation:**
- Velero controller runs once per cluster in the `velero` namespace
- Single Velero instance backs up multiple client namespaces
- No per-client Velero installations needed

**Per-Client Configuration:**
- Backup schedules configured in each client's Helm values
- Storage locations (S3 buckets) unique per client
- Schedules deployed as Kubernetes `Schedule` resources in `velero` namespace
- Template: `charts/api/templates/velero-schedules.yaml`

## Why Velero?

✅ **Application-Aware** - Backs up K8s resources + volumes together
✅ **One-Command Restore** - Simple restore from backup
✅ **CNCF Project** - Industry standard, well-maintained
✅ **Cluster Migration** - Can restore to different cluster
✅ **Incremental Backups** - Only changed data (efficient)

## 3-Tier Backup Strategy

1. **Tier 1: Hourly** - Fast recovery (72h retention)
2. **Tier 2: Daily** - Standard recovery (30d retention)
3. **Tier 3: Weekly** - Long-term archive (90d retention)

## Installation

### One-Time Cluster Setup

```bash
# Install Velero CLI
brew install velero  # macOS
# Or download from https://velero.io/docs/main/basic-install/

# Install Velero server (once per cluster)
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values helm-values.yaml
```

### Per-Client Configuration

Configure backup settings in your client values file:

```yaml
# config/myclient/values-production.yaml
backup:
  enabled: true
  provider: aws
  bucket: myclient-prod-backups
  region: us-east-1

  encryption:
    enabled: true
    type: AES256
    kmsKeyId: arn:aws:kms:us-east-1:123456789012:key/abc123

  schedules:
    hourly:
      enabled: true
      schedule: "0 * * * *"
      retention: 72h

    daily:
      enabled: true
      schedule: "0 2 * * *"
      retention: 720h

    weekly:
      enabled: false
```

When you deploy the API chart, Velero schedules are automatically created.

## Files

- `helm-values.yaml` - Cluster-wide Velero controller configuration
- Client backup schedules defined in `charts/api/templates/velero-schedules.yaml`

## Backup Commands

```bash
# List all backups (all clients)
velero backup get

# List backups for specific client
velero backup get -l client=myclient-prod

# Create on-demand backup
velero backup create myclient-manual-$(date +%Y%m%d) \
  --include-namespaces myclient-prod \
  --snapshot-volumes \
  --default-volumes-to-fs-backup

# Restore from backup
velero restore create --from-backup myclient-prod-daily-20250115020000

# Restore to different namespace (DR)
velero restore create --from-backup myclient-prod-daily-20250115020000 \
  --namespace-mappings myclient-prod:myclient-dr
```

## Integration

Velero integrates with:
- **Storage Providers** - AWS S3, Azure Blob, GCP GCS, MinIO
- **CSI Drivers** - Longhorn, EBS, Azure Disk, GCP PD snapshots
- **External Secrets** - Credentials from cloud KMS
- **Monitoring** - Prometheus metrics and alerts
