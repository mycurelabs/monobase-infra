---
name: helm
description: Helm chart management for 21 charts
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Helm Chart Management Skill

## Kubeconfig Resolution

All helm commands use this priority order:
1. Explicit `--kubeconfig` flag (if provided)
2. `KUBECONFIG` environment variable
3. **Default:** `~/.kube/mycure-doks-main` (if exists)
4. Interactive selection (if multiple configs in `~/.kube/`)
5. Fall back to `~/.kube/config`

Set kubeconfig before running commands:
```bash
export KUBECONFIG=~/.kube/mycure-doks-main
```

---

## Quick Operations

### diff — Compare local chart changes vs deployed release
```bash
# Requires helm-diff plugin: helm plugin install https://github.com/databus23/helm-diff

# Diff against deployed release
helm diff upgrade {release} charts/{chart} -f values/deployments/{deployment}.yaml -n {namespace}

# Diff with additional values
helm diff upgrade {release} charts/{chart} -f values/deployments/{deployment}.yaml -f override.yaml -n {namespace}

# Show only changes (no context)
helm diff upgrade {release} charts/{chart} -f values/deployments/{deployment}.yaml -n {namespace} --no-color

# Examples:
helm diff upgrade api charts/api -f values/deployments/mycure-staging.yaml -n mycure-staging
helm diff upgrade hapihub charts/hapihub -f values/deployments/mycure-production.yaml -n mycure-production
```

### values — Get values from deployed release
```bash
# Get user-supplied values
helm get values {release} -n {namespace}

# Get all values (including defaults)
helm get values {release} -n {namespace} -a

# Output as YAML
helm get values {release} -n {namespace} -o yaml

# Examples:
helm get values api -n mycure-staging
helm get values hapihub -n mycure-production -a -o yaml
```

### template — Render templates locally for validation
```bash
# Basic template rendering
helm template {release} charts/{chart} -f values/deployments/{deployment}.yaml

# With debug output (shows template processing)
helm template {release} charts/{chart} -f values/deployments/{deployment}.yaml --debug

# Validate against cluster (dry-run)
helm template {release} charts/{chart} -f values/deployments/{deployment}.yaml --validate

# Output to file for inspection
helm template {release} charts/{chart} -f values/deployments/{deployment}.yaml > rendered.yaml

# Examples:
helm template api charts/api -f values/deployments/mycure-staging.yaml --debug
helm template hapihub charts/hapihub -f values/deployments/mycure-production.yaml --validate
```

### lint — Validate chart structure
```bash
# Lint single chart
helm lint charts/{chart}

# Lint with values
helm lint charts/{chart} -f values/deployments/{deployment}.yaml

# Lint all charts
for chart in charts/*/; do helm lint "$chart"; done

# Examples:
helm lint charts/api
helm lint charts/hapihub -f values/deployments/mycure-staging.yaml
```

### history — View release history
```bash
# Show release history
helm history {release} -n {namespace}

# Examples:
helm history api -n mycure-staging
helm history hapihub -n mycure-production
```

---

## Current Charts

```
!ls -d charts/*/
```

## Chart Categories

### Healthcare Applications (10)
- `hapihub` — HapiHub API (Bun/MongoDB, healthcare backend)
- `mycure` — MyCure frontend (Vue.js patient app)
- `mycurelocal` — MyCure Local (local-first variant)
- `mycurev8` — MyCure v8 (legacy frontend)
- `mycure-myaccount` — MyCure MyAccount portal
- `mycure-deploydash` — Deployment dashboard
- `dentalemon` — DentaLemon dental app
- `dentalemon-myaccount` — DentaLemon account portal
- `dentalemon-website` — DentaLemon marketing site
- `syncd` — SyncD real-time synchronization (WebSocket/Bun/MongoDB)

### Core Services (2)
- `api` — Monobase API (Hono/Bun backend)
- `account` — Monobase Account App (React/Vite frontend)

### Infrastructure (9)
- `namespace` — Namespace creation with security and resource quotas
- `gateway` — Shared Gateway for multi-tenant routing
- `envoy-proxy-config` — Cloud-specific LoadBalancer settings
- `cert-manager-issuers` — Multi-provider ClusterIssuer management
- `database-secrets` — External Secrets for database credentials
- `external-dns` — Automatic DNS record management
- `grafana` — Grafana with Gateway API integration
- `security-baseline` — NetworkPolicies and RBAC
- `mailpit` — Email testing tool (dev/staging)

