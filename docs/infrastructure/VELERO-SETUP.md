# Velero Backup and Disaster Recovery Setup

## Overview

Velero provides backup and disaster recovery for Kubernetes clusters. This infrastructure uses **two complementary backup strategies**:

### Cluster-Level Backups (Infrastructure Layer)
**What:** Backs up infrastructure namespaces and cluster resources  
**Where:** Configured in `infrastructure/velero/`  
**Managed by:** GitOps (ArgoCD)  
**Use case:** Disaster recovery - restore entire cluster infrastructure

### Per-Application Backups (Application Layer)
**What:** Backs up individual tenant namespaces  
**Where:** Configured in application Helm charts (e.g., `charts/api/templates/velero-schedules.yaml`)  
**Managed by:** Application deployments  
**Use case:** Tenant-specific restore or point-in-time recovery

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Velero Operator                          │
│                   (Sync Wave 0)                             │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
        ┌───────▼────────┐         ┌────────▼────────┐
        │ Infrastructure │         │  Per-App Backup │
        │    Backups     │         │    Schedules    │
        │  (Wave 1)      │         │  (App Charts)   │
        └───────┬────────┘         └────────┬────────┘
                │                           │
        ┌───────▼────────────────┐  ┌──────▼─────────────┐
        │ - cert-manager         │  │ - mycure-prod      │
        │ - envoy-gateway-system │  │ - client-xyz       │
        │ - external-secrets     │  │ - tenant-abc       │
        │ - monitoring           │  │   (per namespace)  │
        │ - argocd              │  │                    │
        │ - velero               │  │                    │
        │ + Cluster Resources    │  │                    │
        │   (CRDs, StorageClass) │  │                    │
        └────────────────────────┘  └────────────────────┘
```

---

## Prerequisites

### 1. Cloud Identity Already Configured ✅

Terraform modules automatically provision cloud identities for Velero:

- **AWS EKS**: IRSA role created (no static credentials needed)
- **Azure AKS**: Workload Identity created (no static credentials needed)
- **GCP GKE**: Service Account created (no static credentials needed)

Check your terraform outputs:
```bash
terraform output | grep velero
```

### 2. Create Backup Storage

**Terraform does NOT create storage buckets/containers** - you must create them manually:

#### AWS S3
```bash
# Create S3 bucket
aws s3 mb s3://my-cluster-velero-backups --region us-east-1

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket my-cluster-velero-backups \
  --versioning-configuration Status=Enabled

# Enable encryption (recommended)
aws s3api put-bucket-encryption \
  --bucket my-cluster-velero-backups \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

#### Azure Blob Storage
```bash
# Create storage account
az storage account create \
  --name myclustervelero \
  --resource-group my-cluster-rg \
  --location eastus \
  --sku Standard_GRS

# Create blob container
az storage container create \
  --name velero-backups \
  --account-name myclustervelero
```

#### GCP Cloud Storage
```bash
# Create GCS bucket
gsutil mb -l us-central1 gs://my-cluster-velero-backups

# Enable versioning (recommended)
gsutil versioning set on gs://my-cluster-velero-backups
```

#### DigitalOcean Spaces
```bash
# Create via doctl
doctl compute space create my-cluster-velero-backups --region nyc3

# Or via web UI: https://cloud.digitalocean.com/spaces
```

---

## Configuration

### Step 1: Update `argocd/infrastructure/values.yaml`

```yaml
velero:
  enabled: true
  provider: aws  # Options: aws, azure, gcp, digitalocean, minio
  
  # AWS Configuration
  aws:
    region: us-east-1
    bucket: my-cluster-velero-backups
    roleArn: ""  # Leave empty - auto-populated from terraform
  
  # Azure Configuration (if using Azure)
  azure:
    resourceGroup: my-cluster-rg
    storageAccount: myclustervelero
    blobContainer: velero-backups
    identityClientId: ""  # Leave empty - auto-populated from terraform
  
  # GCP Configuration (if using GCP)
  gcp:
    bucket: my-cluster-velero-backups
    projectId: my-gcp-project
    region: us-central1
    serviceAccount: ""  # Leave empty - auto-populated from terraform
  
  # Backup schedule configuration
  schedules:
    infrastructure:
      daily:
        enabled: true
        schedule: "0 3 * * *"  # 3 AM daily
        retention: 720h  # 30 days
      hourly:
        enabled: false  # Optional - enable for critical infrastructure
    cluster:
      weekly:
        enabled: true
        schedule: "0 4 * * 0"  # 4 AM Sunday
        retention: 2160h  # 90 days
```

### Step 2: Create Credentials Secret (Only for DigitalOcean/MinIO)

