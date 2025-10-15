# Values Reference

Complete parameter reference for all Monobase Infrastructure configuration values.

## Global Parameters

Used across all charts and configurations.

### global.domain
- **Type:** string
- **Required:** Yes
- **Example:** `myclient.com`
- **Description:** Base domain for all services. Used as default for service hostnames.
- **Pattern:** Valid domain name (e.g., example.com)

### global.namespace
- **Type:** string
- **Required:** Yes
- **Example:** `myclient-prod`
- **Description:** Kubernetes namespace for deployment. Use `{client}-{env}` pattern.
- **Pattern:** Lowercase alphanumeric with hyphens

### global.environment
- **Type:** string
- **Required:** Yes
- **Options:** `development`, `staging`, `production`
- **Description:** Environment identifier for deployment

### global.gateway.name
- **Type:** string
- **Default:** `shared-gateway`
- **Description:** Name of shared Gateway resource in gateway-system namespace

### global.gateway.namespace
- **Type:** string
- **Default:** `gateway-system`
- **Description:** Namespace where shared Gateway is deployed

---

## HapiHub Parameters

### hapihub.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable or disable HapiHub deployment

### hapihub.replicaCount
- **Type:** integer
- **Default:** `2`
- **Minimum:** `1`
- **Production:** `3` (for HA)
- **Description:** Number of HapiHub pod replicas

### hapihub.image.repository
- **Type:** string
- **Default:** `ghcr.io/YOUR-ORG/hapihub`
- **Description:** Container image repository

### hapihub.image.tag
- **Type:** string
- **Default:** `5.215.2`
- **Production:** Pin specific version (e.g., `5.215.2`)
- **Staging:** Can use `latest` for testing
- **Description:** Container image tag

### hapihub.image.pullPolicy
- **Type:** string
- **Default:** `IfNotPresent`
- **Options:** `Always`, `IfNotPresent`, `Never`

### hapihub.resources.requests.cpu
- **Type:** string
- **Default:** `500m`
- **Staging:** `250m`
- **Production:** `1` (1 CPU)
- **Description:** Guaranteed CPU allocation

### hapihub.resources.requests.memory
- **Type:** string
- **Default:** `1Gi`
- **Staging:** `512Mi`
- **Production:** `2Gi`
- **Description:** Guaranteed memory allocation

### hapihub.resources.limits.cpu
- **Type:** string
- **Default:** `2`
- **Production:** `2-4`
- **Description:** Maximum CPU allowed

### hapihub.resources.limits.memory
- **Type:** string
- **Default:** `4Gi`
- **Production:** `4-8Gi`
- **Description:** Maximum memory allowed

### hapihub.gateway.hostname
- **Type:** string
- **Default:** Empty (uses `api.{global.domain}`)
- **Example:** `api.myclient.com` or `api.custom-domain.com`
- **Description:** Custom hostname for HapiHub API. If empty, defaults to api.{global.domain}

### hapihub.autoscaling.enabled
- **Type:** boolean
- **Default:** `false`
- **Production:** `true`
- **Description:** Enable Horizontal Pod Autoscaler

### hapihub.autoscaling.minReplicas
- **Type:** integer
- **Default:** `2`
- **Production:** `3`

### hapihub.autoscaling.maxReplicas
- **Type:** integer
- **Default:** `10`
- **Production:** `5-10`

### hapihub.autoscaling.targetCPUUtilizationPercentage
- **Type:** integer
- **Default:** `70`
- **Range:** 1-100

### hapihub.podDisruptionBudget.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (required for HA)

### hapihub.podDisruptionBudget.minAvailable
- **Type:** integer
- **Default:** `1`
- **Description:** Minimum pods that must remain available during disruptions

### hapihub.networkPolicy.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (required for security)

### hapihub.externalSecrets.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Sync secrets from KMS via External Secrets Operator

---

## Syncd Parameters

### syncd.enabled
- **Type:** boolean
- **Default:** `false`
- **Description:** Enable Syncd (optional component for offline sync)

### syncd.replicaCount
- **Type:** integer
- **Default:** `2`
- **Production:** `2-3`

### syncd.image.repository
- **Type:** string
- **Default:** `ghcr.io/YOUR-ORG/syncd`

### syncd.image.tag
- **Type:** string
- **Default:** `1.2.0`
- **Production:** Pin specific version

### syncd.gateway.hostname
- **Type:** string
- **Default:** Empty (uses `sync.{global.domain}`)
- **Example:** `sync.myclient.com`

