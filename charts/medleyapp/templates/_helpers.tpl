{{/*
Expand the name of the chart.
*/}}
{{- define "medleyapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "medleyapp.fullname" -}}
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
{{- define "medleyapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "medleyapp.labels" -}}
helm.sh/chart: {{ include "medleyapp.chart" . }}
{{ include "medleyapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: medleyapp
{{- end }}

{{/*
Selector labels
*/}}
{{- define "medleyapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "medleyapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "medleyapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "medleyapp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to medleyapp.{global.domain}
*/}}
{{- define "medleyapp.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "medleyapp.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "medleyapp.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
*/}}
{{- define "medleyapp.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/*
Gateway parent reference namespace
*/}}
{{- define "medleyapp.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global)
Returns empty string if disabled or not configured
*/}}
{{- define "medleyapp.nodePool" -}}
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
