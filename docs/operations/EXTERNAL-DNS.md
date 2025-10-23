# External DNS Guide

Automatic DNS record management from Kubernetes resources using External DNS and External Secrets Operator.

## Overview

External DNS automatically creates and updates DNS records based on Kubernetes resources:

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  HTTPRoute   │─────▶│ External DNS │─────▶│  DNS Provider│
│  (Gateway)   │      │   Watcher    │      │  (Cloudflare)│
└──────────────┘      └──────────────┘      └──────────────┘
   hostname: app        Detects hostname      Creates A record
   .example.com         Gets Gateway IP       → Gateway IP
```

### Key Features

- **Automatic DNS management** - No manual DNS configuration required
- **Gateway API integration** - Watches HTTPRoutes, TCPRoutes, TLSRoutes
- **Multi-instance support** - Multiple DNS providers per namespace
- **ESO credential management** - Secure credential sync from cloud KMS
- **Namespace-scoped** - Each deployment manages its own DNS

## Supported DNS Providers

This infrastructure supports **4 DNS providers**:

| Provider | Auth Method | Use Case |
|----------|-------------|----------|
| **Cloudflare** | API Token | Primary recommendation |
| **AWS Route53** | IRSA | AWS/EKS deployments |
| **Google Cloud DNS** | Workload Identity | GCP/GKE deployments |
| **Azure DNS** | Managed Identity | Azure/AKS deployments |

## Quick Start (Cloudflare)

### 1. Create Cloudflare API Token

1. Go to Cloudflare Dashboard → My Profile → API Tokens
2. Create Token → Use "Edit zone DNS" template
3. Permissions:
   - Zone / DNS / Edit
4. Zone Resources:
   - Include / Specific zone / `mycureapp.com`
5. Copy the generated token

### 2. Store Token in GCP Secret Manager

```bash
# Store in GCP (if using GCP Secret Manager)
echo -n "YOUR_CLOUDFLARE_TOKEN" | gcloud secrets create infrastructure-cloudflare-api-token \
  --data-file=- \
  --replication-policy=automatic
```

### 3. Create ExternalSecret

```yaml
# deployments/mycure-staging/cloudflare-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: mycure-staging
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

### 4. Enable External-DNS

```yaml
# deployments/mycure-staging/values.yaml
externalDNS:
  enabled: true

  instances:
    - name: primary
      enabled: true
      provider: cloudflare

      domainFilters:
        - mycureapp.com

      cloudflare:
        proxied: false  # DNS only, no CDN
        apiTokenSecretRef:
          name: cloudflare-api-token
          key: api-token

      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 50m
          memory: 64Mi
```

### 5. Deploy and Verify

```bash
# Deploy via ArgoCD (or commit and push)
kubectl get externalsecret -n mycure-staging cloudflare-api-token
# Should show: Ready: True

# Check External DNS pod
kubectl get pods -n mycure-staging -l app.kubernetes.io/name=external-dns

# View External DNS logs
kubectl logs -n mycure-staging -l app.kubernetes.io/name=external-dns --tail=50

# Verify DNS records created
dig mycure.stg.mycureapp.com
dig api.stg.mycureapp.com
```

## Provider Setup Guides

### Cloudflare

**API Token Setup:**

1. Cloudflare Dashboard → My Profile → API Tokens
2. Create Token → Edit zone DNS template
3. Permissions: Zone / DNS / Edit
4. Zone Resources: Include → Specific zone
5. TTL: No expiration recommended

**ExternalSecret (GCP Secret Manager):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: YOUR-NAMESPACE
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
        key: YOUR-NAMESPACE-cloudflare-token
```

**Values Configuration:**

```yaml
externalDNS:
  enabled: true
  instances:
    - name: primary
      enabled: true
      provider: cloudflare
      domainFilters: [example.com]
      cloudflare:
        proxied: false  # Set true to enable Cloudflare CDN
        apiTokenSecretRef:
          name: cloudflare-api-token
          key: api-token
