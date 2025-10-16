# Client Onboarding Guide

Step-by-step guide for onboarding a new client using the fork-based workflow.

## Prerequisites

- GitHub/GitLab account for forking
- Kubernetes cluster (EKS, AKS, GKE, or self-hosted)
- kubectl configured for your cluster
- Helm 3.x installed
- Access to KMS (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, or SOPS)

## Step 1: Fork the Template Repository

```bash
# On GitHub: Click "Fork" button on YOUR-ORG/monobase-infra

# Clone YOUR fork
git clone https://github.com/YOUR-ORG/YOUR-FORK.git
cd YOUR-FORK
```

## Step 2: Create Client Configuration

```bash
# Create deployment configuration directory
mkdir -p deployments/myclient-prod
mkdir -p deployments/myclient-staging

# Copy base templates
cp deployments/templates/production-base.yaml deployments/myclient-prod/values.yaml
cp deployments/templates/staging-base.yaml deployments/myclient-staging/values.yaml
```

## Step 3: Customize Configuration

Edit the values files:

```bash
vim deployments/myclient-prod/values.yaml
```

**Key items to customize:**

1. **Domain and namespace:**
   ```yaml
   global:
     domain: myclient.com
     namespace: myclient-prod
   ```

2. **Image tags** (IMPORTANT - don't use "latest"):
   ```yaml
   api:
     image:
       tag: "5.215.2"  # Specific version
   ```

3. **Resource limits:**
   ```yaml
   resources:
     requests:
       cpu: 1
       memory: 2Gi
     limits:
       cpu: 2
       memory: 4Gi
   ```

4. **Storage sizes:**
   ```yaml
   postgresql:
     persistence:
       size: 100Gi  # Adjust based on data volume
   ```

5. **Replica counts:**
   ```yaml
   api:
     replicas: 3  # HA for production
   ```

6. **Optional components:**
   ```yaml
   api-worker:
     enabled: true  # Enable if needed
   minio:
     enabled: true  # Or false for external S3
   ```

## Step 4: Configure Secrets Management

Update secrets configuration in your values file:

```yaml
# deployments/myclient-prod/values.yaml

externalSecrets:
  provider: aws  # or azure, gcp, vault
  
  secrets:
    postgresql:
      - secretKey: postgresql-root-password
        remoteKey: myclient/prod/postgresql/root-password
    
    api:
      - secretKey: JWT_SECRET
        remoteKey: myclient/prod/api/jwt-secret
```

## Step 5: Create Secrets in KMS

Before deploying, create all secrets in your KMS:

```bash
# AWS Secrets Manager example
aws secretsmanager create-secret \\
  --name myclient/prod/postgresql/root-password \\
  --secret-string "$(openssl rand -base64 32)"

aws secretsmanager create-secret \\
  --name myclient/prod/api/jwt-secret \\
  --secret-string "$(openssl rand -base64 64)"

# Repeat for all secrets in secrets-mapping.yaml
```

## Step 6: Commit Configuration

```bash
git add deployments/myclient-prod/ deployments/myclient-staging/
git commit -m "Add MyClient production and staging configurations"
git push origin main
```

## Step 7: Bootstrap Cluster (One-Time)

```bash
# Run bootstrap script to install ArgoCD + Infrastructure
./scripts/bootstrap.sh

# This installs:
# 1. ArgoCD itself
# 2. Infrastructure Root Application (manages all cluster infrastructure)
# 3. ApplicationSet (auto-discovers client configs in deployments/)

# Wait for infrastructure to deploy (5-10 minutes)
kubectl get application -n argocd -w
```

## Step 8: Verify Client Auto-Discovery

ArgoCD ApplicationSet automatically discovers your client configurations:

```bash
# Wait for ApplicationSet to discover your config (~30 seconds)
kubectl get applications -n argocd | grep myclient-prod

# You should see Applications created automatically:
# - myclient-prod-namespace
# - myclient-prod-security
# - myclient-prod-postgresql
# - myclient-prod-api
# - myclient-prod-account
# etc.

# Watch deployment progress via ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
```

## Step 9: Verify Deployment

```bash
# Check all pods running
kubectl get pods -n myclient-prod

# Check Gateway HTTPRoutes
kubectl get httproutes -n myclient-prod

# Test Monobase API API
curl https://api.myclient.com/health

# Test Monobase Account
curl https://app.myclient.com
```

## Step 10: Configure DNS

Point your domains to the Gateway LoadBalancer IP:

```bash
# Get LoadBalancer IP
kubectl get svc -n gateway-system envoy-gateway

# Create DNS records:
# A api.myclient.com → <LoadBalancer-IP>
# A app.myclient.com → <LoadBalancer-IP>
# A sync.myclient.com → <LoadBalancer-IP>
# A storage.myclient.com → <LoadBalancer-IP>
```

## Troubleshooting

### Secrets Not Syncing
- Check SecretStore is created: `kubectl get secretstore -n myclient-prod`
- Check IAM permissions (IRSA, Workload Identity)
- Check KMS secret exists and is accessible

### Pods Not Starting
- Check events: `kubectl describe pod <pod-name> -n myclient-prod`
- Check logs: `kubectl logs <pod-name> -n myclient-prod`
- Check resource quotas: `kubectl describe resourcequota -n myclient-prod`

### Gateway Not Working
- Check Gateway status: `kubectl get gateway -n gateway-system`
- Check HTTPRoute status: `kubectl get httproute -n myclient-prod`
- Check DNS resolution: `nslookup api.myclient.com`

## Next Steps

- Set up monitoring (if enabled)
- Configure backups (managed automatically by Velero schedules)
- Set up CI/CD for application updates
- Review security hardening checklist
- Schedule penetration testing
