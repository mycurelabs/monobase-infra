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

### GitOps Deployment (Recommended)

Velero is deployed via ArgoCD along with all other infrastructure. **No manual installation required.**

Velero is **always enabled** for all environments because backups are critical for disaster recovery.

#### Deployment Flow

1. **Render templates:**
   ```bash
   helm template myclient charts/monobase \
     -f deployments/yourclient/values-production.yaml \
     --output-dir rendered/myclient-prod
   ```

2. **Deploy via ArgoCD:**
   ```bash
   kubectl apply -f rendered/myclient-prod/monobase/templates/root-app.yaml
   ```

3. **Verify deployment:**
   ```bash
   # Check Velero controller
   kubectl get pods -n velero

   # Check backup schedules
   velero schedule get
   ```

#### Sync Waves

Velero deploys automatically:

- **Wave 1:** Velero controller (cluster-wide, once per cluster)
- **Wave 2:** Per-client backup schedules (from API chart)

ArgoCD ensures the controller is ready before creating schedules.

### Per-Client Configuration

Configure backup settings in your client values file:

```yaml
# deployments/myclient/values-production.yaml
backup:
  enabled: true  # Usually true for production
  provider: aws  # Options: aws, azure, gcp
  bucket: myclient-prod-backups  # Unique per client
  region: us-east-1
  credentialSecret: velero-credentials  # From External Secrets

  encryption:
    enabled: true
    type: AES256
    kmsKeyId: arn:aws:kms:us-east-1:123456789012:key/abc123

  schedules:
    daily:
      enabled: true
      schedule: "0 2 * * *"  # 2 AM daily
      retention: 720h  # 30 days

    hourly:
      enabled: false  # Optional for RPO <1 day
      schedule: "0 * * * *"
      retention: 72h

    weekly:
      enabled: false  # Optional for compliance
      schedule: "0 3 * * 0"  # Sunday 3 AM
      retention: 2160h  # 90 days
```

When ArgoCD syncs the API chart, Velero schedules are automatically created in the `velero` namespace.

### Velero CLI Installation

Install the CLI for manual operations:

```bash
# macOS
brew install velero

# Linux
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xvf velero-v1.13.0-linux-amd64.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/

# Verify
velero version
```

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
