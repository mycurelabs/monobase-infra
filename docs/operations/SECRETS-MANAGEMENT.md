# Secrets Management Guide

Complete guide to secrets management using External Secrets Operator and Cloud KMS.

## Overview

**Never commit secrets to Git!** Use External Secrets Operator to sync from cloud KMS providers.

This repository uses cloud-based secret management exclusively. Secrets are stored in your cloud provider's KMS and automatically synced to Kubernetes via External Secrets Operator (ESO).

## Quick Start

The easiest way to get started is using our setup script:

```bash
# Run the secrets setup script
bash scripts/secrets.sh

# Follow the interactive prompts to:
# 1. Select your cloud provider (GCP recommended)
# 2. Automatically configure KMS and Workload Identity
# 3. Create secrets interactively or from YAML files
# 4. Generate ExternalSecret manifests for GitOps
```

## Supported Providers

1. **GCP Secret Manager** (Recommended - Free tier: 6 versions, 10k ops/month)
2. **AWS Secrets Manager** (EKS) - Not yet implemented
3. **Azure Key Vault** (AKS) - Not yet implemented

## How It Works

### GitOps Workflow

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  GCP Secret     │      │  ExternalSecret  │      │  Kubernetes     │
│  Manager        │─────▶│  (in Git)        │─────▶│  Secret         │
│  (Cloud KMS)    │      │                  │      │  (Runtime)      │
└─────────────────┘      └──────────────────┘      └─────────────────┘
   Manual/Script            GitOps (ArgoCD)          Auto-synced
   One-time setup           Always in Git            Ephemeral
```

### Manual vs GitOps Steps

**Manual (One-time setup):**

- Create secrets in cloud KMS
- Configure Workload Identity/IRSA
- Deploy ClusterSecretStore

**GitOps (Automatic):**

- ExternalSecret manifests in Git
- ArgoCD applies manifests
- ESO syncs secrets to Kubernetes

## GCP Secret Manager Setup (Recommended)

### Prerequisites

```bash
# Install gcloud CLI via mise
mise install gcloud

# Authenticate
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### Option 1: Automated Setup (Recommended)

```bash
# Run the GCP secrets setup script
bash scripts/secrets-gcp.sh

# The script will:
# 1. Auto-detect your GCP project
# 2. Enable required APIs (Secret Manager, IAM)
# 3. Prompt for namespace and secrets
# 4. Create secrets in GCP Secret Manager
# 5. Configure Workload Identity
# 6. Generate ClusterSecretStore YAML
# 7. Create ExternalSecret manifests for your secrets
```

### Option 2: Manual Setup

#### 1. Enable Secret Manager API

```bash
gcloud services enable secretmanager.googleapis.com
```

#### 2. Create Secrets in GCP

```bash
# Create PostgreSQL password
echo -n "$(openssl rand -base64 32)" | gcloud secrets create postgresql-root-password \
  --data-file=- \
  --replication-policy="automatic"

# Create JWT secret
echo -n "$(openssl rand -base64 64)" | gcloud secrets create api-jwt-secret \
  --data-file=- \
  --replication-policy="automatic"

# Create Cloudflare API token
echo -n "YOUR_CLOUDFLARE_TOKEN" | gcloud secrets create cloudflare-api-token \
  --data-file=- \
  --replication-policy="automatic"
```

#### 3. Configure Workload Identity

```bash
# Set variables
PROJECT_ID="your-gcp-project"
NAMESPACE="mycure-preprod"
KSA_NAME="external-secrets"
GSA_NAME="external-secrets"

# Create GCP service account
gcloud iam service-accounts create $GSA_NAME \
  --display-name="External Secrets Operator"

# Grant Secret Manager access
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Bind to Kubernetes service account
gcloud iam service-accounts add-iam-policy-binding \
  ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"
```

#### 4. Deploy ClusterSecretStore

The `ClusterSecretStore` (named `gcp-secretstore`) is defined declaratively in
`values/infrastructure/main.yaml` and rendered by the `charts/external-secrets-stores`
chart. It looks like:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secretstore
spec:
  provider:
    gcpsm:
      projectID: "${PROJECT_ID}"
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: your-cluster
          serviceAccountRef:
            name: ${KSA_NAME}
            namespace: ${NAMESPACE}
