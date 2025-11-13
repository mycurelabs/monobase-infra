# MyCure Production - Required Secrets Configuration

This document outlines all secrets required for the production deployment to function.

## Status: ⚠️ PRODUCTION DEPLOYMENT DISABLED

All production applications are currently **disabled** until required secrets are properly configured in GCP Secret Manager.

## Current Issue

- **Problem:** Production pods failing with `CreateContainerConfigError`
- **Root Cause:** Required secrets do not exist in GCP Secret Manager or Kubernetes
- **Impact:** 0 out of 8 applications can start successfully

## Required Secrets Overview

### 1. Database Secrets (Kubernetes Native)

These secrets must be created in the `mycure-production` namespace:

#### MongoDB Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb
  namespace: mycure-production
type: Opaque
stringData:
  mongodb-root-password: "<STRONG_PASSWORD>"
  mongodb-replica-set-key: "<BASE64_ENCODED_KEY>"
```

**Used by:**
- MongoDB StatefulSet
- HapiHub API (database connection)
- SyncD (database connection)

**Configuration:**
- `deployments/mycure-production/values.yaml` → `mongodb.auth.existingSecret: mongodb`
- `deployments/mycure-production/values.yaml` → `hapihub.mongodb.serviceName: mongodb`
- `deployments/mycure-production/values.yaml` → `syncd.mongodb.serviceName: mongodb`

---

#### PostgreSQL Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgresql
  namespace: mycure-production
type: Opaque
stringData:
  postgres-password: "<STRONG_PASSWORD>"
```

**Used by:**
- PostgreSQL StatefulSet
- Monobase API (if enabled)

**Configuration:**
- `deployments/mycure-production/values.yaml` → `postgresql.auth.existingSecret: postgresql`

---

#### MinIO Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio
  namespace: mycure-production
type: Opaque
stringData:
  root-user: "admin"  # or custom username
  root-password: "<STRONG_PASSWORD>"
```

**Used by:**
- MinIO StatefulSet
- Monobase API (if using object storage)

**Configuration:**
- `deployments/mycure-production/values.yaml` → `minio.auth.existingSecret: minio`

---

### 2. Application Secrets (GCP Secret Manager via External Secrets Operator)

These secrets must be created in **GCP Secret Manager** project `mc-v4-prod`:

#### Google OAuth Credentials
```bash
# Client ID
gcloud secrets create mycure-production-google-oauth-client-id \
  --project=mc-v4-prod \
  --data-file=- <<< "YOUR_GOOGLE_CLIENT_ID"

# Client Secret  
gcloud secrets create mycure-production-google-oauth-client-secret \
  --project=mc-v4-prod \
  --data-file=- <<< "YOUR_GOOGLE_CLIENT_SECRET"
```

**Used by:**
- HapiHub API (OAuth authentication)

**Configuration:**
- `deployments/mycure-production/values.yaml` → `hapihub.externalSecrets.secrets[]`

**How to obtain:**
1. Go to https://console.cloud.google.com/apis/credentials
2. Select project `mc-v4-prod` (or appropriate GCP project)
3. Create OAuth 2.0 Client ID (or use existing)
4. Set authorized redirect URIs: `https://hapihub.mycureapp.com/api/auth/callback/google`
5. Copy Client ID and Client Secret

---

#### Stripe Secret Key
```bash
gcloud secrets create mycure-production-stripe-secret-key \
  --project=mc-v4-prod \
  --data-file=- <<< "sk_live_YOUR_STRIPE_SECRET_KEY"
```

**Used by:**
- HapiHub API (payment processing)

**Configuration:**
- `deployments/mycure-production/values.yaml` → `hapihub.externalSecrets.secrets[]`

**How to obtain:**
1. Go to https://dashboard.stripe.com/apikeys
2. Use **live mode** secret key (starts with `sk_live_`)
3. ⚠️ Never use test keys in production

---

## External Secrets Operator Configuration

The cluster is already configured with:
- ✅ External Secrets Operator deployed (`external-secrets` namespace)
- ✅ GCP ClusterSecretStore configured (`gcp-secretstore`)
- ✅ Service Account with Secret Manager access

**Verify configuration:**
```bash
kubectl get clustersecretstore -n mycure-production
# Expected: gcp-secretstore (Status: Valid, Ready: True)
```

**Check ExternalSecret status:**
```bash
kubectl get externalsecrets -n mycure-production
kubectl describe externalsecret hapihub-secrets -n mycure-production
```

---

## Deployment Checklist

Before enabling production applications, complete these steps:

