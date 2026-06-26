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
app.kubernetes.io/part-of: monobase
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
{{- printf "hapihub.%s" .Values.global.domain }}
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
MongoDB host - constructs hostname from MongoDB dependency
Supports both standalone and replicaset architectures
*/}}
{{- define "hapihub.mongodb.host" -}}
{{- $serviceName := .Values.mongodb.serviceName | default "mongodb" -}}
{{- $namespace := include "hapihub.namespace" . -}}
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
{{- define "hapihub.mongodb.database" -}}
{{- .Values.mongodb.database | default "hapihub" -}}
{{- end }}

{{/*
MongoDB username
*/}}
{{- define "hapihub.mongodb.username" -}}
{{- .Values.mongodb.username | default "root" -}}
{{- end }}

{{/*
MongoDB connection URL template (app must substitute password from MONGODB_PASSWORD env var)
*/}}
{{- define "hapihub.mongodb.connectionUrl" -}}
{{- $host := include "hapihub.mongodb.host" . -}}
{{- $database := include "hapihub.mongodb.database" . -}}
{{- $username := include "hapihub.mongodb.username" . -}}
{{- $replicaSet := .Values.mongodb.replicaSet | default "rs0" -}}
mongodb://{{ $username }}@{{ $host }}:27017/{{ $database }}?replicaSet={{ $replicaSet }}
{{- end }}

{{/*
PostgreSQL host - constructs hostname from PostgreSQL dependency
Supports both standalone and replication architectures
*/}}
{{- define "hapihub.postgresql.host" -}}
{{- $serviceName := .Values.postgresql.serviceName | default "postgresql" -}}
{{- $namespace := include "hapihub.namespace" . -}}
{{- printf "%s.%s.svc.cluster.local" $serviceName $namespace -}}
{{- end }}

{{/*
PostgreSQL database name
*/}}
{{- define "hapihub.postgresql.database" -}}
{{- .Values.postgresql.auth.database | default "hapihub" -}}
{{- end }}

{{/*
PostgreSQL username
*/}}
{{- define "hapihub.postgresql.username" -}}
{{- .Values.postgresql.auth.username | default "postgres" -}}
{{- end }}

{{/*
Valkey (Redis) URL - constructs connection URL from Valkey dependency
*/}}
{{- define "hapihub.valkey.url" -}}
{{- if .Values.valkey.enabled -}}
{{- $release := .Release.Name -}}
{{- $namespace := include "hapihub.namespace" . -}}
redis://{{ $release }}-valkey-master.{{ $namespace }}.svc.cluster.local:6379
{{- end -}}
{{- end }}

{{/*
MinIO URL - constructs connection URL from MinIO dependency
*/}}
{{- define "hapihub.minio.url" -}}
{{- if .Values.minio.enabled -}}
{{- $namespace := include "hapihub.namespace" . -}}
http://minio.{{ $namespace }}.svc.cluster.local:9000
{{- end -}}
{{- end }}

{{/*
Mailpit SMTP Host - constructs hostname for Mailpit SMTP service
Note: Mailpit is deployed as a standalone chart with instance name "mailpit"
*/}}
{{- define "hapihub.mailpit.host" -}}
{{- if .Values.mailpit.enabled -}}
{{- $namespace := include "hapihub.namespace" . -}}
mailpit-smtp.{{ $namespace }}.svc.cluster.local
{{- end -}}
{{- end }}

{{/*
External URL - constructs public HTTPS URL for HapiHub
Used for OAuth callbacks, webhooks, email links, etc.
*/}}
{{- define "hapihub.externalUrl" -}}
https://{{ include "hapihub.gateway.hostname" . }}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global)
Returns empty string if disabled or not configured
*/}}
{{- define "hapihub.nodePool" -}}
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

{{/*
Container env for hapihub — shared by the Deployment and the prune-expired-sessions CronJob
so a scheduled `hapihub backfill` boots with the identical environment.
*/}}
{{- define "hapihub.containerEnv" -}}
# Set HOME to /tmp to avoid permission denied errors when running as non-root
- name: HOME
  value: "/tmp"