```

Edit `values/infrastructure/main.yaml`, commit, and push — ArgoCD renders the
`charts/external-secrets-stores` chart and applies the store to the
`external-secrets-system` namespace.

#### 5. Create ExternalSecret Manifests

`ExternalSecret` resources are rendered by the app charts; the tenant config that
drives them lives in `values/deployments/<client>-<env>.yaml`. A rendered manifest
looks like:

```yaml
# Example: Cloudflare API token for cert-manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secretstore
    kind: ClusterSecretStore
  target:
    name: cloudflare-api-token-secret
    creationPolicy: Owner
  data:
    - secretKey: api-token
      remoteRef:
        key: cloudflare-api-token
```

Edit the relevant `values/` file, commit, and push — ArgoCD applies the
ExternalSecret for GitOps.

#### 6. Verify Secrets Sync

```bash
# Check ClusterSecretStore
kubectl get clustersecretstore gcp-secretstore
kubectl describe clustersecretstore gcp-secretstore

# Check ExternalSecrets
kubectl get externalsecrets -A

# Check sync status
kubectl describe externalsecret cloudflare-api-token -n cert-manager

# Verify Kubernetes secrets created
kubectl get secret cloudflare-api-token-secret -n cert-manager
```

## AWS Secrets Manager Setup

**Status:** Not yet implemented

To add AWS support:

1. Implement `scripts/secrets-aws.sh` (use `scripts/secrets-gcp.sh` as template)
2. Add an AWS `ClusterSecretStore` to `values/infrastructure/main.yaml` (chart `charts/external-secrets-stores`)
3. Update deployment values to use `provider: aws`

For now, use GCP Secret Manager as the default provider.

## Azure Key Vault Setup

**Status:** Not yet implemented

To add Azure support:

1. Implement `scripts/secrets-azure.sh` (use `scripts/secrets-gcp.sh` as template)
2. Add an Azure `ClusterSecretStore` to `values/infrastructure/main.yaml` (chart `charts/external-secrets-stores`)
3. Update deployment values to use `provider: azure`

For now, use GCP Secret Manager as the default provider.

## Secret Rotation

### Rotate Any Secret

```bash
# 1. Generate new secret value
NEW_SECRET=$(openssl rand -base64 64)

# 2. Update in GCP Secret Manager (creates new version)
echo -n "$NEW_SECRET" | gcloud secrets versions add api-jwt-secret --data-file=-

# 3. External Secrets syncs automatically (within 1h based on refreshInterval)
# Or force refresh:
kubectl annotate externalsecret api-secrets \
  force-sync=$(date +%s) \
  -n mycure-production

# 4. Restart pods to use new secret
kubectl rollout restart deployment api -n mycure-production
```

### Rotate Cloudflare API Token

```bash
# 1. Create new token in Cloudflare dashboard
# https://dash.cloudflare.com/profile/api-tokens

# 2. Update in GCP Secret Manager
echo -n "NEW_CLOUDFLARE_TOKEN" | gcloud secrets versions add cloudflare-api-token --data-file=-

# 3. Force sync (cert-manager will use new token)
kubectl annotate externalsecret cloudflare-api-token \
  force-sync=$(date +%s) \
  -n cert-manager

# 4. Verify cert-manager can access new token
kubectl logs -n cert-manager deploy/cert-manager -f
```

## Using Secrets in Deployments

### Reference ExternalSecret in Helm Values

Tenant config lives in `values/deployments/<client>-<env>.yaml` (e.g.
`values/deployments/mycure-production.yaml`, `mycure-preprod.yaml`) overlaying
`values/deployments/_base/mycure.yaml`:

```yaml
# In values/deployments/mycure-production.yaml
postgresql:
  auth:
    existingSecret: postgresql-secrets
    secretKeys:
      adminPasswordKey: root-password
```

A `global.secretPrefix` scopes the remote-key namespace. For example
`mycure-preprod` intentionally sets `secretPrefix: mycure-production` so it reads
the `mycure-production-*` keys for restored-PVC credential parity.

### Create ExternalSecret for Deployment

The app charts render the `ExternalSecret` from these values. The rendered
resource looks like:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgresql-secrets
  namespace: mycure-production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secretstore
    kind: ClusterSecretStore
  target:
    name: postgresql-secrets
    creationPolicy: Owner
  data:
    - secretKey: root-password
      remoteRef:
        key: mycure-production-postgresql-root-password
```

hapihub is PostgreSQL-backed; its Postgres, Valkey, and MinIO credentials are all
delivered this way via ESO.

