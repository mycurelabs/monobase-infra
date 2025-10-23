{{/*
Expand the name of the chart.
*/}}
{{- define "cert-manager-issuers.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cert-manager-issuers.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cert-manager-issuers.labels" -}}
helm.sh/chart: {{ include "cert-manager-issuers.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Get ACME server URL based on server type
*/}}
{{- define "cert-manager-issuers.acmeServer" -}}
{{- if eq . "production" -}}
https://acme-v02.api.letsencrypt.org/directory
{{- else if eq . "staging" -}}
https://acme-staging-v02.api.letsencrypt.org/directory
{{- else -}}
{{ . }}
{{- end -}}
{{- end -}}
