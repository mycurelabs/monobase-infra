# External DNS Helm Chart

Multi-instance External DNS for automatic DNS record management from Kubernetes resources.

## Overview

This Helm chart deploys [External DNS](https://github.com/kubernetes-sigs/external-dns) with support for **multiple instances** per namespace, enabling:

- **Multiple DNS providers** (Cloudflare, AWS Route53, Google Cloud DNS, Azure DNS, etc.)
- **Multiple accounts per provider** (e.g., multiple Cloudflare accounts with different credentials)
- **Namespace-scoped permissions** (no cluster-wide access required)
- **Automatic DNS record creation** from Gateway API HTTPRoutes and Services
- **Multi-tenant isolation** (each deployment manages its own DNS)

## Architecture

### Namespace-Scoped Design

Unlike traditional cluster-wide External DNS deployments, this chart is designed for **per-namespace deployment**:

```
deployments/
├── mycure-staging/
│   ├── values.yaml          # External DNS config for staging
│   └── secrets/
│       └── cloudflare.yaml  # SOPS-encrypted credentials
├── mycure-production/
│   ├── values.yaml          # External DNS config for production
│   └── secrets/
│       └── cloudflare.yaml  # Different credentials
└── client-acme/
    ├── values.yaml          # Client-specific DNS config
    └── secrets/
        ├── cloudflare.yaml  # Client's Cloudflare account
        └── route53.yaml     # Client's AWS account
```

Each namespace:
- Deploys its own External DNS instances
- Manages its own DNS credentials (SOPS-encrypted)
- Only watches resources in its namespace
- Has namespace-scoped RBAC (Role, not ClusterRole)

### Multi-Instance Support

Each deployment can run **multiple External DNS instances** simultaneously:

```yaml
externalDNS:
  instances:
    # Instance 1: Primary Cloudflare account
    - name: primary
      provider: cloudflare
      domainFilters: [mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-primary

    # Instance 2: Client subdomain on different Cloudflare account
    - name: client-subdomain
      provider: cloudflare
      domainFilters: [client.mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-client

    # Instance 3: AWS Route53 for different domain
    - name: aws-production
      provider: aws
      domainFilters: [example.com]
      aws:
        region: us-east-1
```

Each instance:
- Runs as separate Deployment
- Has its own ServiceAccount
- Uses different credentials
- Manages different domains (via `domainFilters`)
- Has unique TXT record ownership tracking

## Installation

### 1. Create DNS Provider Credentials

#### Cloudflare API Token

Create a Cloudflare API token with **DNS Edit** permissions:

1. Go to Cloudflare Dashboard → My Profile → API Tokens
2. Create Token → Edit zone DNS (use template)
3. Zone Resources: Include → Specific zone → `mycureapp.com`
4. Create Token

Store in Kubernetes secret:

```bash
# Create secret (will be encrypted with SOPS)
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=YOUR_TOKEN_HERE \
  --dry-run=client -o yaml > deployments/mycure-staging/secrets/cloudflare-external-dns.yaml

# Encrypt with SOPS
sops --encrypt --input-type=yaml --output-type=yaml \
  deployments/mycure-staging/secrets/cloudflare-external-dns.yaml > \
  deployments/mycure-staging/secrets/cloudflare-external-dns.enc.yaml
```

#### AWS Route53 (IRSA)

For AWS Route53, use [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html):

```yaml
instances:
  - name: aws-route53
    provider: aws
    domainFilters: [example.com]
    aws:
      region: us-east-1
      zoneType: public
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/external-dns-role
```

No secret needed - IRSA provides credentials automatically.

#### Google Cloud DNS (Workload Identity)

For Google Cloud DNS, use [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity):

```yaml
instances:
  - name: google-clouddns
    provider: google
    domainFilters: [example.com]
    google:
      project: my-gcp-project
    serviceAccount:
      annotations:
        iam.gke.io/gcp-service-account: external-dns@my-project.iam.gserviceaccount.com
```

### 2. Configure in Deployment Values

Add to `deployments/*/values.yaml`:

```yaml
externalDNS:
  enabled: true

  instances:
    - name: primary
      enabled: true
      provider: cloudflare

      domainFilters:
        - mycureapp.com

      cloudflare:
        proxied: false  # DNS only, no Cloudflare proxy
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

### 3. Deploy with ArgoCD

The chart is automatically deployed via ArgoCD ApplicationSet:

```bash
# Verify ArgoCD app is created
kubectl get app -n argocd | grep external-dns

# Check deployment status
kubectl get deployment -n mycure-staging | grep external-dns

# View logs
kubectl logs -n mycure-staging deployment/external-dns-primary
```

## Configuration

### Global Settings

Applied to all instances:

```yaml
externalDNS:
  # Global image configuration
  image:
    registry: registry.k8s.io
    repository: external-dns/external-dns
    tag: "v0.14.0"
    pullPolicy: IfNotPresent

  # Global behavior
  global:
    # Sources to watch (Gateway API + Services)
    sources:
      - gateway-httproute
      - gateway-tcproute
      - service

    # Policy: sync (create+update+delete) or upsert-only (no delete)
    policy: sync

    # Registry for ownership tracking
    registry: txt
    txtPrefix: "external-dns-"

    # Sync interval
    interval: 1m

    # Trigger sync on Kubernetes events (faster than polling)
    triggerLoopOnEvent: true

    # Logging
    logLevel: info
    logFormat: json
```

### Instance Configuration

Each instance in the `instances[]` array:

```yaml
instances:
  - name: instance-name          # Required: Unique name within namespace
    enabled: true                # Optional: Default true
    provider: cloudflare         # Required: DNS provider

    # Domain filtering (highly recommended)
    domainFilters:
      - mycureapp.com
      - "*.mycureapp.com"

    # Provider-specific configuration
    cloudflare:
      proxied: false             # Cloudflare proxy (orange cloud)
      zoneidFilters: []          # Filter by zone ID (optional)
      apiTokenSecretRef:
        name: cloudflare-token
        key: api-token

    # Resource limits
    resources:
      requests:
        cpu: 10m
        memory: 32Mi
      limits:
        cpu: 50m
        memory: 64Mi

    # ServiceAccount annotations (for cloud IAM)
    serviceAccount:
      annotations: {}
```

### Provider-Specific Examples

#### Cloudflare

```yaml
instances:
  - name: cloudflare-primary
    provider: cloudflare
    domainFilters: [mycureapp.com]
    cloudflare:
      proxied: false              # DNS only
      apiTokenSecretRef:
        name: cloudflare-token
        key: api-token
```

**Required secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-token
stringData:
  api-token: YOUR_CLOUDFLARE_API_TOKEN
```

#### AWS Route53

```yaml
instances:
  - name: route53-production
    provider: aws
    domainFilters: [example.com]
    aws:
      region: us-east-1
      zoneType: public            # public or private
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/external-dns
```

**IAM Policy required:**
```json
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
      "Resource": ["*"]
    }
  ]
}
```

#### Google Cloud DNS

```yaml
instances:
  - name: clouddns-production
    provider: google
    domainFilters: [example.com]
    google:
      project: my-gcp-project-id
    serviceAccount:
      annotations:
        iam.gke.io/gcp-service-account: external-dns@my-project.iam.gserviceaccount.com
```

**GCP IAM binding:**
```bash
gcloud projects add-iam-policy-binding my-project \
  --member=serviceAccount:external-dns@my-project.iam.gserviceaccount.com \
  --role=roles/dns.admin
```

#### Azure DNS

```yaml
instances:
  - name: azure-dns
    provider: azure
    domainFilters: [example.com]
    azure:
      resourceGroup: my-dns-rg
      tenantId: YOUR_TENANT_ID
      subscriptionId: YOUR_SUBSCRIPTION_ID
      aadClientId: YOUR_CLIENT_ID
      aadClientSecretSecretRef:
        name: azure-dns-secret
        key: client-secret
```

#### DigitalOcean

```yaml
instances:
  - name: digitalocean-dns
    provider: digitalocean
    domainFilters: [example.com]
    digitalocean:
      apiTokenSecretRef:
        name: do-api-token
        key: token
```

## Use Cases

### 1. Single Provider, Single Account

Most common scenario - manage one domain on one DNS provider:

```yaml
externalDNS:
  instances:
    - name: primary
      provider: cloudflare
      domainFilters: [mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token
```

### 2. Multiple Domains, Same Provider

Multiple Cloudflare accounts for different domains:

```yaml
externalDNS:
  instances:
    - name: primary-domain
      provider: cloudflare
      domainFilters: [mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-primary

    - name: client-domain
      provider: cloudflare
      domainFilters: [client-example.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-client
```

### 3. Multiple Providers

Hybrid cloud setup with different DNS providers:

```yaml
externalDNS:
  instances:
    - name: cloudflare-main
      provider: cloudflare
      domainFilters: [mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token

    - name: aws-backup
      provider: aws
      domainFilters: [mycureapp.net]
      aws:
        region: us-east-1
      serviceAccount:
        annotations:
          eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/external-dns
```

### 4. Multi-Tenant with Subdomain Delegation

Each tenant manages their subdomain with own Cloudflare account:

```yaml
externalDNS:
  instances:
    - name: main-domain
      provider: cloudflare
      domainFilters: [mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-main

    - name: tenant-acme
      provider: cloudflare
      domainFilters: [acme.mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-acme

    - name: tenant-example
      provider: cloudflare
      domainFilters: [example.mycureapp.com]
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-token-example
```

## How It Works

### 1. Gateway API HTTPRoute → DNS Record

When you create an HTTPRoute:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api
  namespace: mycure-staging
spec:
  hostnames:
    - api.stg.mycureapp.com
  parentRefs:
    - name: shared-gateway
      namespace: gateway-system
```

External DNS automatically:
1. Watches the HTTPRoute resource
2. Extracts hostname: `api.stg.mycureapp.com`
3. Gets LoadBalancer IP from Gateway Service: `188.166.196.111`
4. Creates DNS A record in Cloudflare:
   ```
   api.stg.mycureapp.com → 188.166.196.111
   ```
5. Creates TXT record for ownership tracking:
   ```
   TXT external-dns-api.stg.mycureapp.com → "heritage=external-dns,owner=mycure-staging-primary"
   ```

### 2. Service with LoadBalancer → DNS Record

For Services with type LoadBalancer:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    external-dns.alpha.kubernetes.io/hostname: service.stg.mycureapp.com
spec:
  type: LoadBalancer
  loadBalancerIP: 203.0.113.42
```

External DNS creates:
```
service.stg.mycureapp.com → 203.0.113.42
```

### 3. Ownership and Conflict Prevention

Each External DNS instance uses TXT records to track ownership:

- **TXT prefix**: `external-dns-` (configurable)
- **Owner ID**: `{namespace}-{instance-name}`
- **Example**: `mycure-staging-primary`

This prevents conflicts when:
- Multiple instances manage overlapping domains
- Manually created DNS records exist
- Migration from manual to automated DNS

## Monitoring

### Check DNS Record Creation

```bash
# View External DNS logs
kubectl logs -n mycure-staging deployment/external-dns-primary

# Expected output:
# time="2025-01-15T10:30:00Z" level=info msg="Applying provider record filter for domains: [mycureapp.com]"
# time="2025-01-15T10:30:01Z" level=info msg="Desired change: CREATE api.stg.mycureapp.com A [Id: /hostedzone/Z1234567890ABC]"
# time="2025-01-15T10:30:02Z" level=info msg="2 record(s) in zone mycureapp.com were successfully updated"
```

### Verify DNS Records in Cloudflare

```bash
# Check DNS resolution
dig api.stg.mycureapp.com

# Check TXT ownership record
dig TXT external-dns-api.stg.mycureapp.com
```

### Common Log Messages

**Successful sync:**
```
level=info msg="All records are already up to date"
```

**Creating new record:**
```
level=info msg="Desired change: CREATE api.stg.mycureapp.com A"
level=info msg="2 record(s) were successfully updated"
```

**Permission denied:**
```
level=error msg="failed to list records: HTTP 403: Forbidden"
```
→ Check API token permissions

**Domain filter blocked:**
```
level=info msg="Skipping endpoint api.example.com because it doesn't match domain filter [mycureapp.com]"
```
→ Expected - domain filters working correctly

## Troubleshooting

### DNS Records Not Created

1. **Check External DNS is running:**
   ```bash
   kubectl get pods -n mycure-staging | grep external-dns
   ```

2. **Check logs for errors:**
   ```bash
   kubectl logs -n mycure-staging deployment/external-dns-primary
   ```

3. **Verify HTTPRoute has correct hostname:**
   ```bash
   kubectl get httproute -n mycure-staging -o yaml
   ```

4. **Check domain filters:**
   ```bash
   # Ensure hostname matches domain filter
   # If filter is "mycureapp.com", then "api.stg.mycureapp.com" will NOT match
   # Use "*.mycureapp.com" or specific "stg.mycureapp.com"
   ```

5. **Verify credentials:**
   ```bash
   # Check secret exists
   kubectl get secret cloudflare-api-token -n mycure-staging

   # Test API token manually
   curl -X GET "https://api.cloudflare.com/client/v4/zones" \
     -H "Authorization: Bearer YOUR_TOKEN"
   ```

### Permission Errors

**Error:** `failed to list zones: HTTP 403: Forbidden`

**Solution:** Check Cloudflare API token permissions:
- Token needs **Zone:DNS:Edit** permission
- Token must include the specific zone (domain)

**Error:** `error listing hosted zones: AccessDenied`

**Solution:** Check AWS IAM role/policy:
- ServiceAccount annotation has correct role ARN
- Role has Route53 permissions
- Trust policy allows OIDC provider

### Records Not Updating

**Issue:** External DNS logs show updates but DNS not changing

**Possible causes:**
1. **Cloudflare proxy enabled** - Disable with `proxied: false`
2. **TTL too long** - External DNS sets 300s TTL by default
3. **Multiple owners conflict** - Check TXT records for ownership
4. **Policy is upsert-only** - Change to `policy: sync` to allow deletions

### Multiple Instances Conflict

**Error:** `skipping endpoint because it's not owned by this instance`

**This is expected behavior** when:
- Multiple instances have overlapping domain filters
- One instance created the record first

**Solution:**
- Use non-overlapping domain filters
- Each instance should manage distinct domains/subdomains

## Security Considerations

### Namespace-Scoped RBAC

This chart uses **Role** (not ClusterRole) for security:

```yaml
# Role grants permissions ONLY in deployment namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: external-dns
  namespace: mycure-staging
```

Benefits:
- Cannot access resources in other namespaces
- Limits blast radius of compromised credentials
- Perfect for multi-tenant clusters

### Credential Management

**Always encrypt DNS provider credentials with SOPS:**

```bash
# Create secret
kubectl create secret generic cloudflare-token \
  --from-literal=api-token=YOUR_TOKEN \
  --dry-run=client -o yaml > secret.yaml

# Encrypt with SOPS
sops --encrypt --input-type=yaml --output-type=yaml \
  secret.yaml > secret.enc.yaml

# Commit encrypted version
git add secret.enc.yaml
git commit -m "Add Cloudflare credentials (encrypted)"
```

**Never commit plaintext secrets to Git!**

### API Token Least Privilege

**Cloudflare:**
- Use API **tokens** (not API keys)
- Limit to specific zone
- Only grant DNS:Edit permission

**AWS Route53:**
- Use IRSA (no static credentials)
- Limit to specific hosted zone ARNs
- Use `route53:ChangeResourceRecordSets` not `route53:*`

**Google Cloud DNS:**
- Use Workload Identity (no service account keys)
- Grant `roles/dns.admin` only on specific DNS zones

## Values Reference

### Root Level

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable External DNS deployment |
| `image.registry` | string | `registry.k8s.io` | Container registry |
| `image.repository` | string | `external-dns/external-dns` | Image repository |
| `image.tag` | string | `v0.14.0` | Image tag |
| `image.pullPolicy` | string | `IfNotPresent` | Image pull policy |

### Global Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `global.sources` | list | `[gateway-httproute, service]` | Kubernetes sources to watch |
| `global.policy` | string | `sync` | Policy: `sync` or `upsert-only` |
| `global.registry` | string | `txt` | Ownership registry type |
| `global.txtPrefix` | string | `external-dns-` | TXT record prefix |
| `global.interval` | duration | `1m` | Sync interval |
| `global.triggerLoopOnEvent` | bool | `true` | Trigger on K8s events |
| `global.logLevel` | string | `info` | Log level: debug/info/warn/error |
| `global.logFormat` | string | `json` | Log format: json/text |

### Instance Configuration

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `instances[].name` | string | ✅ | Unique instance name |
| `instances[].enabled` | bool | ❌ | Enable this instance (default: true) |
| `instances[].provider` | string | ✅ | DNS provider (cloudflare/aws/google/azure/digitalocean) |
| `instances[].domainFilters` | list | ❌ | Domain filters (highly recommended) |
| `instances[].resources` | object | ❌ | Resource requests/limits |
| `instances[].serviceAccount.annotations` | object | ❌ | ServiceAccount annotations (for cloud IAM) |

### Provider-Specific

**Cloudflare:**
| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `cloudflare.proxied` | bool | ❌ | Enable Cloudflare proxy (default: false) |
| `cloudflare.zoneidFilters` | list | ❌ | Filter by zone ID |
| `cloudflare.apiTokenSecretRef.name` | string | ✅ | Secret name with API token |
| `cloudflare.apiTokenSecretRef.key` | string | ❌ | Secret key (default: api-token) |

**AWS:**
| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `aws.region` | string | ❌ | AWS region |
| `aws.zoneType` | string | ❌ | Zone type: public/private (default: public) |

**Google:**
| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `google.project` | string | ❌ | GCP project ID |

## Version History

### v1.0.0 (2025-01-15)

Initial release with:
- Multi-instance architecture
- Namespace-scoped RBAC
- Support for Cloudflare, AWS, Google, Azure, DigitalOcean
- Gateway API HTTPRoute source
- SOPS secrets integration

## Links

- [External DNS GitHub](https://github.com/kubernetes-sigs/external-dns)
- [External DNS Providers](https://github.com/kubernetes-sigs/external-dns#status-of-providers)
- [Gateway API Docs](https://gateway-api.sigs.k8s.io/)
- [SOPS Documentation](https://github.com/getsops/sops)
