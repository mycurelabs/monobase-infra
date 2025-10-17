{{/*
Expand the name of the chart.
*/}}
{{- define "gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "gateway.fullname" -}}
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
{{- define "gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gateway.labels" -}}
helm.sh/chart: {{ include "gateway.chart" . }}
{{ include "gateway.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: gateway
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Gateway name
*/}}
{{- define "gateway.gatewayName" -}}
{{- .Values.gateway.name | default "shared-gateway" }}
{{- end }}

{{/*
Gateway namespace
*/}}
{{- define "gateway.namespace" -}}
{{- .Values.gateway.namespace | default "gateway-system" }}
{{- end }}

{{/*
Wildcard domain for listeners and certificates
*/}}
{{- define "gateway.wildcardDomain" -}}
{{- printf "*.%s" .Values.domain }}
{{- end }}

{{/*
TLS secret name
*/}}
{{- define "gateway.tlsSecretName" -}}
{{- .Values.tls.secretName | default "wildcard-tls" }}
{{- end }}

{{/*
Cert-manager ClusterIssuer
*/}}
{{- define "gateway.clusterIssuer" -}}
{{- .Values.tls.certManager.clusterIssuer | default "letsencrypt-prod" }}
{{- end }}
