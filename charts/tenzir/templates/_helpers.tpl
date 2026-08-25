{{/* Namespace — the ArgoCD app pins this via global.namespace (security). */}}
{{- define "tenzir.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{- define "tenzir.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "tenzir.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{- define "tenzir.selectorLabels" -}}
app.kubernetes.io/name: tenzir
{{- end }}

{{- define "tenzir.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}{{ default "tenzir" .Values.serviceAccount.name }}{{- else }}{{ default "default" .Values.serviceAccount.name }}{{- end }}
{{- end }}
