{{/*
Expand the name of the chart.
*/}}
{{- define "hapihub.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "hapihub.fullname" -}}
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
{{- define "hapihub.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hapihub.labels" -}}
helm.sh/chart: {{ include "hapihub.chart" . }}
{{ include "hapihub.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: hapihub
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hapihub.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hapihub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "hapihub.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hapihub.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to api.{global.domain}
*/}}
{{- define "hapihub.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "api.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "hapihub.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
*/}}
{{- define "hapihub.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/*
Gateway parent reference namespace
*/}}
{{- define "hapihub.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}

{{/*
StorageClass name - auto-detects based on provider
*/}}
{{- define "hapihub.storageClass" -}}
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
MongoDB connection string - constructs DATABASE_URL from MongoDB dependency
Supports both standalone and replicaset architectures
*/}}
{{- define "hapihub.mongodb.connectionString" -}}
{{- if .Values.mongodb.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "hapihub.namespace" . -}}
{{- $database := .Values.mongodb.auth.database | default "hapihub" -}}
{{- $replicaSet := .Values.mongodb.replicaSetName | default "rs0" -}}
{{- if eq .Values.mongodb.architecture "replicaset" -}}
{{- $hosts := list -}}
{{- range $i := until (int .Values.mongodb.replicaCount) -}}
{{- $hosts = append $hosts (printf "%s-mongodb-%d.%s-mongodb-headless.%s.svc.cluster.local:27017" $release $i $release $namespace) -}}
{{- end -}}
mongodb://root:${MONGODB_ROOT_PASSWORD}@{{ join "," $hosts }}/{{ $database }}?replicaSet={{ $replicaSet }}
{{- else -}}
mongodb://root:${MONGODB_ROOT_PASSWORD}@{{ $release }}-mongodb.{{ $namespace }}.svc.cluster.local:27017/{{ $database }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Typesense URL - constructs connection URL from Typesense dependency
*/}}
{{- define "hapihub.typesense.url" -}}
{{- if .Values.typesense.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "hapihub.namespace" . -}}
http://{{ $release }}-typesense.{{ $namespace }}.svc.cluster.local:8108
{{- end -}}
{{- end }}

{{/*
MinIO URL - constructs connection URL from MinIO dependency
*/}}
{{- define "hapihub.minio.url" -}}
{{- if .Values.minio.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "hapihub.namespace" . -}}
http://{{ $release }}-minio.{{ $namespace }}.svc.cluster.local:9000
{{- end -}}
{{- end }}

{{/*
Mailpit SMTP URL - constructs connection URL from Mailpit dependency
*/}}
{{- define "hapihub.mailpit.url" -}}
{{- if .Values.mailpit.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "hapihub.namespace" . -}}
smtp://{{ $release }}-mailpit.{{ $namespace }}.svc.cluster.local:1025
{{- end -}}
{{- end }}
