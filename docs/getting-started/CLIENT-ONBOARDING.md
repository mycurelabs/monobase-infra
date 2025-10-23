# Client Onboarding Guide

Step-by-step guide for onboarding a new client using the fork-based workflow.

## Prerequisites

- GitHub/GitLab account for forking
- Kubernetes cluster (EKS, AKS, GKE, or self-hosted)
- kubectl configured for your cluster
- Helm 3.x installed
- Access to KMS (AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager)

## Step 1: Fork the Template Repository

```bash
# On GitHub: Click "Fork" button on monobaselabs/monobase-infra

# Clone YOUR fork
git clone https://github.com/YOUR-ORG/monobase-infra.git
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

## Custom Domain Setup (Optional)

If your client has their own domain (e.g., `app.client.com`) instead of using a subdomain under your platform domain, follow these additional steps.

### Prerequisites

- Client owns domain and has DNS access
- LoadBalancer IP from Gateway (see Step 10 above)
- Client willing to create DNS A record

### Step 1: Get LoadBalancer IP

```bash
kubectl get gateway shared-gateway -n gateway-system \
  -o jsonpath='{.status.addresses[0].value}'

# Example output: 203.0.113.42
```

### Step 2: Client Configures DNS

Client creates an A record in their DNS provider:

```
app.client.com    A    203.0.113.42
```

**Verify DNS propagation:**
```bash
dig app.client.com +short
# Should return: 203.0.113.42
```

### Step 3: Add Certificate Configuration

See detailed instructions in [Certificate Management Operations Guide](../operations/CERTIFICATE-MANAGEMENT.md).

**Quick summary:**

Edit `infrastructure/certificates.yaml`:
```yaml
certificates:
  # Add new client certificate
  - name: myclient-domain
    domain: "app.client.com"
    issuer: letsencrypt-http01-prod
    challengeType: http01
```

Commit and deploy:
```bash
git add infrastructure/certificates.yaml
git commit -m "feat: Add certificate for app.client.com"
git push
```

**Wait for certificate provisioning (2-5 minutes):**
```bash
kubectl get certificate myclient-domain-tls -n gateway-system
# Status should show: Ready=True
```

### Step 4: Update Deployment Configuration

Update your client's `values.yaml` to use custom domain:

```yaml
# deployments/myclient-prod/values.yaml

gateway:
  hostname: "app.client.com"  # Custom domain instead of subdomain

# Rest of configuration remains the same
api:
  enabled: true
  replicas: 3
```

### Step 5: Verify Custom Domain

```bash
# Test TLS handshake
openssl s_client -connect app.client.com:443 -servername app.client.com

# Test HTTP routing
curl -v https://app.client.com/health

# Expected: 200 OK with valid TLS certificate
```

### Custom Domain vs Platform Subdomain

| Feature | Platform Subdomain | Client Custom Domain |
|---------|-------------------|---------------------|
| **DNS** | Managed by platform | Client manages DNS |
| **Certificate** | Wildcard (auto) | Per-domain (HTTP-01 or client-provided) |
| **Setup Time** | Instant | 2-5 minutes (cert provisioning) |
| **Client Control** | None | Full DNS control |
| **Use Case** | Standard deployments | White-label, client branding |

### Certificate Options

**Option 1: Auto-Provisioned (HTTP-01) - Recommended**
- Platform manages certificate via Let's Encrypt
- Automatic renewal every 60 days
- Client only needs to create DNS A record

**Option 2: Client-Provided Certificate**
- Client uploads their own certificate to GCP Secret Manager
- Client manages certificate renewal
- See [Certificate Management Guide](../operations/CERTIFICATE-MANAGEMENT.md) for details

---

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