### Phase 1: Create Database Secrets
- [ ] Create `mongodb` secret in `mycure-production` namespace
- [ ] Create `postgresql` secret in `mycure-production` namespace  
- [ ] Create `minio` secret in `mycure-production` namespace
- [ ] Verify secrets exist: `kubectl get secrets -n mycure-production`

### Phase 2: Create GCP Secrets
- [ ] Create Google OAuth Client ID in GCP Secret Manager
- [ ] Create Google OAuth Client Secret in GCP Secret Manager
- [ ] Create Stripe Secret Key in GCP Secret Manager
- [ ] Verify secrets exist: `gcloud secrets list --project=mc-v4-prod | grep mycure-production`

### Phase 3: Verify External Secrets Sync
- [ ] Check ExternalSecret status: `kubectl get externalsecrets -n mycure-production`
- [ ] Verify hapihub-secrets shows `Ready: True`
- [ ] Confirm Kubernetes secret created: `kubectl get secret hapihub-secrets -n mycure-production`

### Phase 4: Enable Applications
- [ ] Edit `deployments/mycure-production/values.yaml`
- [ ] Set `mongodb.enabled: true`
- [ ] Set `postgresql.enabled: true`
- [ ] Set `minio.enabled: true`
- [ ] Set `hapihub.enabled: true`
- [ ] Set `syncd.enabled: true`
- [ ] Set `mycure.enabled: true`
- [ ] Set `mycurev8.enabled: true`
- [ ] Commit and push changes
- [ ] Wait for ArgoCD to sync (or trigger manually)

### Phase 5: Verify Deployment
- [ ] Check all pods are running: `kubectl get pods -n mycure-production`
- [ ] Verify no `CreateContainerConfigError` or `CrashLoopBackOff`
- [ ] Check application logs for any errors
- [ ] Test application endpoints (after DNS propagates)

---

## Security Best Practices

1. **Use strong passwords:**
   - Minimum 32 characters
   - Include upper, lower, numbers, special characters
   - Use password generator: `openssl rand -base64 32`

2. **Rotate secrets regularly:**
   - Database passwords: Every 90 days
   - API keys: Every 180 days
   - OAuth credentials: When compromised

3. **Limit secret access:**
   - GCP Secret Manager IAM: Only grant access to service accounts that need it
   - Kubernetes RBAC: Restrict secret access to production namespace

4. **Audit secret access:**
   - Enable Cloud Audit Logs for Secret Manager
   - Monitor ExternalSecret sync failures
   - Set up alerts for unauthorized access

---

## Troubleshooting

### ExternalSecret shows `SecretSyncedError`
```bash
kubectl describe externalsecret hapihub-secrets -n mycure-production
```
**Common causes:**
- Secret doesn't exist in GCP Secret Manager
- Service Account lacks `secretmanager.secretAccessor` role
- Secret name mismatch between ExternalSecret and GCP

**Fix:**
```bash
# Verify secret exists
gcloud secrets describe mycure-production-google-oauth-client-id --project=mc-v4-prod

# Grant access to service account
gcloud secrets add-iam-policy-binding mycure-production-google-oauth-client-id \
  --project=mc-v4-prod \
  --member="serviceAccount:YOUR_SA@mc-v4-prod.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Pods show `CreateContainerConfigError`
```bash
kubectl describe pod POD_NAME -n mycure-production
```
**Common causes:**
- Secret doesn't exist in namespace
- Secret key mismatch (e.g., chart expects `postgres-password` but secret has `password`)

**Fix:**
```bash
# Check what secrets exist
kubectl get secrets -n mycure-production

# Check secret keys
kubectl get secret mongodb -n mycure-production -o yaml
```

### Database won't start (CrashLoopBackOff)
```bash
kubectl logs -n mycure-production mongodb-0 --previous
```
**Common causes:**
- PVC not bound (check `kubectl get pvc -n mycure-production`)
- Insufficient resources (check node resources)
- Corrupted data volume (may need to delete PVC and recreate)

---

## Reference

- **Helm Chart:** `charts/mycure` (umbrella chart)
- **Values:** `deployments/mycure-production/values.yaml`
- **External Secrets Config:** HapiHub subchart (`hapihub.externalSecrets`)
- **GCP Project:** `mc-v4-prod`
- **Kubernetes Namespace:** `mycure-production`
- **ArgoCD Application:** `mycure-production-root` (App of Apps)

---

## Questions?

Contact the platform team or refer to:
- External Secrets Operator docs: https://external-secrets.io
- GCP Secret Manager docs: https://cloud.google.com/secret-manager/docs
- Bitnami MongoDB chart: https://github.com/bitnami/charts/tree/main/bitnami/mongodb
