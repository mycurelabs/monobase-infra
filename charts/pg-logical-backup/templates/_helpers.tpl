{{/*
Expand the name of the chart.
*/}}
{{- define "pgLogicalBackup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "pgLogicalBackup.fullname" -}}
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
Namespace — the deployment's namespace (global.namespace), falling back to the
release namespace.
*/}}
{{- define "pgLogicalBackup.namespace" -}}
{{- (.Values.global | default dict).namespace | default .Release.Namespace }}
{{- end }}

{{- define "pgLogicalBackup.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pgLogicalBackup.labels" -}}
helm.sh/chart: {{ include "pgLogicalBackup.chart" . }}
{{ include "pgLogicalBackup.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pgLogicalBackup.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pgLogicalBackup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "pgLogicalBackup.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pgLogicalBackup.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret store name for ESO (default: the cluster-wide gcp-secretstore this
cluster actually provides — every chart here uses ClusterSecretStore/gcp-secretstore).
*/}}
{{- define "pgLogicalBackup.secretStore" -}}
{{- .Values.externalSecrets.secretStore | default "gcp-secretstore" }}
{{- end }}