```

**Multiple Cloudflare Accounts:**

```yaml
externalDNS:
  enabled: true
  instances:
    # Primary account
    - name: primary
      enabled: true
      provider: cloudflare
      domainFilters: [mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-primary
          key: api-token

    # Client subdomain with different account
    - name: client-subdomain
      enabled: true
      provider: cloudflare
      domainFilters: [client.mycureapp.com]
      cloudflare:
        proxied: true  # Enable CDN for this subdomain
        apiTokenSecretRef:
          name: cloudflare-token-client
          key: api-token
```

### AWS Route53

**IAM Setup (IRSA):**

```bash
# Create IAM policy
cat > route53-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ExternalDNSRoute53Policy \
  --policy-document file://route53-policy.json

# Create IAM role for service account
eksctl create iamserviceaccount \
  --cluster=YOUR-CLUSTER \
  --namespace=YOUR-NAMESPACE \
  --name=external-dns \
  --attach-policy-arn=arn:aws:iam::ACCOUNT:policy/ExternalDNSRoute53Policy \
  --approve
```

**ExternalSecret (AWS Secrets Manager - if using access keys):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: route53-credentials
  namespace: YOUR-NAMESPACE
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretstore
    kind: ClusterSecretStore
  target:
    name: route53-credentials
    creationPolicy: Owner
  data:
    - secretKey: access-key-id
      remoteRef:
        key: YOUR-NAMESPACE-route53-access-key-id
    - secretKey: secret-access-key
      remoteRef:
        key: YOUR-NAMESPACE-route53-secret-access-key
```

**Values Configuration (IRSA - Recommended):**

```yaml
externalDNS:
  enabled: true
  instances:
    - name: route53
      enabled: true
      provider: aws
      domainFilters: [example.com]
      aws:
        region: us-east-1
        zoneType: public  # or private

      # IRSA annotation
      serviceAccount:
        annotations:
          eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/external-dns-role
```

**Values Configuration (Access Keys):**

```yaml
externalDNS:
  enabled: true
  instances:
    - name: route53
      enabled: true
      provider: aws
      domainFilters: [example.com]
      aws:
        region: us-east-1
        zoneType: public
        credentials:
          secretRef:
            name: route53-credentials
            accessKeyIDKey: access-key-id
            secretAccessKeyKey: secret-access-key
```

### Google Cloud DNS

**IAM Setup (Workload Identity):**

```bash
# Create service account
gcloud iam service-accounts create external-dns \
  --display-name="External DNS Service Account"

# Grant DNS admin permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:external-dns@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/dns.admin"

# Bind Kubernetes SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  external-dns@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/external-dns]"
```

**ExternalSecret (GCP Secret Manager - if using SA key):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: clouddns-sa-key
  namespace: YOUR-NAMESPACE
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secretstore
    kind: ClusterSecretStore
  target:
    name: clouddns-sa-key
    creationPolicy: Owner
  data:
    - secretKey: credentials.json
      remoteRef:
        key: YOUR-NAMESPACE-clouddns-sa-key
```

**Values Configuration (Workload Identity - Recommended):**

```yaml
externalDNS:
  enabled: true
  instances:
    - name: clouddns
      enabled: true
      provider: google
      domainFilters: [example.com]
      google:
        project: YOUR-PROJECT-ID

      # Workload Identity annotation
      serviceAccount:
        annotations:
          iam.gke.io/gcp-service-account: external-dns@PROJECT_ID.iam.gserviceaccount.com
```

**Values Configuration (Service Account Key):**

```yaml
externalDNS:
  enabled: true
  instances:
    - name: clouddns
      enabled: true
      provider: google
      domainFilters: [example.com]
      google:
        project: YOUR-PROJECT-ID
        credentials:
          secretRef:
            name: clouddns-sa-key
            key: credentials.json
```

### Azure DNS

**IAM Setup (Managed Identity):**

```bash
# Create managed identity
az identity create \
  --name external-dns-identity \
  --resource-group YOUR-RG

# Assign DNS Zone Contributor role
az role assignment create \
  --role "DNS Zone Contributor" \
  --assignee-object-id $(az identity show --name external-dns-identity --resource-group YOUR-RG --query principalId -o tsv) \
  --scope /subscriptions/SUBSCRIPTION_ID/resourceGroups/YOUR-RG/providers/Microsoft.Network/dnszones/example.com

# Enable pod identity on AKS
az aks pod-identity add \
  --cluster-name YOUR-CLUSTER \
  --resource-group YOUR-RG \
  --namespace YOUR-NAMESPACE \
  --name external-dns \
  --identity-resource-id $(az identity show --name external-dns-identity --resource-group YOUR-RG --query id -o tsv)
```

**ExternalSecret (Azure Key Vault - if using service principal):**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: azuredns-credentials
  namespace: YOUR-NAMESPACE
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-secretstore
    kind: ClusterSecretStore
  target:
    name: azuredns-credentials
    creationPolicy: Owner
  data:
    - secretKey: client-id
      remoteRef:
        key: YOUR-NAMESPACE-dns-client-id
    - secretKey: client-secret
      remoteRef:
        key: YOUR-NAMESPACE-dns-client-secret
    - secretKey: tenant-id
      remoteRef:
        key: YOUR-NAMESPACE-dns-tenant-id
```

**Values Configuration (Managed Identity - Recommended):**

```yaml
externalDNS:
  enabled: true
  instances:
    - name: azuredns
      enabled: true
      provider: azure
      domainFilters: [example.com]
      azure:
        resourceGroup: YOUR-RG
        subscriptionId: YOUR-SUBSCRIPTION-ID
        useManagedIdentity: true
```

**Values Configuration (Service Principal):**

```yaml
externalDNS:
  enabled: true
  instances:
    - name: azuredns
      enabled: true
      provider: azure
      domainFilters: [example.com]
      azure:
        resourceGroup: YOUR-RG
        subscriptionId: YOUR-SUBSCRIPTION-ID
        credentials:
          secretRef:
            name: azuredns-credentials
            clientIDKey: client-id
            clientSecretKey: client-secret
            tenantIDKey: tenant-id
```

## Multi-Instance Patterns

### Multiple DNS Providers

```yaml
externalDNS:
  enabled: true
  instances:
    # Cloudflare for main domain
    - name: cloudflare-primary
      enabled: true
      provider: cloudflare
      domainFilters: [example.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token

    # Route53 for AWS-hosted subdomain
    - name: route53-aws
      enabled: true
      provider: aws
      domainFilters: [aws.example.com]
      aws:
        region: us-east-1
```

### Separate Production and Staging

```yaml
externalDNS:
  enabled: true
  instances:
    # Staging environment
    - name: staging
      enabled: true
      provider: cloudflare
      domainFilters: [stg.example.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-staging

    # Production environment
    - name: production
      enabled: true
      provider: cloudflare
      domainFilters: [example.com]
      cloudflare:
        proxied: true  # Enable CDN for prod
        apiTokenSecretRef:
          name: cloudflare-production
```

## Verification

### Check ExternalSecret Status

```bash
# View ExternalSecret
kubectl get externalsecret -n NAMESPACE

# Should show Ready: True
NAME                    STORE              REFRESH INTERVAL   STATUS   READY
cloudflare-api-token    gcp-secretstore    1h                 SecretSynced   True

# View synced Kubernetes Secret
kubectl get secret -n NAMESPACE cloudflare-api-token
```

### Check External DNS Pod

```bash
# View pods
kubectl get pods -n NAMESPACE -l app.kubernetes.io/name=external-dns

# View logs
kubectl logs -n NAMESPACE -l app.kubernetes.io/name=external-dns --tail=100

# Should see:
# time="..." level=info msg="Desired change: CREATE ... A ... [IP]"
# time="..." level=info msg="Record created successfully"
```

### Verify DNS Records

```bash
# Query DNS
dig mycure.stg.mycureapp.com
dig api.stg.mycureapp.com +short

# Should return Gateway IP
157.245.123.45

# Test HTTP
curl https://mycure.stg.mycureapp.com
```

### Check HTTPRoutes

```bash
# List HTTPRoutes in namespace
kubectl get httproute -n NAMESPACE

# Verify hostname in HTTPRoute
kubectl get httproute -n NAMESPACE APP-NAME -o yaml | grep -A5 hostnames
```

## Troubleshooting

### ExternalSecret Not Ready

**Symptom:**
```bash
kubectl get externalsecret -n NAMESPACE
NAME                    STATUS           READY
cloudflare-api-token    SecretSyncedError   False
```

**Solutions:**

```bash
# 1. Check if secret exists in cloud KMS
gcloud secrets list | grep cloudflare  # GCP
aws secretsmanager list-secrets        # AWS
az keyvault secret list               # Azure

# 2. Verify ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore gcp-secretstore

# 3. Check Workload Identity permissions
kubectl get sa external-secrets -n NAMESPACE -o yaml
# Should have iam.gke.io/gcp-service-account annotation

# 4. View ExternalSecret events
kubectl describe externalsecret -n NAMESPACE cloudflare-api-token
```

### External DNS Not Creating Records

**Symptom:** Pods running but no DNS records created

**Solutions:**

```bash
# 1. Check External DNS logs
kubectl logs -n NAMESPACE -l app.kubernetes.io/name=external-dns --tail=200

# Look for errors:
# - "Unauthorized" → Wrong credentials
# - "Zone not found" → Check domain filters
# - "No changes" → HTTPRoute might not have correct hostname

# 2. Verify HTTPRoute hostname
kubectl get httproute -n NAMESPACE -o yaml | grep -A3 hostnames

# 3. Check domain filters match
# values.yaml domainFilters must match HTTPRoute hostnames

# 4. Verify secret exists
kubectl get secret -n NAMESPACE cloudflare-api-token

# 5. Test DNS provider credentials manually
# For Cloudflare:
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

### DNS Records Not Updating

**Symptom:** Old records remain after deployment changes

**Solutions:**

```bash
# 1. Check External DNS policy
# In values.yaml, ensure: policy: sync (not upsert-only)

# 2. Force External DNS refresh
kubectl rollout restart deployment -n NAMESPACE external-dns-primary

# 3. Check TXT records (External DNS ownership)
dig txt mycure.stg.mycureapp.com

# Should show: "heritage=external-dns,external-dns/owner=..."

# 4. Manual DNS cleanup if needed
# Use DNS provider console to remove stale records
```

### Permission Denied Errors

**Cloudflare:**
```bash
# Error: "Unauthorized"
# Solution: Regenerate API token with correct permissions
# Zone / DNS / Edit for specific zones
```

**AWS Route53:**
```bash
# Error: "AccessDenied"
# Solution: Verify IRSA role has route53:ChangeResourceRecordSets

aws iam get-role-policy \
  --role-name external-dns-role \
  --policy-name ExternalDNSPolicy
```

**Google Cloud DNS:**
```bash
# Error: "Permission denied"
# Solution: Verify Workload Identity binding

gcloud iam service-accounts get-iam-policy \
  external-dns@PROJECT_ID.iam.gserviceaccount.com
```

**Azure DNS:**
```bash
# Error: "Authorization failed"
# Solution: Verify managed identity has DNS Zone Contributor role

az role assignment list \
  --assignee IDENTITY_PRINCIPAL_ID \
  --scope /subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.Network/dnszones/example.com
```

## Best Practices

### Security

1. **Use cloud-native auth** - IRSA, Workload Identity, Managed Identity over static credentials
2. **Least privilege tokens** - Restrict API tokens to specific zones only
3. **Rotate credentials** - Use short-lived tokens when possible
4. **Namespace isolation** - Deploy External DNS per namespace, not cluster-wide

### Configuration

1. **Domain filters** - Always specify `domainFilters` to prevent managing wrong zones
2. **TXT ownership** - Keep `registry: txt` and `txtPrefix` for record ownership tracking
3. **Sync policy** - Use `policy: sync` to clean up deleted HTTPRoutes
4. **Refresh interval** - Balance between responsiveness (1m) and API costs (5m+)

### Operations

1. **Monitor logs** - Set up alerts for External DNS errors
2. **Test in staging** - Verify DNS automation works before production
3. **Document providers** - Keep track of which namespaces use which DNS providers
4. **Backup DNS config** - Export DNS records before major changes

## Architecture

### Namespace-Scoped Deployment

```
mycure-staging namespace:
├── HTTPRoute (mycure.stg.mycureapp.com)
├── HTTPRoute (api.stg.mycureapp.com)
├── ExternalSecret (cloudflare-api-token)
└── External DNS Pod
    └── Watches HTTPRoutes in THIS namespace only
    └── Creates DNS records in Cloudflare

mycure-production namespace:
├── HTTPRoute (mycure.mycureapp.com)
├── ExternalSecret (route53-credentials)
└── External DNS Pod
    └── Watches HTTPRoutes in THIS namespace only
    └── Creates DNS records in Route53
```

**Benefits:**
- Credential isolation per namespace
- Different DNS providers per environment
- No cross-namespace access
- Easier RBAC management

### How External DNS Works

```
1. HTTPRoute created/updated
   ↓
2. External DNS watches HTTPRoute
   ↓
3. Extracts hostname from spec.hostnames
   ↓
4. Gets Gateway IP from parentRef
   ↓
5. Creates/updates A record in DNS provider
   ↓
6. Creates TXT record for ownership tracking
```

## References

- [External DNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Gateway API Specification](https://gateway-api.sigs.k8s.io/)
- [External Secrets Operator](https://external-secrets.io)
- [Cloudflare API Docs](https://developers.cloudflare.com/api/)
- [AWS Route53 API](https://docs.aws.amazon.com/Route53/latest/APIReference/)
- [Google Cloud DNS API](https://cloud.google.com/dns/docs/reference/v1)
- [Azure DNS API](https://learn.microsoft.com/azure/dns/)