# Load from ConfigMap (conditionally)
{{- if .Values.config.NODE_ENV }}
- name: NODE_ENV
  valueFrom:
    configMapKeyRef:
      name: {{ include "hapihub.fullname" . }}
      key: NODE_ENV
{{- end }}
{{- if .Values.config.LOG_LEVEL }}
- name: LOG_LEVEL
  valueFrom:
    configMapKeyRef:
      name: {{ include "hapihub.fullname" . }}
      key: LOG_LEVEL
{{- end }}
# Port configuration - must be numeric (unquoted) for proper parsing
- name: HAPIHUB_PORT
  value: {{ .Values.service.targetPort | quote }}
- name: PORT
  value: {{ .Values.service.targetPort | quote }}
# MongoDB connection
{{- if .Values.mongodb.external }}
# External/managed MongoDB - MONGO_URI from ExternalSecrets
- name: MONGO_URI
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: MONGO_URI
{{- else if .Values.mongodb.enabled }}
# In-cluster MongoDB - individual components
- name: MONGODB_HOST
  value: {{ include "hapihub.mongodb.host" . | quote }}
- name: MONGODB_PORT
  value: "27017"
- name: MONGODB_DATABASE
  value: {{ include "hapihub.mongodb.database" . | quote }}
- name: MONGODB_USER
  value: {{ include "hapihub.mongodb.username" . | quote }}
- name: MONGODB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: mongodb
      key: mongodb-root-password
# MONGO_URI constructed from components using K8s variable expansion
- name: MONGO_URI
  value: "mongodb://$(MONGODB_USER):$(MONGODB_PASSWORD)@$(MONGODB_HOST):$(MONGODB_PORT)/$(MONGODB_DATABASE)?replicaSet={{ .Values.mongodb.replicaSet }}&directConnection=true&authSource=admin"
{{- end }}
# PostgreSQL connection (v11+)
{{- if .Values.postgresql.enabled }}
{{- if .Values.postgresql.external }}
# External PostgreSQL — DATABASE_URI from ExternalSecrets
{{- else }}
- name: POSTGRESQL_USER
  value: {{ include "hapihub.postgresql.username" . | quote }}
- name: POSTGRESQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.auth.existingSecret | default "postgresql" }}
      key: postgres-password
- name: DATABASE_URI
  value: "postgres://$(POSTGRESQL_USER):$(POSTGRESQL_PASSWORD)@{{ include "hapihub.postgresql.host" . }}:5432/{{ include "hapihub.postgresql.database" . }}"
{{- end }}
- name: DATABASE_WAIT_FOR_READY
  value: "true"
- name: DATABASE_STARTUP_RETRIES
  value: "10"
- name: DATABASE_STARTUP_RETRY_DELAY_MS
  value: "5000"
{{- end }}
# External URL - public HTTPS endpoint for callbacks, webhooks, etc.
- name: EXTERNAL_ADDRESS
  value: {{ include "hapihub.externalUrl" . | quote }}
# Better Auth - Passkey/WebAuthn configuration
- name: BETTER_AUTH_PASSKEY_RP_NAME
  value: {{ .Values.betterAuth.passkey.rpName | default "Acme" | quote }}
- name: BETTER_AUTH_PASSKEY_RP_ID
  value: {{ .Values.betterAuth.passkey.rpId | default .Values.global.domain | quote }}
# Service URLs from dependencies
{{- if .Values.valkey.enabled }}
- name: REDIS_URL
  value: {{ include "hapihub.valkey.url" . | quote }}
{{- end }}
{{- if .Values.minio.enabled }}
- name: STORAGE_PROVIDER
  value: "minio"
- name: STORAGE_ENDPOINT
  value: {{ include "hapihub.minio.url" . | quote }}
- name: STORAGE_PUBLIC_ENDPOINT
  value: {{ include "hapihub.minio.url" . | quote }}
- name: STORAGE_BUCKET
  value: {{ .Values.minio.defaultBuckets | default "hapihub-files" | quote }}
- name: STORAGE_REGION
  value: {{ .Values.minio.region | default "us-east-1" | quote }}
- name: STORAGE_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: minio
      key: root-user
- name: STORAGE_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: minio
      key: root-password
- name: STORAGE_UPLOAD_URL_EXPIRY
  value: "300"
- name: STORAGE_DOWNLOAD_URL_EXPIRY
  value: "900"