## Security Best Practices

1. **Never commit secrets to Git** - Use `.gitignore` for local secret files
2. **Use cloud KMS exclusively** - No encrypted files in Git
3. **Rotate regularly** - Every 90 days minimum for credentials
4. **Use separate secrets per environment** - Don't share secrets between staging/prod
5. **Enable audit logging** - Track secret access in cloud provider
6. **Least privilege** - IAM policies restrict access to specific secrets
7. **Monitor failures** - Alert on ExternalSecret sync failures
8. **Use Workload Identity** - No static credentials in clusters

## Troubleshooting

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret <name> -n <namespace>

# Check ESO logs
kubectl logs -n external-secrets-system deploy/external-secrets -f

# Check ClusterSecretStore
kubectl describe clustersecretstore gcp-secretstore

# Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy \
  external-secrets@PROJECT_ID.iam.gserviceaccount.com
```

### Secret Not Found in GCP

```bash
# List all secrets
gcloud secrets list

# Get secret details
gcloud secrets describe <secret-name>

# View secret versions
gcloud secrets versions list <secret-name>

# Test access
gcloud secrets versions access latest --secret=<secret-name>
```

### Workload Identity Issues

```bash
# Verify GKE Workload Identity is enabled
gcloud container clusters describe CLUSTER_NAME \
  --format="value(workloadIdentityConfig.workloadPool)"

# Check service account annotation
kubectl get sa external-secrets -n <namespace> -o yaml

# Should see: iam.gke.io/gcp-service-account: external-secrets@PROJECT_ID.iam.gserviceaccount.com
```

## Declarative ExternalSecret Pattern

External Secrets Operator uses a **declarative, GitOps-first approach**:

### How It Works

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  1. Create      │      │  2. Store in     │      │  3. ESO         │
│  ExternalSecret │─────▶│  Cloud KMS       │─────▶│  Auto-Syncs     │
│  (in Git)       │      │  (via script)    │      │  (continuous)   │
└─────────────────┘      └──────────────────┘      └─────────────────┘
   GitOps Resource         Manual Operation         Automatic Process
```

### Key Principles

1. **ExternalSecrets are defined in Git first** - Declarative resources committed to repository
2. **Secrets stored in cloud KMS** - Use scripts or cloud console to create actual secrets
3. **ESO continuously syncs** - Operator watches ExternalSecrets and syncs from KMS
4. **If KMS secret missing** - ExternalSecret shows `Ready: False` until secret exists

### Example Workflow

**Step 1: Create ExternalSecret in Git**

```yaml
# Rendered from values/deployments/mycure-preprod.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: mycure-preprod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secretstore
    kind: ClusterSecretStore
  target:
    name: cloudflare-api-token
    creationPolicy: Owner
  data:
    - secretKey: api-token
      remoteRef:
        key: infrastructure-cloudflare-api-token
```

**Step 2: Store Secret in GCP Secret Manager**

```bash
# Create secret in GCP (if not already exists)
echo -n "YOUR_CLOUDFLARE_TOKEN" | gcloud secrets create infrastructure-cloudflare-api-token \
  --data-file=- \
  --replication-policy=automatic
```

**Step 3: ESO Automatically Syncs**

```bash
# Watch ExternalSecret status
kubectl get externalsecret -n mycure-preprod cloudflare-api-token -w

# Verify synced Kubernetes Secret
kubectl get secret -n mycure-preprod cloudflare-api-token
```

### Common Patterns

**External-DNS Credentials:**

- ExternalSecret in namespace → References infrastructure Cloudflare token → DNS automation works

**Application Secrets:**

- ExternalSecret in namespace → References app-specific secrets → Pods consume via env/volume

**Database Passwords:**

- ExternalSecret in namespace → References DB password from KMS → StatefulSet uses secret

### Troubleshooting

**ExternalSecret shows `Ready: False`:**

- Secret doesn't exist in cloud KMS
- ClusterSecretStore not configured
- Workload Identity permissions missing

**Secret not updating:**

- Check `refreshInterval` (default: 1h)
- Force refresh: `kubectl annotate externalsecret NAME force-sync=$(date +%s)`

## References

- [External Secrets Operator Docs](https://external-secrets.io)
- [GCP Secret Manager](https://cloud.google.com/secret-manager/docs)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [Azure Key Vault](https://docs.microsoft.com/azure/key-vault/)
