{{/*
Expand the name of the chart.
*/}}
{{- define "dentalemon-seeder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "dentalemon-seeder.fullname" -}}
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
{{- define "dentalemon-seeder.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dentalemon-seeder.labels" -}}
helm.sh/chart: {{ include "dentalemon-seeder.chart" . }}
{{ include "dentalemon-seeder.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dentalemon-seeder.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dentalemon-seeder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: seeder
{{- end }}

{{/*
Secret name for MongoDB URI
*/}}
{{- define "dentalemon-seeder.secretName" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecret }}
{{- else }}
{{- include "dentalemon-seeder.fullname" . }}-secrets
{{- end }}
{{- end }}
