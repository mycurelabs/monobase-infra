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
# Use the bootstrap script (recommended)
./scripts/new-client-config.sh myclient myclient.com

# This creates:
# config/myclient/
# ├── README.md
# ├── values-staging.yaml
# ├── values-production.yaml
# └── secrets-mapping.yaml
```

## Step 3: Customize Configuration

Edit the generated values files:

```bash
vim config/myclient/values-production.yaml
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
   hapihub:
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
   mongodb:
     persistence:
       size: 100Gi  # Adjust based on data volume
   ```

5. **Replica counts:**
   ```yaml
   hapihub:
     replicas: 3  # HA for production
   ```

6. **Optional components:**
   ```yaml
   syncd:
     enabled: true  # Enable if needed
   minio:
     enabled: true  # Or false for external S3
   ```

## Step 4: Configure Secrets Management

Edit secrets mapping:

```bash
vim config/myclient/secrets-mapping.yaml
```

Update with your KMS paths:

```yaml
provider: aws  # or azure, gcp, sops

# AWS example
mongodb:
  - secretKey: mongodb-root-password
    remoteKey: myclient/prod/mongodb/root-password

hapihub:
  - secretKey: JWT_SECRET
    remoteKey: myclient/prod/hapihub/jwt-secret
```

## Step 5: Create Secrets in KMS

Before deploying, create all secrets in your KMS:

```bash
# AWS Secrets Manager example
aws secretsmanager create-secret \\
  --name myclient/prod/mongodb/root-password \\
  --secret-string "$(openssl rand -base64 32)"

aws secretsmanager create-secret \\
  --name myclient/prod/hapihub/jwt-secret \\
  --secret-string "$(openssl rand -base64 64)"

# Repeat for all secrets in secrets-mapping.yaml
```

## Step 6: Commit Configuration

```bash
git add config/myclient/
git commit -m "Add MyClient production configuration"
git push origin main
```

## Step 7: Deploy Infrastructure (One-Time)

```bash
# Deploy Longhorn (storage)
kubectl apply -f infrastructure/longhorn/

# Deploy Envoy Gateway (routing)
kubectl apply -f infrastructure/envoy-gateway/

# Deploy External Secrets Operator
kubectl apply -f infrastructure/external-secrets-operator/

# Deploy ArgoCD (GitOps)
kubectl apply -f infrastructure/argocd/

# Wait for all to be ready
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
```

## Step 8: Deploy Applications via ArgoCD

```bash
# Render templates with your config
./scripts/render-templates.sh \\
  --values config/myclient/values-production.yaml \\
  --output rendered/myclient/

# Deploy root app (deploys everything)
kubectl apply -f rendered/myclient/argocd/root-app.yaml

# Watch deployment progress
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
```

## Step 9: Verify Deployment

```bash
# Check all pods running
kubectl get pods -n myclient-prod

# Check Gateway HTTPRoutes
kubectl get httproutes -n myclient-prod

# Test HapiHub API
curl https://api.myclient.com/health

# Test MyCureApp
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
- Configure backups (Velero schedules)
- Set up CI/CD for application updates
- Review security hardening checklist
- Schedule penetration testing

## Phase 1 Status

This is Phase 1 - foundation only. Subsequent phases will complete:
- Full Helm templates (Phase 2)
- Infrastructure YAMLs (Phase 3)
- Complete documentation (Phase 5)
- All scripts (Phase 6)