### syncd.resources.requests.cpu
- **Type:** string
- **Default:** `500m`
- **Production:** `500m-1`

### syncd.resources.requests.memory
- **Type:** string
- **Default:** `1Gi`
- **Production:** `1-2Gi`

---

## MyCureApp Parameters

### mycureapp.enabled
- **Type:** boolean
- **Default:** `true`

### mycureapp.replicaCount
- **Type:** integer
- **Default:** `2`
- **Production:** `2-3`

### mycureapp.image.repository
- **Type:** string
- **Default:** `ghcr.io/YOUR-ORG/mycureapp`

### mycureapp.image.tag
- **Type:** string
- **Default:** `1.0.0`

### mycureapp.gateway.hostname
- **Type:** string
- **Default:** Empty (uses `app.{global.domain}`)

### mycureapp.resources.requests.cpu
- **Type:** string
- **Default:** `200m`
- **Production:** `200m-500m`

### mycureapp.resources.requests.memory
- **Type:** string
- **Default:** `512Mi`
- **Production:** `512Mi-1Gi`

---

## MongoDB Parameters

### mongodb.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Deploy MongoDB (required for HapiHub)

### mongodb.architecture
- **Type:** string
- **Default:** `replicaset`
- **Options:** `standalone`, `replicaset`
- **Production:** `replicaset` (required for HA)

### mongodb.replicaCount
- **Type:** integer
- **Default:** `3`
- **Staging:** `1`
- **Production:** `3` (minimum for HA)

### mongodb.auth.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (required)

### mongodb.auth.existingSecret
- **Type:** string
- **Default:** `mongodb-credentials`
- **Description:** Secret name containing MongoDB passwords (managed by External Secrets)

### mongodb.persistence.enabled
- **Type:** boolean
- **Default:** `true`

### mongodb.persistence.storageClass
- **Type:** string
- **Default:** `longhorn`

### mongodb.persistence.size
- **Type:** string
- **Default:** `100Gi`
- **Staging:** `20Gi`
- **Production:** `50Gi-500Gi` (based on data volume)

### mongodb.resources.requests.cpu
- **Type:** string
- **Default:** `1.5`
- **Production:** `1.5-3`

### mongodb.resources.requests.memory
- **Type:** string
- **Default:** `6Gi`
- **Production:** `6-8Gi`

### mongodb.tls.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (recommended for security and compliance)

---

## MinIO Parameters (Optional)

### minio.enabled
- **Type:** boolean
- **Default:** `false`
- **Description:** Deploy self-hosted MinIO or use external S3
- **Enable when:** <1TB data, cost-sensitive, full control needed
- **Disable when:** >1TB data, using AWS S3/GCS/Azure Blob

### minio.mode
- **Type:** string
- **Default:** `distributed`
- **Options:** `standalone`, `distributed`
- **Staging:** `standalone`
- **Production:** `distributed` (for HA)

### minio.statefulset.replicaCount
- **Type:** integer
- **Default:** `6`
- **Description:** Number of MinIO nodes (6 for 1TB usable with EC:2)

### minio.persistence.size
- **Type:** string
- **Default:** `250Gi`
- **Description:** Storage per node (6 × 250Gi = 1.5TB raw → ~1TB usable with EC:2)

### minio.gateway.hostname
- **Type:** string
- **Default:** Empty (uses `storage.{global.domain}`)

---

## Typesense Parameters (Optional)

### typesense.enabled
- **Type:** boolean
- **Default:** `false`
- **Description:** Deploy Typesense search engine

### typesense.replicas
- **Type:** integer
- **Default:** `3`
- **Production:** `3` (for HA)

### typesense.persistence.size
- **Type:** string
- **Default:** `50Gi`
- **Description:** Search index storage

---

## External Secrets Parameters

### externalSecrets.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable External Secrets Operator for KMS integration

### externalSecrets.provider
- **Type:** string
- **Required:** Yes
- **Options:** `aws`, `azure`, `gcp`, `sops`
- **Description:** KMS provider

### externalSecrets.aws.region
- **Type:** string
- **Example:** `us-east-1`
- **Description:** AWS region for Secrets Manager

### externalSecrets.aws.secretStore
- **Type:** string
- **Example:** `myclient-prod-secretstore`
- **Description:** SecretStore resource name

### externalSecrets.azure.vaultUrl
- **Type:** string
- **Example:** `https://myclient-kv.vault.azure.net/`
- **Description:** Azure Key Vault URL

