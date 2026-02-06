{{/*
Expand the name of the chart.
*/}}
{{- define "syncd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "syncd.fullname" -}}
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
{{- define "syncd.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "syncd.labels" -}}
helm.sh/chart: {{ include "syncd.chart" . }}
{{ include "syncd.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels
*/}}
{{- define "syncd.selectorLabels" -}}
app.kubernetes.io/name: {{ include "syncd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "syncd.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "syncd.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to sync.{global.domain}
*/}}
{{- define "syncd.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "sync.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "syncd.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
*/}}
{{- define "syncd.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/*
Gateway parent reference namespace
*/}}
{{- define "syncd.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}

{{/*
MongoDB host - constructs hostname from MongoDB dependency
Supports both standalone and replicaset architectures
CRITICAL: Uses mongodb-headless for Bitnami replicaset pattern
*/}}
{{- define "syncd.mongodb.host" -}}
{{- $serviceName := .Values.mongodb.serviceName | default "mongodb" -}}
{{- $namespace := include "syncd.namespace" . -}}
{{- $architecture := .Values.mongodb.architecture | default "replicaset" -}}
{{- if eq $architecture "replicaset" -}}
{{- printf "%s-headless.%s.svc.cluster.local" $serviceName $namespace -}}
{{- else -}}
{{- printf "%s.%s.svc.cluster.local" $serviceName $namespace -}}
{{- end -}}
{{- end }}

{{/*
MongoDB database name
*/}}
{{- define "syncd.mongodb.database" -}}
{{- .Values.mongodb.database | default "hapihub" -}}
{{- end }}

{{/*
MongoDB username
*/}}
{{- define "syncd.mongodb.username" -}}
{{- .Values.mongodb.username | default "root" -}}
{{- end }}

{{/*
Mailpit host - constructs hostname from Mailpit service
*/}}
{{- define "syncd.mailpit.host" -}}
{{- $serviceName := .Values.mailpit.serviceName | default "mailpit" -}}
{{- $namespace := include "syncd.namespace" . -}}
{{- printf "%s.%s.svc.cluster.local" $serviceName $namespace -}}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global)
Returns empty string if disabled or not configured
*/}}
{{- define "syncd.nodePool" -}}
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