## Standard Chart Structure

```
charts/{name}/
  Chart.yaml          # Chart metadata
  values.yaml         # Default values
  templates/
    _helpers.tpl      # Template helpers
    deployment.yaml   # Deployment spec
    service.yaml      # Service spec
    httproute.yaml    # Gateway API HTTPRoute
    externalsecret.yaml  # External Secrets (if applicable)
    hpa.yaml          # HorizontalPodAutoscaler (if applicable)
    pdb.yaml          # PodDisruptionBudget (if applicable)
    networkpolicy.yaml   # NetworkPolicy (if applicable)
    servicemonitor.yaml  # Prometheus ServiceMonitor (if applicable)
```

## Global Values Pattern

All charts inherit global values from deployment files (`values/deployments/*.yaml`):

```yaml
global:
  domain: localfirsthealth.com        # Base domain
  namespace: mycure-production         # Target namespace
  environment: production              # Environment name
  nodePool: "production"               # Node affinity pool
  gateway:
    name: shared-gateway               # Gateway resource name
    namespace: gateway-system           # Gateway namespace
  storage:
    provider: ""                       # Storage provider (longhorn, ebs-csi, etc.)
    className: ""                      # StorageClass name
```

## Key Template Patterns

### HTTPRoute (Gateway API)
Routes use `parentRefs` pointing to shared gateway with optional `sectionName` for multi-domain:
```yaml
parentRefs:
  - name: {{ include "{chart}.gateway.name" . }}
    namespace: {{ include "{chart}.gateway.namespace" . }}
    sectionName: https-lfh  # Listener for *.localfirsthealth.com
```

### ExternalSecret
```yaml
spec:
  secretStoreRef:
    name: {{ .Values.externalSecrets.secretStore }}
    kind: {{ .Values.externalSecrets.secretStoreKind }}
  refreshInterval: {{ .Values.externalSecrets.refreshInterval }}
  data:
    {{- range .Values.externalSecrets.secrets }}
    - secretKey: {{ .secretKey }}
      remoteRef:
        key: {{ .remoteKey }}
    {{- end }}
```

### Conditional `.enabled` Flags
Every major component uses `.enabled` flags for toggling:
```yaml
{{- if .Values.autoscaling.enabled }}
{{- if .Values.externalSecrets.enabled }}
{{- if .Values.podDisruptionBudget.enabled }}
```

### Node Pool Scheduling
```yaml
{{- $nodePool := include "{chart}.nodePool" . }}
{{- if $nodePool }}
nodeSelector:
  node-pool: {{ $nodePool }}
tolerations:
  - key: "node-pool"
    operator: "Equal"
    value: {{ $nodePool | quote }}
    effect: "NoSchedule"
{{- end }}
```

## Creating a New Chart

1. Copy closest existing chart as template:
   ```bash
   cp -r charts/mycure charts/{new-chart}
   ```
2. Update `Chart.yaml` (name, description, appVersion)
3. Update `values.yaml` (image, resources, gateway hostname)
4. Update `_helpers.tpl` (replace all `mycure.` prefixes with `{new-chart}.`)
5. Update template files (labels, selectors)
6. Test: `helm template test charts/{new-chart} --dry-run`
7. Lint: `helm lint charts/{new-chart}`
8. Add to deployment values file in `values/deployments/`

## Debugging Commands

```bash
# Template rendering (see what Kubernetes manifests would be generated)
helm template test charts/{name} -f values/deployments/{deployment}.yaml --debug

# Lint chart
helm lint charts/{name}

# Validate (dry-run against cluster)
helm template test charts/{name} --dry-run > /dev/null

# Run Helm unit tests (if helm-unittest plugin installed)
helm unittest charts/{name}
```

## Reference Implementation

The `hapihub` chart is the most complete reference — it includes all patterns:
HTTPRoute with sectionName, ExternalSecret, HPA, PDB, MongoDB helpers,
Valkey/MinIO URL helpers, node pool affinity, and security context.
See `charts/hapihub/templates/_helpers.tpl` for all template helpers.
