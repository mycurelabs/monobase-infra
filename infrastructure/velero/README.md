# Velero Backup Implementation

> **Note**: This document covers Velero-specific implementation details. For backup strategy, disaster recovery procedures, and runbooks, see:
> - [Backup & DR Strategy](../../docs/operations/BACKUP_DR.md)
> - [Disaster Recovery Runbooks](../../docs/operations/DISASTER_RECOVERY_RUNBOOKS.md)

## Overview

Velero is the current backup implementation for the monobase infrastructure. It provides:
- Cluster-level backups (infrastructure namespaces + cluster resources)
- Per-application backups (tenant namespaces via app charts)
- Multi-cloud support (AWS, Azure, GCP, DigitalOcean, MinIO)
- Cloud-native authentication (IRSA, Workload Identity)

## Prerequisites

### Cloud Identity (Automated)

Terraform modules automatically provision cloud identities:
- **AWS**: IRSA role for S3/EBS access
- **Azure**: Workload Identity for Blob Storage/Disk access
- **GCP**: Service Account for GCS/PD access

Check terraform outputs:
```bash
cd terraform/clusters/your-cluster
terraform output | grep velero
```

### Backup Storage (Manual Setup Required)

**Terraform does NOT create storage buckets** - create them manually:

#### AWS S3
```bash
aws s3 mb s3://my-cluster-velero-backups --region us-east-1
aws s3api put-bucket-versioning \
  --bucket my-cluster-velero-backups \
  --versioning-configuration Status=Enabled
```

#### Azure Blob Storage
```bash
az storage account create \
  --name myclustervelero \
  --resource-group my-cluster-rg \
  --sku Standard_GRS
az storage container create \
  --name velero-backups \
  --account-name myclustervelero
```

#### GCP Cloud Storage
```bash
gsutil mb -l us-central1 gs://my-cluster-velero-backups
gsutil versioning set on gs://my-cluster-velero-backups
```

#### DigitalOcean Spaces
```bash
doctl compute space create my-cluster-velero-backups --region nyc3
```

---

## Configuration

### Update `argocd/infrastructure/values.yaml`

```yaml
velero:
  enabled: true
  provider: aws  # Options: aws, azure, gcp, digitalocean, minio
  
  # AWS Configuration
  aws:
    region: us-east-1
    bucket: my-cluster-velero-backups
    roleArn: ""  # Auto-populated from terraform
  
  # Schedule configuration
  schedules:
    infrastructure:
      daily:
        enabled: true
        retention: 720h  # 30 days
    cluster:
      weekly:
        enabled: true
        retention: 2160h  # 90 days
```

### Credentials (Only for DigitalOcean/MinIO)

**AWS/Azure/GCP**: No credentials needed - uses cloud-native auth (IRSA/Workload Identity)

**DigitalOcean/MinIO**: Create secret manually:
```bash
kubectl create secret generic velero-credentials \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=YOUR_KEY
aws_secret_access_key=YOUR_SECRET"
```

See `credentials-template.yaml` for detailed examples.

### Deploy via GitOps

```bash
git add argocd/infrastructure/values.yaml
git commit -m "feat: Enable Velero backups"
git push
```

ArgoCD will automatically deploy:
1. Velero operator (sync wave 0)
2. Backup locations and schedules (sync wave 1)

---

## Verification

```bash
# Check installation
kubectl get pods -n velero
kubectl get backupstoragelocation -n velero  # Should show: Available
kubectl get volumesnapshotlocation -n velero  # Should show: Available
kubectl get schedule -n velero  # Should show: infrastructure-daily, cluster-resources-weekly

# Monitor backup creation
kubectl get backup -n velero
velero backup describe infrastructure-daily-<timestamp> --details

# Verify cloud storage
aws s3 ls s3://my-cluster-velero-backups/infrastructure/
```

---

## Multi-Cloud Configuration Examples

### AWS (IRSA Authentication)
```yaml
velero:
  enabled: true
  provider: aws
  aws:
    region: us-east-1
    bucket: prod-cluster-velero-backups
    # roleArn: auto-populated from terraform
```

### Azure (Workload Identity)
```yaml
velero:
  enabled: true
  provider: azure
  azure:
    resourceGroup: prod-cluster-rg
    storageAccount: prodclustervelero
    blobContainer: velero-backups
    # identityClientId: auto-populated from terraform
```

### GCP (Workload Identity)
```yaml
velero:
  enabled: true
  provider: gcp
  gcp:
    bucket: prod-cluster-velero-backups
    projectId: my-gcp-project
    region: us-central1
    # serviceAccount: auto-populated from terraform
```

### DigitalOcean (S3-Compatible)
```yaml
velero:
  enabled: true
  provider: digitalocean
  digitalocean:
