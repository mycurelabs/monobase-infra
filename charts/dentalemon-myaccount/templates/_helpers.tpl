{{/*
Expand the name of the chart.
*/}}
{{- define "dentalemon-myaccount.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "dentalemon-myaccount.fullname" -}}
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
{{- define "dentalemon-myaccount.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dentalemon-myaccount.labels" -}}
helm.sh/chart: {{ include "dentalemon-myaccount.chart" . }}
{{ include "dentalemon-myaccount.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: dentalemon-myaccount
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dentalemon-myaccount.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dentalemon-myaccount.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "dentalemon-myaccount.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "dentalemon-myaccount.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway hostname - defaults to dentalemon-myaccount.{global.domain}
*/}}
{{- define "dentalemon-myaccount.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "dentalemon-myaccount.%s" .Values.global.domain }}
{{- end }}
{{- end }}

{{/*
Namespace - uses global.namespace or Release.Namespace
*/}}
{{- define "dentalemon-myaccount.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Gateway parent reference name
*/}}
{{- define "dentalemon-myaccount.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}

{{/*
Gateway parent reference namespace
*/}}
{{- define "dentalemon-myaccount.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}

{{/*
Node Pool - returns the effective node pool name (component-level or global)
Returns empty string if disabled or not configured
*/}}
{{- define "dentalemon-myaccount.nodePool" -}}
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
