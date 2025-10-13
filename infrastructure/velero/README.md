# Velero Kubernetes Backup Solution

Velero provides Kubernetes-native backup and restore for disaster recovery.

## Why Velero?

✅ **Application-Aware** - Backs up K8s resources + volumes together
✅ **One-Command Restore** - Simple restore from backup
✅ **CNCF Project** - Industry standard, well-maintained
✅ **Cluster Migration** - Can restore to different cluster
✅ **Incremental Backups** - Only changed data (efficient)

## 3-Tier Backup Strategy

1. **Tier 1: Hourly** - Fast recovery (72h retention)
2. **Tier 2: Daily** - Medium recovery (30d retention)
3. **Tier 3: Weekly** - Long-term archive (90d retention)

## Installation

```bash
# Install Velero CLI
brew install velero  # macOS
# Or download from https://velero.io/docs/main/basic-install/

# Install Velero server
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \\
  --namespace velero \\
  --create-namespace \\
  --values helm-values.yaml
```

## Files

- `helm-values.yaml` - Velero configuration
- `backup-schedules/hourly-critical.yaml` - Hourly backups
- `backup-schedules/daily-full.yaml` - Daily full backups
- `backup-schedules/weekly-archive.yaml` - Weekly archives
- `restore-examples.yaml` - Restore procedures

## Backup Commands

```bash
# Create on-demand backup
velero backup create my-backup --include-namespaces client-prod

# List backups
velero backup get

# Restore from backup
velero restore create --from-backup daily-20250115

# Schedule automatic backups
kubectl apply -f backup-schedules/daily-full.yaml
```

## Integration

Velero integrates with:
- **Longhorn** - CSI snapshots for PVCs
- **External Secrets** - Credentials from KMS
- **S3** - Backup storage (encrypted)
- **Monitoring** - Prometheus metrics and alerts

## Phase 3 Implementation

Full implementation includes:
- Complete backup schedules (hourly/daily/weekly)
- S3 backup target with encryption
- Velero Node Agent for CSI snapshots
- Integration with External Secrets for credentials
- Monitoring and alerting for backup failures
- Restore testing procedures
