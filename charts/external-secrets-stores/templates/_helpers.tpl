{{/*
Expand the name of the chart.
*/}}
{{- define "external-secrets-stores.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "external-secrets-stores.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "external-secrets-stores.labels" -}}
helm.sh/chart: {{ include "external-secrets-stores.chart" . }}
{{ include "external-secrets-stores.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "external-secrets-stores.selectorLabels" -}}
app.kubernetes.io/name: {{ include "external-secrets-stores.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
