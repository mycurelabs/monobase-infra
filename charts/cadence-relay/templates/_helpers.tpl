{{/* Public hostname: explicit override, else cadence-relay.{global.domain}. */}}
{{- define "cadence-relay.hostname" -}}
{{- if .Values.hostname -}}
{{- .Values.hostname -}}
{{- else -}}
{{- printf "cadence-relay.%s" .Values.global.domain -}}
{{- end -}}
{{- end -}}

{{- define "cadence-relay.labels" -}}
app.kubernetes.io/name: cadence-relay
app.kubernetes.io/part-of: cadence
{{- end -}}
