{{- define "cadence-issuer.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{- define "cadence-issuer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "cadence-issuer.selectorLabels" -}}
app.kubernetes.io/name: cadence-issuer
{{- end }}

{{- define "cadence-issuer.labels" -}}
helm.sh/chart: {{ include "cadence-issuer.chart" . }}
{{ include "cadence-issuer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{- define "cadence-issuer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}{{ default "cadence-issuer" .Values.serviceAccount.name }}{{ else }}{{ default "default" .Values.serviceAccount.name }}{{ end }}
{{- end }}

{{- define "cadence-issuer.postgresql.host" -}}
{{- printf "%s.%s.svc.cluster.local" (.Values.postgresql.serviceName | default "postgresql") (include "cadence-issuer.namespace" .) -}}
{{- end }}

{{- define "cadence-issuer.gateway.name" -}}
{{- default "shared-gateway" .Values.global.gateway.name }}
{{- end }}
{{- define "cadence-issuer.gateway.namespace" -}}
{{- default "gateway-system" .Values.global.gateway.namespace }}
{{- end }}
{{- define "cadence-issuer.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}{{ .Values.gateway.hostname }}{{ else }}{{ printf "cadence-issuer.%s" .Values.global.domain }}{{ end }}
{{- end }}
