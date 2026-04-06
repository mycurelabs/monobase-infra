{{/*
Expand the name of the chart.
*/}}
{{- define "hapihub-migrator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "hapihub-migrator.fullname" -}}
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
Chart name and version label.
*/}}
{{- define "hapihub-migrator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hapihub-migrator.labels" -}}
helm.sh/chart: {{ include "hapihub-migrator.chart" . }}
{{ include "hapihub-migrator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hapihub-migrator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hapihub-migrator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "hapihub-migrator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hapihub-migrator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "hapihub-migrator.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
PostgreSQL host (in-cluster service FQDN)
*/}}
{{- define "hapihub-migrator.postgresql.host" -}}
{{- $serviceName := .Values.postgresql.serviceName | default "postgresql-primary" -}}
{{- $namespace := include "hapihub-migrator.namespace" . -}}
{{- printf "%s.%s.svc.cluster.local" $serviceName $namespace -}}
{{- end }}

{{/*
MongoDB host (in-cluster service FQDN)
*/}}
{{- define "hapihub-migrator.mongodb.host" -}}
{{- $serviceName := .Values.mongodb.serviceName | default "mongodb" -}}
{{- $namespace := include "hapihub-migrator.namespace" . -}}
{{- printf "%s.%s.svc.cluster.local" $serviceName $namespace -}}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global).
Returns empty string if disabled or not configured.
*/}}
{{- define "hapihub-migrator.nodePool" -}}
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
