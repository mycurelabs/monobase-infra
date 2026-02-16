# Deployment Workflow Guide

## Deployment File Structure

Each file in `values/deployments/` defines a complete tenant deployment.
Filename determines namespace: `mycure-production.yaml` → namespace `mycure-production`.

### Required Fields

```yaml
global:
  domain: localfirsthealth.com        # Base domain for all apps
  namespace: mycure-production         # Must match filename
  environment: production              # production | staging | development
  nodePool: "production"               # Node affinity target
  gateway:
    name: shared-gateway               # Gateway resource (always shared-gateway)
    namespace: gateway-system           # Gateway namespace
  storage:
    provider: ""                       # Storage provider (optional)
    className: ""                      # StorageClass override (optional)
```

### Application Sections

Each application has its own section with `.enabled` toggle:

```yaml
hapihub:
  enabled: true                        # Deploy this app
  image:
    repository: ghcr.io/mycurelabs/hapihub
    tag: "10.11.15"                    # Version to deploy
    pullPolicy: IfNotPresent
  replicaCount: 1
  resources:
    requests: { cpu: 1000m, memory: 768Mi }
    limits: { cpu: "2", memory: 2Gi }
  gateway:
    hostname: ""                       # Auto-derived from global.domain
    sectionName: https-lfh             # Listener name for domain routing
    timeouts:
      request: "60s"
  autoscaling:
    enabled: true
    maxReplicas: 3
  externalSecrets:
    enabled: true
    secretStore: gcp-secretstore
    secretStoreKind: ClusterSecretStore
    refreshInterval: 1h
    secrets: [...]                     # Secret key mappings
  mongodb:
    enabled: true
    serviceName: mongodb
    database: hapihub
    username: root
    replicaSet: rs0
```

### Database Sections (Bitnami Subcharts)

```yaml
mongodb:
  enabled: true
  fullnameOverride: "mongodb"
  architecture: replicaset
  replicaCount: 1
  image:
    repository: bitnamilegacy/mongodb
    tag: 7.0.15-debian-12-r0
  auth:
    rootUser: root
    existingSecret: mongodb            # Pre-created via database-secrets chart
  persistence:
    enabled: true
    size: 100Gi
  resources: { ... }

postgresql:
  enabled: false                       # Disabled unless API is used
  # Similar structure to mongodb
```

### Optional Sections

```yaml
valkey:                                # Redis-compatible cache
  enabled: false
  architecture: standalone

minio:                                 # S3-compatible object storage
  enabled: false
  mode: standalone

mailpit:                               # Email testing (staging only)
  enabled: false

backup:                                # Velero backup for this namespace
  enabled: false

podSecurityStandards:
  enabled: true
  level: restricted

resourceQuotas:
  enabled: false
```

## Values Flow

```
values/deployments/mycure-production.yaml
  ↓ (referenced by ApplicationSet)
ArgoCD Application (mycure-production-root)
  ↓ (Helm rendering with these values)
argocd/applications/ templates
  ↓ (creates per-chart ArgoCD Applications)
Individual chart deployments (hapihub, mycure, syncd, etc.)
  ↓ (each chart reads global + its section from values)
Kubernetes resources (Deployments, Services, HTTPRoutes, etc.)
```

## Environment-Specific Patterns

### Production
- `global.environment: production`
- `global.nodePool: "production"`
- HPA enabled for hapihub and syncd
- ExternalSecrets enabled (full secret set)
- Higher resource limits
- `gateway.sectionName: https-lfh`

### Staging
- `global.environment: staging`
- `global.nodePool: "staging"`
- HPA disabled (save resources)
- ExternalSecrets may be partial
- Lower resource limits
- `gateway.sectionName: https-lfh-stg`
- Mailpit enabled for email testing
- MinIO enabled for local object storage

## Common Operations

### Bump Image Version
```yaml
# Edit the specific app's image.tag
hapihub:
  image:
    tag: "10.12.0"  # was "10.11.15"
```

### Enable/Disable Component
```yaml
# Toggle the .enabled flag
dentalemon:
  enabled: true  # was false
```

### Add External Secret
```yaml
externalSecrets:
  secrets:
    - secretKey: NEW_SECRET_KEY
      remoteKey: mycure-production-new-secret
```

### Change Resources
```yaml
hapihub:
  resources:
    requests:
      cpu: 2000m      # was 1000m
      memory: 1Gi     # was 768Mi
    limits:
      cpu: "4"        # was "2"
      memory: 4Gi     # was 2Gi
```