**AWS/Azure/GCP**: No credential secret needed! Cloud-native authentication (IRSA/Workload Identity) is used automatically.

**DigitalOcean/MinIO**: Create secret with access keys:

```bash
# DigitalOcean Spaces
kubectl create secret generic velero-credentials \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=YOUR_SPACES_ACCESS_KEY
aws_secret_access_key=YOUR_SPACES_SECRET_KEY"

# MinIO (K3D)
kubectl create secret generic velero-credentials \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=minio
aws_secret_access_key=minio123"
```

See `infrastructure/velero/credentials-template.yaml` for more details.

### Step 3: Deploy via GitOps

```bash
# Commit and push changes
git add argocd/infrastructure/values.yaml
git commit -m "feat: Configure Velero backup infrastructure"
git push

# ArgoCD will automatically:
# 1. Deploy Velero operator (sync wave 0)
# 2. Deploy backup locations and schedules (sync wave 1)
```

---

## Verification

### Check Velero Installation
```bash
# Check operator deployment
kubectl get pods -n velero

# Check backup storage location
kubectl get backupstoragelocation -n velero
# Should show: default   Available

# Check volume snapshot location
kubectl get volumesnapshotlocation -n velero
# Should show: default   Available

# Check scheduled backups
kubectl get schedule -n velero
# Should show: infrastructure-daily, cluster-resources-weekly
```

### Monitor Backup Creation
```bash
# List all backups
kubectl get backup -n velero

# Watch backup progress
velero backup describe infrastructure-daily-20250116030000 --details

# Check backup logs
velero backup logs infrastructure-daily-20250116030000
```

### Verify Cloud Storage
```bash
# AWS
aws s3 ls s3://my-cluster-velero-backups/infrastructure/

# Azure
az storage blob list --container-name velero-backups \
  --account-name myclustervelero --prefix infrastructure/

# GCP
gsutil ls gs://my-cluster-velero-backups/infrastructure/
```

---

## Backup Schedules

### Infrastructure Backups (Cluster-Level)

| Schedule | Frequency | Retention | What's Backed Up |
|----------|-----------|-----------|------------------|
| `infrastructure-daily` | Daily at 3 AM | 30 days | Infrastructure namespaces (cert-manager, gateway, monitoring, etc.) |
| `infrastructure-hourly` | Every hour (optional) | 3 days | Critical infrastructure namespaces (fast recovery) |
| `cluster-resources-weekly` | Sunday 4 AM | 90 days | Cluster resources (CRDs, StorageClasses, ClusterRoles) |

### Application Backups (Per-Tenant)

Configured in application Helm charts (e.g., `charts/api/templates/velero-schedules.yaml`):

| Schedule | Frequency | Retention | What's Backed Up |
|----------|-----------|-----------|------------------|
| `{namespace}-hourly` | Every hour | 3 days | Tenant namespace (fast recovery) |
| `{namespace}-daily` | Daily at 2 AM | 30 days | Tenant namespace (standard recovery) |
| `{namespace}-weekly` | Sunday 3 AM | 90 days | Tenant namespace (long-term archive) |

---

## Disaster Recovery Procedures

### Scenario 1: Restore Infrastructure Namespace

```bash
# List available backups
velero backup get | grep infrastructure-daily

# Restore a specific backup
velero restore create --from-backup infrastructure-daily-20250116030000

# Monitor restore progress
velero restore describe infrastructure-daily-20250116030000-20250117120000

# Check restored resources
kubectl get all -n cert-manager
kubectl get all -n monitoring
```

### Scenario 2: Restore Entire Cluster

```bash
# 1. Create new cluster via terraform
cd terraform/clusters/my-cluster
terraform apply

# 2. Install Velero on new cluster
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set configuration.backupStorageLocation[0].bucket=my-cluster-velero-backups

# 3. Restore cluster resources first
velero restore create cluster-restore \
  --from-backup cluster-resources-weekly-20250114040000

# 4. Restore infrastructure namespaces
velero restore create infra-restore \
  --from-backup infrastructure-daily-20250116030000

# 5. Restore application namespaces (if needed)
velero restore create app-restore \
  --from-backup mycure-prod-daily-20250116020000
```

### Scenario 3: Restore Single Resource

```bash
# Restore specific namespace only
velero restore create cert-manager-restore \
  --from-backup infrastructure-daily-20250116030000 \
  --include-namespaces cert-manager

# Restore specific resource type
velero restore create secrets-restore \
  --from-backup infrastructure-daily-20250116030000 \
  --include-resources secrets \
  --namespace monitoring
```

### Scenario 4: Restore PersistentVolume Data

