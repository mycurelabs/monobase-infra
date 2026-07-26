{{/* Chart name */}}
{{- define "cade.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name */}}
{{- define "cade.fullname" -}}
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

{{/* Chart label */}}
{{- define "cade.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "cade.labels" -}}
helm.sh/chart: {{ include "cade.chart" . }}
{{ include "cade.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/* Selector labels — app label is stable "cade" (the udp-gateway targets it). */}}
{{- define "cade.selectorLabels" -}}
app.kubernetes.io/name: cade
{{- end }}

{{/* Namespace */}}
{{- define "cade.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/* Service account name */}}
{{- define "cade.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default "cade" .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Gateway parent ref */}}
{{- define "cade.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}
{{- define "cade.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}
{{- define "cade.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}{{ .Values.gateway.hostname }}{{ else }}{{ printf "cade.%s" .Values.global.domain }}{{ end }}
{{- end }}

{{/* PostgreSQL coordinates for the isolated cadence_v2 database */}}
{{- define "cade.postgresql.host" -}}
{{- printf "%s.%s.svc.cluster.local" (.Values.postgresql.serviceName | default "postgresql") (include "cade.namespace" .) -}}
{{- end }}
{{- define "cade.postgresql.database" -}}
{{- .Values.postgresql.auth.database | default "cadence_v2" -}}
{{- end }}
{{- define "cade.postgresql.username" -}}
{{- .Values.postgresql.auth.username | default "postgres" -}}
{{- end }}
