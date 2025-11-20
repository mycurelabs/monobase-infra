# Deployment Guide

Complete deployment procedures for Monobase Infrastructure.

## ⚡ Quick Start: GitOps-First Approach (Recommended)

**For the automated GitOps deployment using ArgoCD and bootstrap.sh**, see:
- **[CLIENT-ONBOARDING.md](CLIENT-ONBOARDING.md)** - Complete GitOps workflow with bootstrap.sh
- **[GITOPS-ARGOCD.md](../architecture/GITOPS-ARGOCD.md)** - GitOps architecture details

The sections below document **manual deployment steps** as an alternative or reference.

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Infrastructure Deployment](#infrastructure-deployment) *(Manual alternative to bootstrap.sh)*
3. [Application Deployment](#application-deployment)
4. [Post-Deployment Verification](#post-deployment-verification)
5. [DNS Configuration](#dns-configuration)
6. [Backup Configuration](#backup-configuration)
7. [Monitoring Setup](#monitoring-setup)

---

## Pre-Deployment Checklist

### Prerequisites

- [ ] Kubernetes cluster provisioned (EKS, AKS, GKE, or self-hosted)
- [ ] kubectl configured and authenticated
- [ ] Helm 3.x installed
- [ ] Domain names registered
- [ ] DNS access for configuration
- [ ] KMS access (AWS Secrets Manager / Azure Key Vault / GCP Secret Manager)
- [ ] S3 bucket for backups
- [ ] Repository forked and client config created

### Cluster Requirements

**Minimum (Core Stack):**
- 3 nodes
- 4 CPU per node (12 CPU total)
- 16GB RAM per node (48GB total)
- 100GB storage per node

**Recommended (Full Stack):**
- 5 nodes
- 8 CPU per node (40 CPU total)
- 32GB RAM per node (160GB total)
- 500GB storage per node

### Configuration Checklist

- [ ] Client config created: `deployments/{client}/`
- [ ] values-production.yaml customized
- [ ] Image tags set to specific versions (not "latest")
- [ ] Resource limits configured
- [ ] Secrets created in KMS
- [ ] secrets-mapping.yaml updated
- [ ] Backup S3 bucket created
- [ ] Configuration committed to Git

---

## Infrastructure Deployment

Deploy infrastructure in specific order (dependencies):

### Step 1: Create Namespace

```bash
# Label namespace for Gateway access
kubectl create namespace gateway-system
kubectl label namespace gateway-system kubernetes.io/metadata.name=gateway-system

# Create client namespace
kubectl create namespace myclient-prod
kubectl label namespace myclient-prod \\
  pod-security.kubernetes.io/enforce=restricted \\
  pod-security.kubernetes.io/audit=restricted \\
  pod-security.kubernetes.io/warn=restricted \\
  kubernetes.io/metadata.name=myclient-prod

# Or use template
cat infrastructure/namespaces/namespace.yaml.template | \\
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \\
  kubectl apply -f -
```

### Step 2: Deploy Longhorn (Storage)

```bash
# Add Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install Longhorn
helm install longhorn longhorn/longhorn \\
  --namespace longhorn-system \\
  --create-namespace \\
  --values infrastructure/longhorn/helm-values.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \\
  -l app=longhorn-manager \\
  -n longhorn-system \\
  --timeout=600s

# Apply StorageClass
kubectl apply -f infrastructure/longhorn/storageclass.yaml

# Apply backup configuration
kubectl apply -f infrastructure/longhorn/backup-config.yaml

# Verify
kubectl get storageclass longhorn
kubectl get pods -n longhorn-system
```

**Time:** ~5-10 minutes

### Step 3: Deploy cert-manager (TLS)

```bash
# Add Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \\
  --namespace cert-manager \\
  --create-namespace \\
  --set installCRDs=true

# Wait for ready
kubectl wait --for=condition=ready pod \\
  -l app.kubernetes.io/name=cert-manager \\
  -n cert-manager \\
  --timeout=300s

# Apply ClusterIssuer (replace values)
cat infrastructure/cert-manager/clusterissuer.yaml.template | \\
  sed 's/{{ .Values.global.domain }}/myclient.com/g' | \\
  kubectl apply -f -

# Verify
kubectl get clusterissuer
```

**Time:** ~3-5 minutes

### Step 4: Deploy Envoy Gateway

```bash
# Add Helm repository
helm repo add envoy-gateway https://gateway.envoyproxy.io
helm repo update

# Install Envoy Gateway
helm install envoy-gateway envoy-gateway/gateway-helm \\
  --namespace envoy-gateway-system \\
  --create-namespace \\
  --values infrastructure/envoy-gateway/helm-values.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \\
  -l control-plane=envoy-gateway \\
  -n envoy-gateway-system \\
  --timeout=300s

# Create GatewayClass
kubectl apply -f infrastructure/envoy-gateway/gateway-class.yaml

# Create shared Gateway (replace values)
cat infrastructure/envoy-gateway/gateway.yaml.template | \\
  sed 's/{{ .Values.global.domain }}/myclient.com/g' | \\
  kubectl apply -f -

# Apply security policies
kubectl apply -f infrastructure/envoy-gateway/rate-limit-policy.yaml

# Wait for LoadBalancer IP
kubectl wait --for=jsonpath='{.status.addresses[0].value}' \\
  gateway/shared-gateway \\
  -n gateway-system \\
  --timeout=300s

# Get LoadBalancer IP
GATEWAY_IP=$(kubectl get gateway shared-gateway -n gateway-system \\
  -o jsonpath='{.status.addresses[0].value}')
echo "Gateway LoadBalancer IP: $GATEWAY_IP"
```

**Time:** ~5-10 minutes

**Certificate Management:**

For client custom domains, see:
- [Certificate Management Operations Guide](../operations/CERTIFICATE-MANAGEMENT.md)
- [Multi-Domain Gateway Architecture](../architecture/MULTI-DOMAIN-GATEWAY.md)

Certificates are provisioned via HTTP-01 challenge or can be client-provided.

### Step 5: Deploy External Secrets Operator

```bash
# Add Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \\
  --namespace external-secrets-system \\
  --create-namespace \\
  --values infrastructure/external-secrets-operator/helm-values.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \\
  -l app.kubernetes.io/name=external-secrets \\
  -n external-secrets-system \\
  --timeout=300s

# Create SecretStore (choose your provider)
# AWS:
cat infrastructure/external-secrets-operator/secretstore/aws-secretsmanager.yaml.template | \\
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \\
  kubectl apply -f -

# Azure:
# cat infrastructure/external-secrets-operator/secretstore/azure-keyvault.yaml.template | ...

# GCP:
# cat infrastructure/external-secrets-operator/secretstore/gcp-secretmanager.yaml.template | ...

# Verify
kubectl get secretstore -n myclient-prod
```

**Time:** ~3-5 minutes

### Step 6: Deploy Velero (Backups)

```bash
# Install Velero CLI
brew install velero  # macOS
# Or download from https://velero.io

# Create backup credentials secret (via External Secrets)
# See infrastructure/velero/helm-values.yaml for configuration

# Add Helm repository
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Install Velero
helm install velero vmware-tanzu/velero \\
  --namespace velero \\
  --create-namespace \\
  --values infrastructure/velero/helm-values.yaml \\
  --set configuration.backupStorageLocation[0].bucket=myclient-prod-backups \\
  --set configuration.backupStorageLocation[0].config.region=us-east-1

# Wait for ready
kubectl wait --for=condition=ready pod \\
  -l app.kubernetes.io/name=velero \\
  -n velero \\
  --timeout=300s

# Deploy backup schedules (replace values)
cat infrastructure/velero/backup-schedules/hourly-critical.yaml | \\
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \\
  kubectl apply -f -

cat infrastructure/velero/backup-schedules/daily-full.yaml | \\
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \\
  kubectl apply -f -

cat infrastructure/velero/backup-schedules/weekly-archive.yaml | \\
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \\
  kubectl apply -f -

# Verify
velero schedule get
velero backup get
```

**Time:** ~5 minutes

### Step 7: Deploy ArgoCD (GitOps)

```bash
# Add Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD
helm install argocd argo/argo-cd \\
  --namespace argocd \\
  --create-namespace \\
  --values infrastructure/argocd/helm-values.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \\
  -l app.kubernetes.io/name=argocd-server \\
  -n argocd \\
  --timeout=600s

# Create HTTPRoute for UI access
cat infrastructure/argocd/httproute.yaml.template | \\
  sed 's/{{ .Values.global.domain }}/myclient.com/g' | \\
  kubectl apply -f -

# Get admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \\
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"
echo "ArgoCD URL: https://argocd.myclient.com"
```

**Time:** ~5-10 minutes

### Step 8: Apply Security Policies

```bash
# Apply NetworkPolicies
kubectl apply -f infrastructure/security/networkpolicies/default-deny-all.yaml
kubectl apply -f infrastructure/security/networkpolicies/allow-gateway-to-apps.yaml
kubectl apply -f infrastructure/security/networkpolicies/allow-apps-to-db.yaml
kubectl apply -f infrastructure/security/networkpolicies/allow-apps-to-storage.yaml
kubectl apply -f infrastructure/security/networkpolicies/deny-cross-namespace.yaml

# Apply RBAC
cat infrastructure/security/rbac/*.yaml.template | \\
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \\
  kubectl apply -f -

# Verify
kubectl get networkpolicy -n myclient-prod
kubectl get serviceaccount -n myclient-prod
kubectl get role -n myclient-prod
```

**Time:** ~2 minutes

**Total Infrastructure Deployment Time:** ~30-40 minutes

---

## Application Deployment

### Option A: Via Helm (Direct)

```bash
# Deploy PostgreSQL
helm install postgresql charts/api \\
  --namespace myclient-prod \\
  --values deployments/myclient/values-production.yaml \\
  --set postgresql.enabled=true \\
  --set api.enabled=false

# Deploy Monobase API
helm install api charts/api \\
  --namespace myclient-prod \\
  --values deployments/myclient/values-production.yaml \\
  --set postgresql.enabled=false

# Deploy API Worker (if enabled)
helm install api-worker charts/api-worker \\
  --namespace myclient-prod \\
  --values deployments/myclient/values-production.yaml

# Deploy Monobase Account
helm install account charts/account \\
  --namespace myclient-prod \\
  --values deployments/myclient/values-production.yaml
```

### Option B: Via ArgoCD (Recommended)

```bash
# 1. Ensure ArgoCD is deployed
# 2. Create ArgoCD Application (App-of-Apps)

cat argocd/bootstrap/root-app.yaml.template | \\
  sed 's/{{ .Values.global.namespace }}/myclient-prod/g' | \\
  sed 's/{{ .Values.argocd.repoURL }}/https:\\/\\/github.com\\/myclient\\/client-infra.git/g' | \\
  kubectl apply -f -

# 3. Watch deployment in ArgoCD UI
# Open: https://argocd.myclient.com
# Login with admin password from Step 7

# 4. Or watch via CLI
argocd app get myclient-prod-root --refresh

# 5. Sync applications
argocd app sync myclient-prod-root --async
```

**Time:** ~10-15 minutes for all applications

---

## Post-Deployment Verification

### 1. Verify All Pods Running

```bash
# Check all pods
kubectl get pods -n myclient-prod

# Expected pods:
# - api-xxx (2-3 replicas)
# - api-worker-xxx (2 replicas, if enabled)
# - account-xxx (2 replicas)
# - postgresql-xxx (3 replicas)
# - minio-xxx (6 replicas, if enabled)
# - valkey-xxx (3 replicas, if enabled)

# Check pod status
kubectl get pods -n myclient-prod -o wide

# All should show STATUS: Running, READY: 1/1
```

### 2. Verify Services

```bash
# List services
kubectl get svc -n myclient-prod

# Expected services:
# - api (ClusterIP)
# - api-worker (ClusterIP)
# - account (ClusterIP)
# - postgresql (ClusterIP)
# - minio (ClusterIP, if enabled)
# - valkey (ClusterIP, if enabled)
```

### 3. Verify HTTPRoutes

```bash
# Check HTTPRoutes
kubectl get httproute -n myclient-prod

# Expected routes:
# - api → api.myclient.com
# - api-worker → sync.myclient.com (if enabled)
# - account → app.myclient.com
# - minio → storage.myclient.com (if enabled)

# Check route status
kubectl describe httproute api -n myclient-prod
```

### 4. Verify External Secrets

```bash
# Check ExternalSecrets
kubectl get externalsecrets -n myclient-prod

# Check sync status
kubectl describe externalsecret api-secrets -n myclient-prod

# Verify secrets created
kubectl get secrets -n myclient-prod | grep secrets
```

### 5. Test Endpoints

```bash
# Test Monobase API health
curl https://api.myclient.com/health
# Expected: {"status": "ok"}

# Test Monobase Account
curl -I https://app.myclient.com
# Expected: HTTP/2 200

# Test API Worker (if enabled)
curl https://sync.myclient.com/health
```

---

## DNS Configuration

### Get LoadBalancer IP

```bash
# Get Gateway LoadBalancer IP
kubectl get gateway shared-gateway -n gateway-system \\
  -o jsonpath='{.status.addresses[0].value}'

# Example output: 54.123.456.789
```

### Create DNS Records

Create A records pointing to the LoadBalancer IP:

```
Type  | Name                  | Value
------|-----------------------|----------------
A     | api.myclient.com      | 54.123.456.789
A     | app.myclient.com      | 54.123.456.789
A     | sync.myclient.com     | 54.123.456.789
A     | storage.myclient.com  | 54.123.456.789
A     | argocd.myclient.com   | 54.123.456.789
A     | grafana.myclient.com  | 54.123.456.789
```

**Or use wildcard:**

```
Type  | Name            | Value
------|-----------------|----------------
A     | *.myclient.com  | 54.123.456.789
```

### Verify DNS

```bash
# Check DNS resolution
nslookup api.myclient.com
dig api.myclient.com

# Test TLS certificate
curl -v https://api.myclient.com 2>&1 | grep subject
```

---

## Backup Configuration

### Configure Longhorn Backup Target

```bash
# Set backup target (S3 or NFS)
kubectl -n longhorn-system patch settings.longhorn.io backup-target \\
  --type=merge \\
  --patch='{"value": "s3://myclient-prod-backups@us-east-1/longhorn"}'

# Set backup credentials
kubectl -n longhorn-system patch settings.longhorn.io backup-target-credential-secret \\
  --type=merge \\
  --patch='{"value": "longhorn-backup-credentials"}'

# Verify
kubectl get settings.longhorn.io backup-target -n longhorn-system -o yaml
```

### Test Backups

```bash
# Test Velero backup
velero backup create test-backup \\
  --include-namespaces myclient-prod \\
  --wait

# Check backup status
velero backup describe test-backup

# List backups
velero backup get

# Test restore (to different namespace)
kubectl create namespace myclient-restore-test
velero restore create test-restore \\
  --from-backup test-backup \\
  --namespace-mappings myclient-prod:myclient-restore-test

# Cleanup
kubectl delete namespace myclient-restore-test
```

---

## Monitoring Setup

### Deploy Monitoring Stack (Optional)

```bash
# Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \\
  --namespace monitoring \\
  --create-namespace \\
  --values infrastructure/monitoring/helm-values.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \\
  -l app.kubernetes.io/name=prometheus \\
  -n monitoring \\
  --timeout=600s

# Apply custom alert rules
kubectl apply -f infrastructure/monitoring/prometheus-rules.yaml

# Create HTTPRoute for Grafana
cat infrastructure/monitoring/httproute.yaml.template | \\
  sed 's/{{ .Values.global.domain }}/myclient.com/g' | \\
  kubectl apply -f -

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring monitoring-grafana \\
  -o jsonpath="{.data.admin-password}" | base64 -d)

echo "Grafana URL: https://grafana.myclient.com"
echo "Username: admin"
echo "Password: $GRAFANA_PASSWORD"
```

**Time:** ~10-15 minutes

---

## Deployment Checklist

### Infrastructure
- [ ] Longhorn deployed and healthy
- [ ] cert-manager deployed
- [ ] Envoy Gateway deployed
- [ ] LoadBalancer IP assigned
- [ ] External Secrets Operator deployed
- [ ] Velero deployed
- [ ] ArgoCD deployed
- [ ] Security policies applied

### Applications
- [ ] PostgreSQL replica set healthy (3 nodes)
- [ ] Monobase API pods running
- [ ] API Worker pods running (if enabled)
- [ ] Monobase Account pods running
- [ ] MinIO cluster healthy (if enabled)
- [ ] Valkey running (if enabled)

### Networking
- [ ] HTTPRoutes created
- [ ] DNS records configured
- [ ] TLS certificates issued
- [ ] All endpoints accessible

### Security
- [ ] NetworkPolicies applied
- [ ] Pod Security Standards enforced
- [ ] Secrets synced from KMS
- [ ] RBAC configured

### Backups
- [ ] Backup schedules created
- [ ] Test backup successful
- [ ] S3 bucket configured
- [ ] Encryption enabled

---

## Rollback Procedures

### Rollback Application

```bash
# Via Helm
helm rollback api -n myclient-prod

# Via ArgoCD
argocd app rollback myclient-prod-api

# To specific revision
helm rollback api 3 -n myclient-prod
```

### Rollback Infrastructure

```bash
# Restore from Velero backup
velero restore create rollback-$(date +%Y%m%d) \\
  --from-backup daily-full-20250115020000

# Or selective restore
velero restore create \\
  --from-backup daily-full-20250115020000 \\
  --include-resources deployments,services
```

---

## Next Steps

1. **Configure monitoring alerts** - Update Alertmanager with Slack/PagerDuty webhooks
2. **Test disaster recovery** - Perform restore test monthly
3. **Security hardening** - Review [SECURITY-HARDENING.md](SECURITY-HARDENING.md)
4. **Performance tuning** - Monitor and adjust resource limits
5. **Documentation** - Document any client-specific procedures

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.