### externalSecrets.gcp.projectId
- **Type:** string
- **Example:** `myclient-prod-123456`
- **Description:** GCP project ID

---

## Network Policy Parameters

### networkPolicies.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (recommended for security and compliance)
- **Description:** Enable NetworkPolicies for zero-trust networking

### networkPolicies.defaultDeny
- **Type:** boolean
- **Default:** `true`
- **Description:** Default-deny all traffic (explicit allow rules required)

---

## Pod Security Parameters

### podSecurityStandards.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (required)

### podSecurityStandards.level
- **Type:** string
- **Default:** `restricted`
- **Options:** `privileged`, `baseline`, `restricted`
- **Production:** `restricted` (highest security)

---

## Monitoring Parameters

### monitoring.enabled
- **Type:** boolean
- **Default:** `false`
- **Production:** `true` (recommended)
- **Staging:** `false` (to save resources)

### monitoring.prometheus.retention
- **Type:** string
- **Default:** `15d`
- **Description:** Metrics retention period

### monitoring.prometheus.storage
- **Type:** string
- **Default:** `50Gi`
- **Description:** Prometheus PVC size

### monitoring.grafana.enabled
- **Type:** boolean
- **Default:** `false`
- **Production:** `true`

---

## Backup Parameters

### backup.enabled
- **Type:** boolean
- **Default:** `false`
- **Production:** `true` (critical for production)

### backup.s3Bucket
- **Type:** string
- **Example:** `myclient-prod-backups`
- **Description:** S3 bucket for Velero backups

### backup.region
- **Type:** string
- **Example:** `us-east-1`

### backup.schedules.hourly.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Hourly backups (72h retention)

### backup.schedules.daily.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Daily backups (30d retention)

### backup.schedules.weekly.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Weekly archives (90d retention for compliance)

---

## Resource Quota Parameters

### resourceQuotas.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true`

### resourceQuotas.limits.cpu
- **Type:** string
- **Default:** `"50"`
- **Description:** Total CPU limit for namespace

### resourceQuotas.limits.memory
- **Type:** string
- **Default:** `"100Gi"`
- **Description:** Total memory limit for namespace

### resourceQuotas.limits.persistentvolumeclaims
- **Type:** string
- **Default:** `"20"`
- **Description:** Maximum number of PVCs in namespace

### resourceQuotas.limits.pods
- **Type:** string
- **Default:** `"100"`
- **Description:** Maximum number of pods in namespace

---

## Compliance Parameters

### compliance.enabled
- **Type:** boolean
- **Default:** `true`
- **Production:** `true` (for regulated industries)

### compliance.auditLogging.enabled
- **Type:** boolean
- **Default:** `true`
- **Description:** Enable audit logging

### compliance.auditLogging.retention
- **Type:** string
- **Default:** `2555d` (7 years)
- **Description:** Audit log retention period (configurable per compliance requirements)

### compliance.encryption.atRest
- **Type:** string
- **Default:** `required`
- **Options:** `required`, `optional`

### compliance.encryption.inTransit
- **Type:** string
- **Default:** `required`

---

## Configuration Examples

### Minimal Configuration (Staging)

```yaml
global:
  domain: myclient.com
  namespace: myclient-staging
  environment: staging

hapihub:
  enabled: true
  replicas: 1
  image:
    tag: "latest"

mycureapp:
  enabled: true
  replicas: 1

mongodb:
  enabled: true
  replicaCount: 1
  persistence:
    size: 20Gi
```

### Production Configuration (HA)

```yaml
global:
  domain: myclient.com
  namespace: myclient-prod
  environment: production

hapihub:
  enabled: true
  replicas: 3
  image:
    tag: "5.215.2"  # Pin version
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
  resources:
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 2
      memory: 4Gi

mongodb:
  enabled: true
  architecture: replicaset
  replicaCount: 3
  persistence:
    size: 100Gi

monitoring:
  enabled: true

backup:
  enabled: true
  s3Bucket: myclient-prod-backups

networkPolicies:
  enabled: true

podSecurityStandards:
  enabled: true
  level: restricted
```

---

## Reference Files

For complete examples, see:
- `config/example.com/values-staging.yaml` - All staging parameters
- `config/example.com/values-production.yaml` - All production parameters
- `config/example.com/secrets-mapping.yaml` - Secret mappings

For chart-specific schemas, see:
- `charts/hapihub/values.schema.json`
- `charts/syncd/values.schema.json`
- `charts/mycureapp/values.schema.json`