```bash
# Restore with volume snapshots
velero restore create postgres-restore \
  --from-backup mycure-prod-daily-20250116020000 \
  --include-namespaces mycure-prod \
  --restore-volumes=true

# Check PVC restoration
kubectl get pvc -n mycure-prod
kubectl get pv
```

---

## Testing Backups

### Test 1: Manual Backup

```bash
# Create on-demand backup
velero backup create test-backup \
  --include-namespaces cert-manager \
  --wait

# Verify backup completed
velero backup describe test-backup --details

# Check cloud storage
aws s3 ls s3://my-cluster-velero-backups/infrastructure/backups/test-backup/
```

### Test 2: Restore to Different Namespace

```bash
# Create test namespace
kubectl create namespace restore-test

# Restore cert-manager to test namespace
velero restore create test-restore \
  --from-backup test-backup \
  --namespace-mappings cert-manager:restore-test

# Verify
kubectl get all -n restore-test

# Cleanup
kubectl delete namespace restore-test
```

### Test 3: Validate Schedule Execution

```bash
# Check last backup time for each schedule
kubectl get schedule -n velero -o custom-columns=\
NAME:.metadata.name,\
LAST_BACKUP:.status.lastBackup,\
PHASE:.status.phase

# Verify backups are being created
kubectl get backup -n velero --sort-by=.metadata.creationTimestamp
```

---

## Troubleshooting

### Issue: BackupStorageLocation shows "Unavailable"

```bash
# Check BSL status
kubectl describe backupstoragelocation default -n velero

# Common causes:
# 1. Incorrect bucket name or region
# 2. Missing IAM permissions
# 3. Bucket doesn't exist

# Verify cloud access
kubectl logs -n velero deployment/velero

# For AWS IRSA - check service account annotation
kubectl get sa velero -n velero -o yaml | grep eks.amazonaws.com
```

### Issue: Volume snapshots not working

```bash
# Check VolumeSnapshotLocation
kubectl get volumesnapshotlocation -n velero
kubectl describe volumesnapshotlocation default -n velero

# Verify CSI driver is installed
kubectl get csidriver

# For AWS: Check EBS CSI driver
kubectl get pods -n kube-system | grep ebs-csi

# Check if snapshots are enabled in backup
velero backup describe <backup-name> --details | grep -A 5 "Snapshot Volumes"
```

### Issue: Backup fails with permission errors

```bash
# Check Velero logs
kubectl logs -n velero deployment/velero | grep -i error

# AWS - Verify IRSA role permissions
aws iam get-role --role-name my-cluster-velero
aws iam list-attached-role-policies --role-name my-cluster-velero

# Azure - Verify Workload Identity permissions
az role assignment list --assignee <identity-client-id>

# GCP - Verify Service Account permissions
gcloud projects get-iam-policy my-project \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:my-cluster-velero@"
```

### Issue: Scheduled backups not running

```bash
# Check schedule status
kubectl get schedule -n velero
kubectl describe schedule infrastructure-daily -n velero

# Check for schedule controller errors
kubectl logs -n velero deployment/velero | grep schedule

# Verify cron syntax
# Use https://crontab.guru/ to validate schedule expressions
```

### Issue: Restore fails

```bash
# Get detailed restore information
velero restore describe <restore-name> --details

# Check for partial failures
velero restore logs <restore-name>

# Common issues:
# 1. Resource conflicts (resource already exists)
# 2. StorageClass not available
# 3. PV provisioning failures
```

---

## Maintenance

### Cleanup Old Backups

```bash
# Backups auto-delete based on TTL
# Check TTL for each schedule in values.yaml

# Manually delete old backup
velero backup delete <backup-name>

# Delete all backups older than 30 days (careful!)
velero backup get -o json | \
  jq -r '.items[] | select(.status.expiration < now) | .metadata.name' | \
  xargs -I {} velero backup delete {}
```

### Monitor Storage Usage

```bash
# AWS S3
aws s3 ls s3://my-cluster-velero-backups/infrastructure/ --recursive \
  --human-readable --summarize

# Azure Blob
az storage blob list --container-name velero-backups \
  --account-name myclustervelero \
  --query "[].{Name:name, Size:properties.contentLength}" \
  --output table

# GCP GCS
gsutil du -sh gs://my-cluster-velero-backups/infrastructure/
```

### Velero CLI Installation

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

---

## Multi-Cloud Configuration Examples

### AWS Example

```yaml
velero:
  enabled: true
  provider: aws
  aws:
    region: us-east-1
    bucket: prod-cluster-velero-backups
    # roleArn auto-populated from terraform output
```

### Azure Example

```yaml
velero:
  enabled: true
  provider: azure
  azure:
    resourceGroup: prod-cluster-rg
    storageAccount: prodclustervelero
    blobContainer: velero-backups
    # identityClientId auto-populated from terraform output
```

