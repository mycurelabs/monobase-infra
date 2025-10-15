# Storage Operations Guide

Longhorn and MinIO storage management, expansion, and troubleshooting.

## Table of Contents

1. [Longhorn Operations](#longhorn-operations)
2. [MinIO Operations](#minio-operations)
3. [Volume Expansion](#volume-expansion)
4. [Storage Monitoring](#storage-monitoring)
5. [Troubleshooting](#troubleshooting)

---

## Longhorn Operations

### Access Longhorn UI

```bash
# Port-forward to Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Open browser
open http://localhost:8080
```

### Check Storage Status

```bash
# List all volumes
kubectl get volumes -n longhorn-system

# Check volume details
kubectl describe volume pvc-<uuid> -n longhorn-system

# Check node storage
kubectl get nodes -n longhorn-system \\
  -o custom-columns=NAME:.metadata.name,STORAGE:.status.conditions[?(@.type==\"Ready\")].status
```

### Manual Snapshot

```bash
# Create snapshot via kubectl
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: postgresql-manual-snapshot
  namespace: longhorn-system
spec:
  volume: pvc-postgresql-data
  labels:
    snapshot-type: manual
EOF

# Or via Longhorn UI:
# Volumes → Select volume → Create Snapshot
```

### Manual Backup to S3

```bash
# Trigger backup via Longhorn UI
# Volumes → Select volume → Create Backup

# Or via kubectl
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: postgresql-manual-backup
  namespace: longhorn-system
spec:
  snapshotName: postgresql-manual-snapshot
  labels:
    backup-type: manual
EOF
```

### Restore from Backup

```bash
# Via Longhorn UI:
# 1. Backup tab → Select backup → Restore
# 2. Choose: Create new volume or restore to existing

# Via kubectl (create new volume from backup):
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: postgresql-restored
  namespace: longhorn-system
spec:
  fromBackup: s3://bucket/backups/backup-<id>
  numberOfReplicas: 3
  size: "100Gi"
EOF

# Create PVC for restored volume
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-data-restored
  namespace: myclient-prod
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  volumeName: postgresql-restored
EOF
```

---

## MinIO Operations

### Access MinIO Console

```bash
# Port-forward to MinIO console
kubectl port-forward -n myclient-prod svc/minio 9001:9001

# Get credentials
MINIO_USER=$(kubectl get secret minio-credentials -n myclient-prod \\
  -o jsonpath='{.data.root-user}' | base64 -d)
MINIO_PASS=$(kubectl get secret minio-credentials -n myclient-prod \\
  -o jsonpath='{.data.root-password}' | base64 -d)

echo "URL: http://localhost:9001"
echo "User: $MINIO_USER"
echo "Pass: $MINIO_PASS"
```

### MinIO CLI (mc) Operations

```bash
# Install mc client
brew install minio/stable/mc

# Configure alias
mc alias set myminio https://storage.myclient.com <access-key> <secret-key>

# List buckets
mc ls myminio

# Create bucket
mc mb myminio/new-bucket

# Set bucket policy (public read)
mc policy set download myminio/api-files

# Monitor usage
mc admin info myminio

# Check healing status
mc admin heal myminio
```

### MinIO Bucket Management

```bash
# Create bucket with versioning
mc mb myminio/versioned-bucket
mc version enable myminio/versioned-bucket

# Set lifecycle policy (auto-delete old versions)
mc ilm add --expiry-days 90 myminio/versioned-bucket

# Set encryption
mc encrypt set sse-s3 myminio/encrypted-bucket

# Monitor bucket usage
mc du myminio/api-files
```

---

## Volume Expansion

### Expand StatefulSet PVC (PostgreSQL, MinIO)

**Automated Script:**

```bash
# See: scripts/resize-statefulset-storage.sh (Phase 6)
./scripts/resize-statefulset-storage.sh \\
  postgresql \\
  myclient-prod \\
  200Gi
```

**Manual Process:**

```bash
# 1. Check current size
kubectl get pvc -n myclient-prod

# 2. Edit each PVC (for StatefulSet, edit ALL PVCs)
kubectl edit pvc postgresql-data-postgresql-0 -n myclient-prod
# Change: storage: 100Gi → 200Gi

kubectl edit pvc postgresql-data-postgresql-1 -n myclient-prod
kubectl edit pvc postgresql-data-postgresql-2 -n myclient-prod

# 3. Delete StatefulSet (keeps pods running!)
kubectl delete statefulset postgresql -n myclient-prod --cascade=orphan

# 4. Re-create StatefulSet with new size
# Edit helm values or redeploy via ArgoCD

# 5. Rolling restart to use new size
kubectl rollout restart statefulset postgresql -n myclient-prod

# 6. Verify expansion
kubectl get pvc -n myclient-prod
df -h  # Inside pod
```

### Expand Regular PVC (Simple)

```bash
# 1. Edit PVC
kubectl edit pvc my-pvc -n myclient-prod
# Change storage size

# 2. Longhorn expands automatically
# No pod restart needed!

# 3. Verify
kubectl get pvc my-pvc -n myclient-prod
```

---

## Storage Monitoring

### Longhorn Metrics

```bash
# Via Prometheus (if monitoring enabled)
# Metrics available:
# - longhorn_volume_actual_size_bytes
# - longhorn_volume_capacity_bytes
# - longhorn_volume_state
# - longhorn_volume_robustness
# - longhorn_node_storage_capacity_bytes
# - longhorn_node_storage_usage_bytes

# Check via Grafana dashboard
# Or query Prometheus directly
```

### Storage Alerts

**Configure in Prometheus:**

```yaml
# See: infrastructure/monitoring/prometheus-rules.yaml

# Alerts:
- PersistentVolumeFillingUp (>80% full)
- LonghornVolumeUnhealthy (degraded)
- MinIODiskOffline
- MinIOHighStorage (>80% used)
```

### Manual Storage Checks

```bash
# Check PVC usage
kubectl exec -it postgresql-0 -n myclient-prod -- df -h

# Check Longhorn node storage
kubectl get nodes.longhorn.io -n longhorn-system \\
  -o custom-columns=NAME:.metadata.name,CAPACITY:.status.diskStatus.*.storageMaximum,USED:.status.diskStatus.*.storageAvailable

# Check MinIO usage
mc du --depth 1 myminio
```

---

## Troubleshooting

### Longhorn Issues

**Volume Degraded:**

```bash
# Check replica status
kubectl describe volume pvc-<id> -n longhorn-system

# Common causes:
# - Node down (replicas rebuilding)
# - Disk full (add storage or clean up)
# - Network issues (check node connectivity)

# Force rebuild
# Via Longhorn UI: Volume → Replica → Rebuild
```

**Backup Failed:**

```bash
# Check backup target
kubectl get settings.longhorn.io backup-target -n longhorn-system -o yaml

# Check credentials
kubectl get secret longhorn-backup-credentials -n longhorn-system

# Check S3 bucket access
aws s3 ls s3://myclient-prod-backups/longhorn/

# Test manual backup
# Longhorn UI → Volume → Create Backup
```

**Snapshot Failed:**

```bash
# Check recurring job
kubectl get recurringjobs -n longhorn-system

# Check job logs
kubectl logs -l app=longhorn-manager -n longhorn-system | grep snapshot

# Common issues:
# - Snapshot space limit (increase snapshot-space-usage-limit)
# - Too many snapshots (adjust retain count)
```

### MinIO Issues

**Disk Offline:**

```bash
# Check MinIO pods
kubectl get pods -n myclient-prod -l app.kubernetes.io/name=minio

# Check PVCs
kubectl get pvc -n myclient-prod -l app.kubernetes.io/name=minio

# Healing status
mc admin heal myminio

# Common causes:
# - PVC not bound (check storage class)
# - Node down (pods rescheduling)
# - Disk full (expand PVCs)
```

**Performance Issues:**

```bash
# Check MinIO metrics
mc admin info myminio

# Increase replicas (more nodes)
# Or increase resources per node

# Check network (MinIO is network-intensive)
kubectl exec -it minio-0 -n myclient-prod -- \\
  iperf3 -c minio-1.minio.myclient-prod.svc.cluster.local
```

---

## Best Practices

### 1. Regular Maintenance

**Weekly:**
- Review storage usage
- Check for degraded volumes
- Verify backups completing

**Monthly:**
- Test backup restore
- Clean up old snapshots
- Review storage capacity planning

**Quarterly:**
- Audit storage access
- Review encryption keys
- Performance tuning

### 2. Capacity Planning

**Monitor Growth:**

```bash
# Track storage usage over time
# Via Grafana dashboard

# Estimate growth rate
# Plan expansion when >70% full

# PostgreSQL: Plan for 2x growth per year
# MinIO: Plan based on file upload rate
```

**Expansion Triggers:**
- >70% used: Plan expansion
- >80% used: Execute expansion
- >90% used: Emergency expansion

### 3. Performance Optimization

**Longhorn:**
- Use `dataLocality: best-effort` for performance
- Use SSD disks for production
- Increase `storageOverProvisioningPercentage` for burst

**MinIO:**
- More nodes = better performance
- Use SSD for cache
- Enable compression (reduces storage)
- Use CDN for public files

---

## Storage Cost Optimization

### Longhorn

**Reduce Costs:**
- Use 2 replicas for non-critical data (instead of 3)
- Clean up old snapshots automatically
- Use compression (if supported)
- Archive old data to S3

### MinIO

**Reduce Costs:**
- **Consider external S3 if:**
  - >1TB data (economies of scale)
  - Global distribution needed
  - CDN integration required

- **Keep self-hosted MinIO if:**
  - <1TB data (cost-effective)
  - No egress fees
  - Full control needed
  - Compliance requires on-prem

**MinIO Lifecycle Policies:**

```bash
# Auto-delete old files
mc ilm add --expiry-days 365 myminio/temporary-files

# Transition to S3 Standard-IA
# (requires external S3 replication)
```

---

## Summary

**Longhorn:**
- Distributed block storage
- 3x replication for HA
- Snapshots + S3 backups
- Online expansion
- Encryption support

**MinIO:**
- S3-compatible object storage
- Erasure coding (EC:2)
- 6 nodes for 1TB usable
- Self-hosted or external S3
- Presigned URLs via Gateway

**Operations:**
- Regular monitoring
- Capacity planning
- Backup verification
- Performance tuning
- Security audits

For backup procedures, see [BACKUP-RECOVERY.md](BACKUP-RECOVERY.md).
