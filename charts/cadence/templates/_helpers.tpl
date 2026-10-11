{{/* Chart name */}}
{{- define "cadence.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name */}}
{{- define "cadence.fullname" -}}
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

{{/* Chart label */}}
{{- define "cadence.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "cadence.labels" -}}
helm.sh/chart: {{ include "cadence.chart" . }}
{{ include "cadence.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: monobase
{{- end }}

{{/*
Selector labels. `cadence.name` = nameOverride or the chart name, so the stock `cadence` release keeps
`app.kubernetes.io/name: cadence` (an immutable Deployment selector — changing it would force a
delete/recreate of the live hub) while a second engine in the same namespace (e.g. release
`cadence-easyjoey` with nameOverride cadence-easyjoey) gets its own selector and never captures the
other hub's pods into its Service/NetworkPolicy.
*/}}
{{- define "cadence.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cadence.name" . }}
{{- end }}

{{/* Namespace */}}
{{- define "cadence.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/* Service account name */}}
{{- define "cadence.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cadence.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Gateway parent ref */}}
{{- define "cadence.gateway.name" -}}
{{- required "global.gateway.name is required (set in the deployment values, e.g. values/deployments/_base)" .Values.global.gateway.name }}
{{- end }}
{{- define "cadence.gateway.namespace" -}}
{{- required "global.gateway.namespace is required (set in the deployment values)" .Values.global.gateway.namespace }}
{{- end }}
{{- define "cadence.gateway.hostname" -}}
{{- if .Values.gateway.hostname }}{{ .Values.gateway.hostname }}{{ else }}{{ printf "%s.%s" (include "cadence.fullname" .) .Values.global.domain }}{{ end }}
{{- end }}

{{/* PostgreSQL coordinates for the isolated cadence_v2 database */}}
{{- define "cadence.postgresql.host" -}}
{{- printf "%s.%s.svc.cluster.local" (.Values.postgresql.serviceName | default "postgresql") (include "cadence.namespace" .) -}}
{{- end }}
{{- define "cadence.postgresql.database" -}}
{{- .Values.postgresql.auth.database | default "cadence_v2" -}}
{{- end }}
{{- define "cadence.postgresql.username" -}}
{{- .Values.postgresql.auth.username | default "postgres" -}}
{{- end }}

{{/*
Metadata-schema URL suffix. Empty `postgresql.metadataSchema` (the stock MYCURE hub) => "" so the URL is
unchanged (the engine keeps its historical "$user", public resolution). Set => SQLx `options[search_path]`
selecting exactly that schema + pg_temp, the format cadence's PgStore accepts as an explicit metadata
namespace (services/cadence/crates/cadence-store/src/postgres.rs metadata_namespace; docs/config.md
#authoritative-application-database). Node identity, grant, capture queue + functions, scope memberships
and fingerprints then live in that schema; application tables still resolve in public. The engine
refuses a missing/system/public-fallback schema at startup — the guard here fails the render earlier
for the names it would refuse anyway.
*/}}
{{- define "cadence.postgresql.urlOptions" -}}
{{- with .Values.postgresql.metadataSchema -}}
{{- if or (not (regexMatch "^[a-z_][a-z0-9_]{0,39}$" .)) (hasPrefix "pg_" .) (has . (list "public" "information_schema" "drizzle" "pgboss")) -}}
{{- fail (printf "postgresql.metadataSchema %q is not a usable Cadence metadata schema: lowercase [a-z0-9_], at most 40 chars, not pg_*/public/information_schema/drizzle/pgboss (leave it empty for the historical public metadata)." .) -}}
{{- end -}}
{{- printf "?options%%5Bsearch_path%%5D=%s%%2Cpg_temp" . -}}
{{- end -}}
{{- end }}

{{/*
Finite enrollment scope for a registered product client (`auth.clientId`, e.g. easyjoey-native). The
engine refuses wildcard enrollment for a registered client on a shared database (cadence main.rs
auth_login), so the render fails first: `auth.enrollScope` must be a space-separated list of
`org:<id>` tokens. Only called when auth.clientId is set — the stock hub keeps its '*' anchor grant.
*/}}
{{- define "cadence.enrollScope" -}}
{{- $scope := .Values.auth.enrollScope | default "" | trim -}}
{{- if not $scope -}}
{{- fail "auth.enrollScope is required with auth.clientId: list the clinic organizations explicitly, e.g. 'org:<id> org:<id>' (a registered client cannot enroll '*')." -}}
{{- end -}}
{{- range (splitList " " $scope) -}}
{{- if and . (or (not (regexMatch `^org:[^*\s]+$` .)) (eq . "org:*")) -}}
{{- fail (printf "auth.enrollScope token %q is not a finite org:<id> scope: wildcard or non-org enrollment is unsafe on a shared database (cadence refuses it; so does this chart)." .) -}}
{{- end -}}
{{- end -}}
{{- $scope -}}
{{- end }}
