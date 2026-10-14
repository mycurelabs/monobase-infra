{{/* Chart name */}}
{{- define "cadence.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name */}}
{{- define "cadence.fullname" -}}
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
{{- define "cadence.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "cadence.labels" -}}
helm.sh/chart: {{ include "cadence.chart" . }}
{{ include "cadence.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels. The udp-gateway UDP LoadBalancer selects pods by `app.kubernetes.io/name: cadence`
(kept in lockstep in charts/udp-gateway/values.yaml).
*/}}
{{- define "cadence.selectorLabels" -}}
app.kubernetes.io/name: cadence
{{- end }}

{{/* Namespace */}}
{{- define "cadence.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/* Service account name */}}
{{- define "cadence.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default "cadence" .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Gateway parent ref */}}
{{- define "cadence.gateway.name" -}}
{{- required "global.gateway.name is required (set in the deployment values, e.g. values/deployments/_base)" .Values.global.gateway.name }}
{{- end }}
{{- define "cadence.gateway.namespace" -}}
{{- required "global.gateway.namespace is required (set in the deployment values)" .Values.global.gateway.namespace }}
{{- end }}
{{- define "cadence.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}{{ .Values.gateway.hostname }}{{ else }}{{ printf "cadence.%s" .Values.global.domain }}{{ end }}
{{- end }}

{{/* PostgreSQL coordinates for the isolated cadence_v2 database */}}
{{- define "cadence.postgresql.host" -}}
{{- printf "%s.%s.svc.cluster.local" (.Values.postgresql.serviceName | default "postgresql") (include "cadence.namespace" .) -}}
{{- end }}
{{- define "cadence.postgresql.database" -}}
{{- .Values.postgresql.auth.database | default "cadence_v2" -}}
{{- end }}
{{- define "cadence.postgresql.username" -}}
{{- .Values.postgresql.auth.username | default "postgres" -}}
{{- end }}

{{/*
retention_secs for files/cadence.yaml: values tuning.retentionSecs, else the 7d default. A short name
on purpose — files/cadence.yaml is yamllinted and that line must stay <= 120 chars.
*/}}
{{- define "cadence.ret" -}}
{{- with (.Values.tuning | default dict).retentionSecs -}}
{{- $s := int64 . -}}
{{ $s }}  # {{ div $s 86400 }}d via values tuning.retentionSecs; default
{{- else -}}
604800
{{- end -}}
{{- end -}}
