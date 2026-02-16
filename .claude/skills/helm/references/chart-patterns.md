# Chart Template Patterns

Reference: `charts/hapihub/templates/_helpers.tpl` (most complete implementation)

## _helpers.tpl Standard Helpers

Every chart should define these helpers (replace `hapihub` with chart name):

### Name & Labels
```yaml
{{- define "{chart}.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "{chart}.fullname" -}}
# Standard fullname logic with fullnameOverride support
{{- end }}

{{- define "{chart}.labels" -}}
helm.sh/chart: {{ include "{chart}.chart" . }}
{{ include "{chart}.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{- define "{chart}.selectorLabels" -}}
app.kubernetes.io/name: {{ include "{chart}.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

### Gateway Helpers
```yaml
{{/* Gateway hostname - defaults to {chart}.{global.domain} */}}
{{- define "{chart}.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "{chart}.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/* Namespace - uses global.namespace or Release.Namespace */}}
{{- define "{chart}.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/* Gateway parent reference name */}}
{{- define "{chart}.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/* Gateway parent reference namespace */}}
{{- define "{chart}.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}
```

### Storage Helper
```yaml
{{/* StorageClass - auto-detects based on provider */}}
{{- define "{chart}.storageClass" -}}
{{- if .Values.global.storage.className -}}
{{- .Values.global.storage.className }}
{{- else if eq .Values.global.storage.provider "longhorn" -}}longhorn
{{- else if eq .Values.global.storage.provider "ebs-csi" -}}gp3
{{- else if eq .Values.global.storage.provider "azure-disk" -}}managed-premium
{{- else if eq .Values.global.storage.provider "gcp-pd" -}}pd-ssd
{{- else if eq .Values.global.storage.provider "local-path" -}}local-path
{{- end -}}
{{- end }}
```

### Node Pool Helper
```yaml
{{/* Node Pool - returns effective pool name (component-level or global) */}}
{{- define "{chart}.nodePool" -}}
{{- if hasKey .Values "nodePool" -}}
  {{- if and .Values.nodePool (hasKey .Values.nodePool "enabled") (not .Values.nodePool.enabled) -}}
    {{- /* Component explicitly disabled node pool */ -}}
  {{- else if and .Values.nodePool .Values.nodePool.name -}}
    {{- .Values.nodePool.name -}}
  {{- else if and .Values.global .Values.global.nodePool -}}
    {{- .Values.global.nodePool -}}
  {{- end -}}
{{- else if and .Values.global .Values.global.nodePool -}}
  {{- .Values.global.nodePool -}}
{{- end -}}
{{- end -}}
```

## HTTPRoute Pattern

With `sectionName` for multi-domain support:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "{chart}.fullname" . }}
  namespace: {{ include "{chart}.namespace" . }}
  labels:
    {{- include "{chart}.labels" . | nindent 4 }}
spec:
  parentRefs:
    - name: {{ include "{chart}.gateway.name" . }}
      namespace: {{ include "{chart}.gateway.namespace" . }}
      {{- if .Values.gateway.sectionName }}
      sectionName: {{ .Values.gateway.sectionName }}
      {{- end }}
  hostnames:
    - {{ include "{chart}.gateway.hostname" . | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: {{ include "{chart}.fullname" . }}
          port: {{ .Values.service.port }}
      {{- if .Values.gateway.timeouts }}
      timeouts:
        request: {{ .Values.gateway.timeouts.request | default "30s" | quote }}
      {{- end }}
```

**sectionName values:**
- `https-lfh` — Production `*.localfirsthealth.com` listener
- `https-lfh-stg` — Staging `*.stg.localfirsthealth.com` listener
- (omit) — Default `*.mycureapp.com` listener

## ExternalSecret Pattern

```yaml
{{- if .Values.externalSecrets.enabled }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ include "{chart}.fullname" . }}-secrets
  namespace: {{ include "{chart}.namespace" . }}
spec:
  secretStoreRef:
    name: {{ .Values.externalSecrets.secretStore }}
    kind: {{ .Values.externalSecrets.secretStoreKind }}
  refreshInterval: {{ .Values.externalSecrets.refreshInterval | default "1h" }}
  target:
    name: {{ include "{chart}.fullname" . }}-secrets
  data:
    {{- range .Values.externalSecrets.secrets }}
    - secretKey: {{ .secretKey }}
      remoteRef:
        key: {{ .remoteKey }}
    {{- end }}
{{- end }}
```

## Pod Security Context Pattern

All production containers use restricted security context:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
```

## MongoDB Connection Helper

```yaml
{{/* MongoDB host - supports standalone and replicaset */}}
{{- define "{chart}.mongodb.host" -}}
{{- $serviceName := .Values.mongodb.serviceName | default "mongodb" -}}
{{- $namespace := include "{chart}.namespace" . -}}
{{- $architecture := .Values.mongodb.architecture | default "replicaset" -}}
{{- if eq $architecture "replicaset" -}}
{{- printf "%s-headless.%s.svc.cluster.local" $serviceName $namespace -}}
{{- else -}}
{{- printf "%s.%s.svc.cluster.local" $serviceName $namespace -}}
{{- end -}}
{{- end }}

{{/* Full connection URL (app substitutes password from env var) */}}
{{- define "{chart}.mongodb.connectionUrl" -}}
{{- $host := include "{chart}.mongodb.host" . -}}
{{- $database := .Values.mongodb.database | default "hapihub" -}}
{{- $username := .Values.mongodb.username | default "root" -}}
{{- $replicaSet := .Values.mongodb.replicaSet | default "rs0" -}}
mongodb://{{ $username }}@{{ $host }}:27017/{{ $database }}?replicaSet={{ $replicaSet }}
{{- end }}
```

## Multi-Hostname Support

For charts serving multiple hostnames (e.g., main + API subdomain):

```yaml
# Additional hostnames in HTTPRoute
hostnames:
  - {{ include "{chart}.gateway.hostname" . | quote }}
  {{- range .Values.gateway.additionalHostnames }}
  - {{ . | quote }}
  {{- end }}
```

## Conditional Component Pattern

```yaml
# HPA
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
...
  minReplicas: {{ .Values.autoscaling.minReplicas | default 1 }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas | default 5 }}
{{- end }}

# PDB
{{- if .Values.podDisruptionBudget.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
...
{{- end }}

# ServiceMonitor
{{- if .Values.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
...
{{- end }}
```
