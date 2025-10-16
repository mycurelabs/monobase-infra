{{/*
Expand the name of the chart.
*/}}
{{- define "api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "api.fullname" -}}
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
{{- define "api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "api.labels" -}}
helm.sh/chart: {{ include "api.chart" . }}
{{ include "api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels
*/}}
{{- define "api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to api.{global.domain}
*/}}
{{- define "api.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "api.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "api.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
*/}}
{{- define "api.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/*
Gateway parent reference namespace
*/}}
{{- define "api.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}

{{/*
StorageClass name - auto-detects based on provider
*/}}
{{- define "api.storageClass" -}}
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
PostgreSQL connection string - constructs DATABASE_URL from PostgreSQL dependency
Supports both standalone and replication architectures
Note: Always generates connection string; PostgreSQL may be deployed separately in GitOps
*/}}
{{- define "api.postgresql.connectionString" -}}
{{- $serviceName := .Values.postgresql.serviceName | default (printf "%s-postgresql" .Release.Name) -}}
{{- $namespace := include "api.namespace" . -}}
{{- $database := .Values.postgresql.auth.database | default "monobase" -}}
{{- $username := .Values.postgresql.auth.username | default "monobase" -}}
{{- $architecture := .Values.postgresql.architecture | default "replication" -}}
{{- if eq $architecture "replication" -}}
{{- /* Use primary for writes */ -}}
postgresql://{{ $username }}:${POSTGRESQL_PASSWORD}@{{ $serviceName }}-primary.{{ $namespace }}.svc.cluster.local:5432/{{ $database }}
{{- else -}}
{{- /* Standalone mode */ -}}
postgresql://{{ $username }}:${POSTGRESQL_PASSWORD}@{{ $serviceName }}.{{ $namespace }}.svc.cluster.local:5432/{{ $database }}
{{- end -}}
{{- end }}

{{/*
Valkey (Redis) URL - constructs connection URL from Valkey dependency
*/}}
{{- define "api.valkey.url" -}}
{{- if .Values.valkey.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "api.namespace" . -}}
redis://{{ $release }}-valkey-master.{{ $namespace }}.svc.cluster.local:6379
{{- end -}}
{{- end }}

{{/*
MinIO URL - constructs connection URL from MinIO dependency
*/}}
{{- define "api.minio.url" -}}
{{- if .Values.minio.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "api.namespace" . -}}
http://{{ $release }}-minio.{{ $namespace }}.svc.cluster.local:9000
{{- end -}}
{{- end }}

{{/*
Mailpit SMTP URL - constructs connection URL from Mailpit dependency
*/}}
{{- define "api.mailpit.url" -}}
{{- if .Values.mailpit.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "api.namespace" . -}}
smtp://{{ $release }}-mailpit.{{ $namespace }}.svc.cluster.local:1025
{{- end -}}
{{- end }}
