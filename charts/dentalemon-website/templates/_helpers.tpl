{{/*
Expand the name of the chart.
*/}}
{{- define "dentalemon-website.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "dentalemon-website.fullname" -}}
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
{{- define "dentalemon-website.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dentalemon-website.labels" -}}
helm.sh/chart: {{ include "dentalemon-website.chart" . }}
{{ include "dentalemon-website.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: dentalemon-website
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dentalemon-website.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dentalemon-website.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "dentalemon-website.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "dentalemon-website.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to dentalemon-website.{global.domain}
*/}}
{{- define "dentalemon-website.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "dentalemon-website.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "dentalemon-website.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
Checks .Values.gateway.gatewayName first (per-service override),
then falls back to .Values.global.gateway.name, then "shared-gateway"
*/}}
{{- define "dentalemon-website.gateway.name" -}}
{{- .Values.gateway.gatewayName | default .Values.global.gateway.name | default "shared-gateway" }}
{{- end }}

{{/*
Gateway parent reference namespace
Checks .Values.gateway.gatewayNamespace first (per-service override),
then falls back to .Values.global.gateway.namespace, then "gateway-system"
*/}}
{{- define "dentalemon-website.gateway.namespace" -}}
{{- .Values.gateway.gatewayNamespace | default .Values.global.gateway.namespace | default "gateway-system" }}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global)
Returns empty string if disabled or not configured
*/}}
{{- define "dentalemon-website.nodePool" -}}
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
