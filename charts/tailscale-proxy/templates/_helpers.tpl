{{/*
Expand the name of the chart.
*/}}
{{- define "tailscale-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. The argocd-applications factory releases this chart
as "tailscale-proxy", which contains the chart name, so fullname == release.
*/}}
{{- define "tailscale-proxy.fullname" -}}
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

{{- define "tailscale-proxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tailscale-proxy.labels" -}}
helm.sh/chart: {{ include "tailscale-proxy.chart" . }}
{{ include "tailscale-proxy.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.global.partOf | default "mycureapp" }}
{{- end }}

{{- define "tailscale-proxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tailscale-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "tailscale-proxy.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/* Kubernetes Secret holding tailscaled state (TS_KUBE_SECRET). */}}
{{- define "tailscale-proxy.stateSecret" -}}
{{- include "tailscale-proxy.fullname" . }}-state
{{- end }}

{{/* Kubernetes Secret (ESO target) holding the auth key. */}}
{{- define "tailscale-proxy.authSecret" -}}
{{- include "tailscale-proxy.fullname" . }}-auth
{{- end }}

{{- define "tailscale-proxy.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
