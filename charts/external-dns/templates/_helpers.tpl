{{/*
Expand the name of the chart.
*/}}
{{- define "external-dns.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "external-dns.fullname" -}}
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
{{- define "external-dns.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "external-dns.labels" -}}
helm.sh/chart: {{ include "external-dns.chart" . }}
{{ include "external-dns.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels for a specific instance
*/}}
{{- define "external-dns.selectorLabels" -}}
app.kubernetes.io/name: {{ include "external-dns.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for a specific instance
Usage: {{ include "external-dns.instanceSelectorLabels" (dict "instance" .instance "root" $) }}
*/}}
{{- define "external-dns.instanceSelectorLabels" -}}
{{- $instance := .instance -}}
{{- $root := .root -}}
app.kubernetes.io/name: {{ include "external-dns.name" $root }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/component: {{ $instance.name }}
{{- end }}

{{/*
Create the name of the service account for an instance
Usage: {{ include "external-dns.serviceAccountName" (dict "instance" .instance "root" $) }}
*/}}
{{- define "external-dns.serviceAccountName" -}}
{{- $instance := .instance -}}
{{- $root := .root -}}
{{- if $instance.serviceAccount }}
{{- if $instance.serviceAccount.create }}
{{- default (printf "external-dns-%s" $instance.name) $instance.serviceAccount.name }}
{{- else }}
{{- default "default" $instance.serviceAccount.name }}
{{- end }}
{{- else }}
{{- printf "external-dns-%s" $instance.name }}
{{- end }}
{{- end }}

{{/*
Resource name for an instance
Usage: {{ include "external-dns.instanceResourceName" (dict "instance" .instance "root" $) }}
*/}}
{{- define "external-dns.instanceResourceName" -}}
{{- $instance := .instance -}}
{{- printf "external-dns-%s" $instance.name }}
{{- end }}
