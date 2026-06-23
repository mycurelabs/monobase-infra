{{/*
Expand the name of the chart.
*/}}
{{- define "openmed.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "openmed.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openmed.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openmed.labels" -}}
helm.sh/chart: {{ include "openmed.chart" . }}
{{ include "openmed.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels
*/}}
{{- define "openmed.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openmed.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "openmed.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "openmed.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to openmed.{global.domain}
*/}}
{{- define "openmed.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "openmed.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "openmed.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
*/}}
{{- define "openmed.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/*
Gateway parent reference namespace
*/}}
{{- define "openmed.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}

{{/*
StorageClass name - auto-detects based on provider
*/}}
{{- define "openmed.storageClass" -}}
{{- if .Values.persistence.storageClassName -}}
{{- .Values.persistence.storageClassName }}
{{- else if .Values.global.storage.className -}}
{{- .Values.global.storage.className }}
{{- else if eq .Values.global.storage.provider "longhorn" -}}
longhorn
{{- else if eq .Values.global.storage.provider "ebs-csi" -}}
gp3
{{- else if eq .Values.global.storage.provider "azure-disk" -}}
managed-premium
{{- else if eq .Values.global.storage.provider "gcp-pd" -}}
pd-ssd
{{- else if eq .Values.global.storage.provider "local-path" -}}
local-path
{{- else -}}
longhorn
{{- end -}}
{{- end }}

{{/*
PVC name for model cache
*/}}
{{- define "openmed.pvcName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim }}
{{- else -}}
openmed-model-cache
{{- end -}}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global)
Returns empty string if disabled or not configured
*/}}
{{- define "openmed.nodePool" -}}
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
