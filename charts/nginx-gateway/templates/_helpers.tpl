{{/*
Expand the name of the chart.
*/}}
{{- define "nginx-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "nginx-gateway.fullname" -}}
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
Common labels
*/}}
{{- define "nginx-gateway.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Gateway namespace — uses gateway.namespace or Release.Namespace
*/}}
{{- define "nginx-gateway.namespace" -}}
{{- default .Release.Namespace .Values.gateway.namespace }}
{{- end }}

{{/*
Every Gateway this chart renders: the main `gateway` (only when it has
listeners) followed by each `extraGateways` entry. Single source for
gateway.yaml and nginxproxy.yaml so the two can't drift. Returns YAML;
consume with: include "nginx-gateway.allGateways" . | fromYamlArray
*/}}
{{- define "nginx-gateway.allGateways" -}}
{{- $gateways := list }}
{{- if .Values.gateway.listeners }}
{{- $gateways = append $gateways .Values.gateway }}
{{- end }}
{{- range .Values.extraGateways }}
{{- $gateways = append $gateways . }}
{{- end }}
{{- toYaml $gateways }}
{{- end }}