# v11 storage naming
- name: STORAGE_TYPE
  value: "s3"
- name: STORAGE_S3_ENDPOINT
  value: {{ include "hapihub.minio.url" . | quote }}
- name: STORAGE_S3_REGION
  value: "us-east-1"
- name: STORAGE_S3_FORCE_PATH_STYLE
  value: "true"
- name: STORAGE_S3_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: minio
      key: root-user
- name: STORAGE_S3_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: minio
      key: root-password
{{- end }}
{{- if .Values.mailpit.enabled }}
- name: SMTP_HOST
  value: {{ include "hapihub.mailpit.host" . | quote }}
- name: SMTP_PORT
  value: "25"
- name: SMTP_SECURE
  value: "false"
{{- end }}
# Load non-DB secrets from External Secrets Operator
{{- if .Values.externalSecrets.enabled }}
- name: JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: JWT_SECRET
      optional: true
- name: S3_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: S3_ACCESS_KEY_ID
      optional: true
- name: S3_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: S3_SECRET_ACCESS_KEY
      optional: true
- name: GOOGLE_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: GOOGLE_CLIENT_ID
      optional: true
- name: GOOGLE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: GOOGLE_CLIENT_SECRET
      optional: true
- name: STRIPE_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STRIPE_SECRET_KEY
      optional: true
# v11 auth secrets
- name: AUTH_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: AUTH_SECRET
      optional: true
- name: BETTER_AUTH_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: BETTER_AUTH_SECRET
      optional: true
# v11 database URI (from ExternalSecrets, for external PostgreSQL)
{{- if not (and .Values.postgresql.enabled (not .Values.postgresql.external)) }}
- name: DATABASE_URI
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: DATABASE_URI
      optional: true
{{- end }}
# Encryption keys
- name: ENC_BILLING_INVOICES
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: ENC_BILLING_INVOICES
      optional: true
- name: ENC_BILLING_ITEMS
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: ENC_BILLING_ITEMS
      optional: true
- name: ENC_BILLING_PAYMENTS
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: ENC_BILLING_PAYMENTS
      optional: true
- name: ENC_MEDICAL_RECORDS
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: ENC_MEDICAL_RECORDS
      optional: true
- name: ENC_PERSONAL_DETAILS
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: ENC_PERSONAL_DETAILS
      optional: true
# MongoDB URI (fallback) - only if neither external nor in-cluster MongoDB configured
{{- if and (not .Values.mongodb.external) (not .Values.mongodb.enabled) }}
- name: MONGO_URI
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: MONGO_URI
      optional: true
{{- end }}
# JWT/Auth keys
- name: PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: PRIVATE_KEY
      optional: true
- name: PUBLIC_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: PUBLIC_KEY
      optional: true
# Storage configuration - only if not using local MinIO
{{- if not .Values.minio.enabled }}
- name: STORAGE_BUCKET
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STORAGE_BUCKET
      optional: true
- name: STORAGE_CLIENT_EMAIL
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STORAGE_CLIENT_EMAIL
      optional: true
- name: STORAGE_DIRECTORY
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STORAGE_DIRECTORY
      optional: true
- name: STORAGE_PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STORAGE_PRIVATE_KEY
      optional: true
- name: STORAGE_PROJECT_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STORAGE_PROJECT_ID
      optional: true
- name: STORAGE_TYPE
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STORAGE_TYPE
      optional: true
{{- end }}
# Stripe configuration
- name: STRIPE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STRIPE_KEY
      optional: true
- name: STRIPE_CHECKOUT_SUCCESS_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STRIPE_CHECKOUT_SUCCESS_URL
      optional: true
- name: STRIPE_CHECKOUT_CANCEL_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "hapihub.fullname" . }}-secrets
      key: STRIPE_CHECKOUT_CANCEL_URL
      optional: true
{{- end }}
# Additional environment variables from config
{{- range $key, $value := .Values.config }}
{{- if not (has $key (list "NODE_ENV" "LOG_LEVEL" "PORT" "DATABASE_WAIT_FOR_READY" "DATABASE_STARTUP_RETRIES" "DATABASE_STARTUP_RETRY_DELAY_MS")) }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
# Custom environment variables
{{- with .Values.env }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}
