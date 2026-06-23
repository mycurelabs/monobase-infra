{{/*
Expand the name of the chart.
*/}}
{{- define "medgemma-worker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "medgemma-worker.fullname" -}}
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
{{- define "medgemma-worker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "medgemma-worker.labels" -}}
helm.sh/chart: {{ include "medgemma-worker.chart" . }}
{{ include "medgemma-worker.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels
*/}}
{{- define "medgemma-worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "medgemma-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "medgemma-worker.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "medgemma-worker.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to medgemma-worker.{global.domain}
*/}}
{{- define "medgemma-worker.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "medgemma-worker.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "medgemma-worker.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
*/}}
{{- define "medgemma-worker.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/*
Gateway parent reference namespace
*/}}
{{- define "medgemma-worker.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}

{{/*
StorageClass name - auto-detects based on provider
*/}}
{{- define "medgemma-worker.storageClass" -}}
{{- if .Values.global.storage.className -}}
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
{{- end -}}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global)
Returns empty string if disabled or not configured
*/}}
{{- define "medgemma-worker.nodePool" -}}
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
