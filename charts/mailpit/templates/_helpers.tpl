{{/*
Expand the name of the chart.
*/}}
{{- define "mailpit.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "mailpit.fullname" -}}
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
{{- define "mailpit.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mailpit.labels" -}}
helm.sh/chart: {{ include "mailpit.chart" . }}
{{ include "mailpit.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mailpit.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mailpit.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Resolve the namespace to use
*/}}
{{- define "mailpit.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
Resolve the gateway name to use
*/}}
{{- define "mailpit.gateway.name" -}}
{{- .Values.gateway.parentRefs | first | dig "name" .Values.global.gateway.name }}
{{- end }}

{{/*
Resolve the gateway namespace to use
*/}}
{{- define "mailpit.gateway.namespace" -}}
{{- .Values.gateway.parentRefs | first | dig "namespace" .Values.global.gateway.namespace }}
{{- end }}

{{/*
Resolve the hostname for HTTPRoute
Default: mail.{global.domain}
*/}}
{{- define "mailpit.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}
{{- .Values.gateway.hostname }}
{{- else }}
{{- printf "mail.%s" .Values.global.domain }}
{{- end }}
{{- end }}
