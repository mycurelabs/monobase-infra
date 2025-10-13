# Longhorn Distributed Block Storage

Longhorn provides distributed block storage for StatefulSets (MongoDB, MinIO, Typesense).

## Features

- **3x Replication** - Data replicated across 3 nodes by default
- **Snapshots** - Automatic hourly/daily snapshots
- **Encryption** - Volume encryption at rest
- **Backup** - S3/NFS backup target support
- **Expansion** - Online volume expansion without downtime

## Installation

```bash
# Add Longhorn Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install Longhorn
helm install longhorn longhorn/longhorn \\
  --namespace longhorn-system \\
  --create-namespace \\
  --values helm-values.yaml
```

## Files

- `helm-values.yaml` - Longhorn Helm chart configuration
- `storageclass.yaml` - Encrypted StorageClass with 3-replica policy
- `backup-config.yaml` - Backup target and recurring backup configuration

## Post-Installation

1. Access Longhorn UI: `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80`
2. Configure backup target (S3 or NFS)
3. Verify StorageClass: `kubectl get storageclass longhorn`

## Phase 3 Implementation

Full implementation includes:
- Complete Helm values configuration
- Encrypted StorageClass
- Backup schedules and retention policies
- Integration with Velero for K8s backups
