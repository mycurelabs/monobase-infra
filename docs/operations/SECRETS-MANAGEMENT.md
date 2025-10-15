# Secrets Management Guide

Complete guide to secrets management using External Secrets Operator and KMS.

## Overview

**Never commit secrets to Git!** Use External Secrets Operator to sync from KMS.

## Supported Providers

1. **AWS Secrets Manager** (EKS recommended)
2. **Azure Key Vault** (AKS recommended)
3. **GCP Secret Manager** (GKE recommended)
4. **SOPS** (Git-based encrypted files)

## AWS Secrets Manager Setup

### 1. Create IAM Role (IRSA)

```bash
# Create IAM policy
aws iam create-policy --policy-name external-secrets-policy --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
    "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:myclient/prod/*"
  }]
}'

# Create IAM role with IRSA trust policy
eksctl create iamserviceaccount \
  --name external-secrets \
  --namespace myclient-prod \
  --cluster my-cluster \
  --attach-policy-arn arn:aws:iam::123456789012:policy/external-secrets-policy \
  --approve
```

### 2. Create Secrets in AWS

```bash
# Create PostgreSQL password
aws secretsmanager create-secret \
  --name myclient/prod/postgresql/root-password \
  --secret-string "$(openssl rand -base64 32)"

# Create JWT secret
aws secretsmanager create-secret \
  --name myclient/prod/api/jwt-secret \
  --secret-string "$(openssl rand -base64 64)"

# Create all secrets from secrets-mapping.yaml
```

### 3. Deploy SecretStore

```bash
# Applied automatically via ArgoCD or manually:
cat infrastructure/external-secrets-operator/secretstore/aws-secretsmanager.yaml.template | \
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \
  kubectl apply -f -
```

### 4. Verify Secrets Sync

```bash
# Check ExternalSecrets
kubectl get externalsecrets -n myclient-prod

# Check sync status
kubectl describe externalsecret api-secrets -n myclient-prod

# Verify Kubernetes secrets created
kubectl get secrets -n myclient-prod
```

## Azure Key Vault Setup

### 1. Enable Workload Identity

```bash
# Enable on AKS cluster
az aks update \
  --resource-group my-rg \
  --name my-cluster \
  --enable-workload-identity \
  --enable-oidc-issuer
```

### 2. Create Key Vault and Secrets

```bash
# Create Key Vault
az keyvault create \
  --name myclient-prod-kv \
  --resource-group my-rg \
  --location eastus

# Create secrets
az keyvault secret set \
  --vault-name myclient-prod-kv \
  --name postgresql-root-password \
  --value "$(openssl rand -base64 32)"
```

### 3. Configure Workload Identity

```bash
# Create managed identity
az identity create \
  --name external-secrets-identity \
  --resource-group my-rg

# Grant Key Vault access
az keyvault set-policy \
  --name myclient-prod-kv \
  --object-id <identity-object-id> \
  --secret-permissions get list
```

## GCP Secret Manager Setup

### 1. Enable API

```bash
gcloud services enable secretmanager.googleapis.com
```

### 2. Create Secrets

```bash
# Create secret
echo -n "SecurePassword123" | gcloud secrets create postgresql-root-password \
  --data-file=- \
  --project=my-project
```

### 3. Configure Workload Identity

```bash
# Create GCP service account
gcloud iam service-accounts create external-secrets \
  --project=my-project

# Grant Secret Manager access
gcloud projects add-iam-policy-binding my-project \
  --member="serviceAccount:external-secrets@my-project.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Bind to K8s service account
gcloud iam service-accounts add-iam-policy-binding \
  external-secrets@my-project.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:my-project.svc.id.goog[myclient-prod/external-secrets]"
```

## SOPS Setup

### 1. Install SOPS

```bash
brew install sops
```

### 2. Create Encryption Key

```bash
# AWS KMS
aws kms create-key --description "SOPS encryption key"

# Or use age (no cloud dependency)
age-keygen -o age.key
```

### 3. Create .sops.yaml

```yaml
# In repository root
creation_rules:
  - path_regex: config/.*/secrets\.enc\.yaml$
    kms: 'arn:aws:kms:us-east-1:123456789012:key/key-id'
```

### 4. Encrypt Secrets File

```bash
# Create secrets file
cat > config/myclient/secrets.yaml <<EOF
postgresql:
  root-password: SecurePassword123
api:
  jwt-secret: JwtSecret456
EOF

# Encrypt with SOPS
sops -e config/myclient/secrets.yaml > config/myclient/secrets.enc.yaml

# Commit encrypted file (safe!)
git add config/myclient/secrets.enc.yaml
git commit -m "Add encrypted secrets"
```

## Secret Rotation

### Rotate JWT Secret

```bash
# 1. Generate new secret
NEW_SECRET=$(openssl rand -base64 64)

# 2. Update in KMS
aws secretsmanager update-secret \
  --secret-id myclient/prod/api/jwt-secret \
  --secret-string "$NEW_SECRET"

# 3. External Secrets syncs automatically (within 1h)
# Or force refresh:
kubectl annotate externalsecret api-secrets \
  force-sync=$(date +%s) \
  -n myclient-prod

# 4. Restart pods to use new secret
kubectl rollout restart deployment api -n myclient-prod
```

## Security Best Practices

1. **Never commit secrets** - Use .gitignore
2. **Rotate regularly** - Every 90 days minimum
3. **Use separate secrets** per environment
4. **Enable audit logging** - Track secret access
5. **Least privilege** - IAM policies restrict access
6. **Monitor failures** - Alert on sync failures

For complete secret mappings, see `config/example.com/secrets-mapping.yaml`.
