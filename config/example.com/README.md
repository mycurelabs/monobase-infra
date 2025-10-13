# Reference Configuration (example.com)

This directory contains **REFERENCE CONFIGURATION** showing all available parameters for the LFH Infrastructure template.

## ⚠️ This is NOT a real client configuration

This is a **template and reference** only. Do not deploy this directly!

## For New Clients

### 1. Copy This Directory

```bash
# Use the bootstrap script (recommended)
./scripts/new-client-config.sh yourclient yourdomain.com

# OR copy manually
cp -r config/example.com config/yourclient
```

### 2. Customize Your Configuration

Edit the copied files and replace:

- `example.com` → your actual domain
- `example` → your client identifier
- `example-prod` / `example-staging` → your namespace names
- Image tags: `"latest"` → specific versions (e.g., `"5.215.2"`)
- Resource limits → your actual requirements
- Storage sizes → based on your data volume
- Replica counts → based on your scale

### 3. Configure Secrets

Edit `secrets-mapping.yaml` with your KMS secret paths:

- AWS Secrets Manager paths
- Azure Key Vault URIs
- GCP Secret Manager names
- SOPS encrypted file paths

### 4. Commit to Your Fork

```bash
git add config/yourclient/
git commit -m "Add YourClient configuration"
git push origin main
```

## Configuration Files

### values-staging.yaml

Minimal configuration for staging/development environments:
- Small replica counts (1-2)
- Smaller resource limits
- Mailpit enabled for email testing
- Optional components disabled

### values-production.yaml

Production-ready configuration:
- High availability (3+ replicas)
- Production resource limits
- All required security controls
- Optional components (enable as needed)

### secrets-mapping.yaml

Maps Kubernetes secret keys to KMS paths:
- Database credentials
- API keys
- SMTP credentials
- S3/MinIO credentials
- JWT signing keys

## Key Configuration Patterns

### Namespace Strategy

Use `{client}-{environment}` pattern:
- `yourclient-staging`
- `yourclient-production`

Each namespace is isolated and can have independent:
- Resource quotas
- Network policies
- RBAC permissions

### Hostname Flexibility

Each service hostname is fully configurable:

```yaml
global:
  domain: example.com  # Default base domain

hapihub:
  gateway:
    hostname: ""  # Empty = uses api.example.com (default)
    # OR set explicitly: api.custom-domain.com

syncd:
  gateway:
    hostname: sync.example.com  # Explicit

mycureapp:
  gateway:
    hostname: ""  # Uses app.example.com (default)
```

### Optional Components

Enable only what you need:

```yaml
# Sync service - enable for offline/mobile sync
syncd:
  enabled: true  # Set false if not needed

# Search engine - enable for full-text search
typesense:
  enabled: true  # Set false if not needed

# Self-hosted S3 - enable if cost-sensitive, disable for AWS S3
minio:
  enabled: true  # Set false to use external S3

# Email testing - enable for dev/staging ONLY
mailpit:
  enabled: false  # NEVER enable in production

# Monitoring - enable for production visibility
monitoring:
  enabled: false  # Enable when needed
```

## Best Practices

### Image Tags

❌ **Never use in production:**
```yaml
image:
  tag: "latest"
```

✅ **Always pin versions:**
```yaml
image:
  tag: "5.215.2"  # Specific, tested version
```

### Resource Limits

Start with reference values and adjust based on actual usage:

```yaml
resources:
  requests:
    cpu: 500m      # Guaranteed resources
    memory: 1Gi
  limits:
    cpu: 2         # Maximum allowed
    memory: 4Gi
```

Monitor actual usage and tune accordingly.

### Storage Sizing

Base storage sizes on data growth projections:

```yaml
mongodb:
  persistence:
    size: 50Gi    # Start small, expand as needed

minio:
  persistence:
    size: 250Gi   # Per node (6 nodes = 1TB usable with EC:2)
```

Note: Longhorn supports volume expansion without downtime.

### High Availability

Production should always use:
- MongoDB: 3 replicas (replica set)
- HapiHub: 2-3 replicas (load balanced)
- MinIO: 6+ nodes (distributed, erasure coded)

```yaml
mongodb:
  replicas: 3  # Required for HA

hapihub:
  replicas: 3  # Minimum 2 for HA

minio:
  replicas: 6  # For 1TB usable with EC:2
```

## Next Steps

1. ✅ Copy this directory to `config/yourclient/`
2. ✅ Customize all values (domain, namespaces, images, resources)
3. ✅ Configure secrets mapping for your KMS
4. ✅ Commit to your forked repository
5. ✅ Deploy infrastructure (one-time setup)
6. ✅ Deploy applications via ArgoCD

See **[CLIENT-ONBOARDING.md](../../docs/CLIENT-ONBOARDING.md)** for detailed deployment instructions.