### GCP Example

```yaml
velero:
  enabled: true
  provider: gcp
  gcp:
    bucket: prod-cluster-velero-backups
    projectId: my-gcp-project-123
    region: us-central1
    # serviceAccount auto-populated from terraform output
```

### DigitalOcean Example

```yaml
velero:
  enabled: true
  provider: digitalocean
  digitalocean:
    bucket: prod-cluster-velero-backups
    region: nyc3
    # accessKey/secretKey via External Secrets or manual secret
```

---

## Security Best Practices

1. **Use Cloud-Native Authentication**
   - AWS: IRSA (not static IAM user credentials)
   - Azure: Workload Identity (not service principal keys)
   - GCP: Workload Identity (not service account keys)

2. **Enable Encryption**
   - AWS S3: Server-side encryption (SSE-S3 or SSE-KMS)
   - Azure: Storage Account encryption enabled by default
   - GCP: Customer-managed encryption keys (CMEK) optional

3. **Restrict IAM Permissions**
   - Use least-privilege IAM policies
   - Scope to specific buckets (not wildcard)
   - Terraform modules already implement this

4. **Enable Versioning**
   - Protects against accidental deletion
   - Allows recovery of overwritten backups

5. **Monitor Backup Success**
   - Configure Alertmanager alerts for failed backups
   - Regular restore testing

---

## Cost Optimization

### Storage Costs

| Provider | Storage Type | Approximate Cost (per GB/month) |
|----------|-------------|----------------------------------|
| AWS S3 Standard | Hot | $0.023 |
| AWS S3 Glacier | Cold | $0.004 |
| Azure Blob Hot | Hot | $0.0184 |
| Azure Blob Cool | Cold | $0.01 |
| GCP Standard | Hot | $0.02 |
| GCP Nearline | Cold | $0.01 |
| DO Spaces | Hot | $0.02 (250GB free) |

### Optimization Tips

1. **Adjust Retention Periods**
   - Daily backups: 30 days (default)
   - Weekly backups: 90 days (default)
   - Consider shorter retention for non-production

2. **Use Lifecycle Policies**
   ```bash
   # AWS S3 - Move to Glacier after 30 days
   aws s3api put-bucket-lifecycle-configuration \
     --bucket my-cluster-velero-backups \
     --lifecycle-configuration file://lifecycle.json
   ```

3. **Disable Hourly Backups** (unless critical)
   ```yaml
   velero:
     schedules:
       infrastructure:
         hourly:
           enabled: false  # Saves storage costs
   ```

4. **Monitor Backup Size**
   ```bash
   # Check backup sizes
   velero backup get -o json | \
     jq -r '.items[] | "\(.metadata.name): \(.status.progress.totalItems) items"'
   ```

---

## Reference

### Velero Resources
- [Velero Documentation](https://velero.io/docs/)
- [Velero GitHub](https://github.com/vmware-tanzu/velero)
- [Backup Hooks](https://velero.io/docs/main/backup-hooks/)
- [Restore Reference](https://velero.io/docs/main/restore-reference/)

### Cloud Provider Guides
- [AWS EKS Backup Guide](https://docs.aws.amazon.com/eks/latest/userguide/velero.html)
- [Azure AKS Backup Guide](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-storage)
- [GCP GKE Backup Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/backing-up-stateful-apps)

### Related Infrastructure Docs
- [External Secrets Setup](./EXTERNAL-SECRETS-SETUP.md) - For credential management
- [Monitoring Setup](./MONITORING-SETUP.md) - For backup alerting
- [Storage Setup](./STORAGE-SETUP.md) - For PVC backup configuration

---

## Quick Reference Commands

```bash
# Installation verification
kubectl get pods -n velero
kubectl get backupstoragelocation -n velero
kubectl get schedule -n velero

# Create manual backup
velero backup create my-backup --include-namespaces cert-manager

# List backups
velero backup get

# Describe backup
velero backup describe my-backup --details

# Restore from backup
velero restore create --from-backup my-backup

# Monitor restore
velero restore describe my-restore --details

# Check logs
kubectl logs -n velero deployment/velero
velero backup logs my-backup

# Delete backup
velero backup delete my-backup

# Export backup to local file (for migration)
velero backup download my-backup -o /tmp/my-backup.tar.gz
```

---

## Support

For issues or questions:

1. Check Velero logs: `kubectl logs -n velero deployment/velero`
2. Review this documentation
3. Consult Velero documentation: https://velero.io/docs/
4. Check ArgoCD application status: `kubectl get application velero -n argocd`

---

**Last Updated**: 2025-10-16  
**Velero Version**: 7.1.4  
**Infrastructure**: monobase-infra
