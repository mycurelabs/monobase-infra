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

{{/*
Render a full tenzir.yaml node config. Argument: a dict with:
  root : the chart root context (.)
  geo  : bool — include the geoip-dependent pipelines (20/21) + geoip-city context.

Two variants are rendered into the configmap: a NO-GEO variant (geo=false) and,
when geoip is enabled, a GEO variant (geo=true). The startup wrapper picks the
geo variant only when the MaxMind mmdb is actually present and non-empty — this
is the TRUE fail-open: tenzir-node v6.13.0 exits 139 (SIGSEGV) if a configured
geoip context points at a missing/empty db, so a config that references the
context MUST NOT be selected when the db is absent.
*/}}
{{- define "tenzir.config" -}}
{{- $ := .root -}}
{{- $d := $.Values.detect -}}
tenzir:
  # Node API stays on localhost — nothing external talks to it.
  endpoint: "127.0.0.1:5158"
  pipelines:

    00-ingest:
      name: "ingest: hapihub audit_events (HTTP push, all orgs)"
      # accept_http spins an HTTP/1.1 server; the subpipeline parses each
      # request body. The endpoint is dedicated to the audit sink (path
      # {{ $.Values.ingestPath }}), so no path filter is needed. HMAC
      # verification (webhook-signature header) is a phase-2 flip.
      definition: |
        accept_http "0.0.0.0:{{ $.Values.ingestPort }}" {
          read_json
        }
        where collection == "audit_events" and operation == "INSERT"
        this = document
        publish "audit"
      restart-on-error: 10s
      unstoppable: true

    10-failed-logins:
      name: "detect: failed logins burst (T1110)"
      definition: |
        subscribe "audit"
        where action == "auth.sign_in_failed" or action == "auth.mfa_failed"
        every {{ $d.failedLogins.window }} {
          summarize ip, n=count(), org=first(organization), emails=distinct(meta.email)
        }
        where n >= {{ $d.failedLogins.threshold }}
        this = {
          signal: "failed_logins", severity: "warning", attck: "T1110",
          ocsf_class_uid: 3002,
          title: f"Failed-login burst from {ip}",
          description: f"{n} failed sign-ins from {ip} in {{ $d.failedLogins.window }}",
          entity: {ip: ip, organization: org, emails: emails},
          time: now(),
        }
        publish "findings"
      restart-on-error: 10s

    11-mass-export:
      name: "detect: mass PHI export (T1567)"
      definition: |
        subscribe "audit"
        where action == "phi.record_exported"
        every {{ $d.massExport.window }} {
          summarize actor, n=count(), org=first(organization), ip=first(ip)
        }
        where n >= {{ $d.massExport.threshold }}
        this = {
          signal: "mass_export", severity: "critical", attck: "T1567",
          ocsf_class_uid: 4001,
          title: f"Mass PHI export by {actor}",
          description: f"{n} records exported by actor {actor} in {{ $d.massExport.window }}",
          entity: {actor: actor, organization: org, ip: ip},
          time: now(),
        }
        publish "findings"
      restart-on-error: 10s

    12-late-night:
      name: "detect: late-night access (T1078)"
      definition: |
        subscribe "audit"
        where action == "auth.sign_in" and outcome == "success"
        hr = (occurred_at + {{ $d.lateNight.tzOffsetHours }}h).hour()
        where hr >= {{ $d.lateNight.startHour }} and hr < {{ $d.lateNight.endHour }}
        this = {
          signal: "late_night", severity: "warning", attck: "T1078",
          ocsf_class_uid: 3002,
          title: f"Late-night sign-in by {actor}",
          description: f"Sign-in by {actor} at local hour {hr} from {ip}",
          entity: {actor: actor, organization: organization, ip: ip, hour: hr},
          time: occurred_at,
        }
        publish "findings"
      restart-on-error: 10s

    13-privilege-change:
      name: "detect: privilege escalation (T1098)"
      definition: |
        subscribe "audit"
        where action == "org.member_role_changed"
        where meta.to == "admin" or meta.to == "owner" or meta.to == "superadmin"
        where not (meta.from == "admin" or meta.from == "owner" or meta.from == "superadmin")
        this = {
          signal: "privilege_change", severity: "critical", attck: "T1098",
          ocsf_class_uid: 3006,
          title: f"Role escalated to {meta.to}",
          description: f"Member {meta.userId} role {meta.from} -> {meta.to} in org {organization}",
          entity: {target: meta.userId, organization: organization, from: meta.from, to: meta.to},
          time: occurred_at,
        }
        publish "findings"
      restart-on-error: 10s

    14-concurrent-sessions:
      name: "detect: concurrent sessions (heuristic; T1078)"
      definition: |
        // Reconstruct live sessions from the audit stream. sign_out fires only
        // on explicit logout (expiry is NOT audited), so open = sign_ins minus
        // sign_outs OVERCOUNTS — the window bounds the overcount (a stale
        // sign_in ages out of the window ~= the TTL heuristic). Tune in staging.
        subscribe "audit"
        where action == "auth.sign_in" or action == "auth.sign_out"
        every {{ $d.concurrentSessions.ttl }} {
          summarize actor, ins=count_if(action, a => a == "auth.sign_in"), outs=count_if(action, a => a == "auth.sign_out"), org=first(organization)
        }
        open = ins - outs
        where open >= {{ $d.concurrentSessions.threshold }}
        this = {
          signal: "concurrent_sessions", severity: "warning", attck: "T1078",
          ocsf_class_uid: 3002,
          title: f"{open} concurrent sessions for {actor}",
          description: f"~{open} open sessions for actor {actor} (heuristic over {{ $d.concurrentSessions.ttl }})",
          entity: {actor: actor, organization: org, open: open},
          time: now(),
        }
        publish "findings"
      restart-on-error: 10s

    15-bulk-view:
      name: "detect: bulk PHI record viewing (T1530)"
      # Sibling of 11-mass-export: phi.record_accessed shares the exact event
      # envelope of phi.record_exported (actor, organization, ip all present;
      # confirmed against hapihub actions.ts + phi-emitters.e2e). Viewing (not
      # exporting) a large number of records in one window is data-staging /
      # recon rather than exfil — hence T1530 (data from local system) vs the
      # T1567 (exfil) of mass-export. Threshold/window in values .detect.bulkView.
      definition: |
        subscribe "audit"
        where action == "phi.record_accessed"
        every {{ $d.bulkView.window }} {
          summarize actor, n=count(), org=first(organization), ip=first(ip)
        }
        where n >= {{ $d.bulkView.threshold }}
        this = {
          signal: "bulk_patient_view", severity: "warning", attck: "T1530",
          ocsf_class_uid: 4001,
          title: f"Bulk patient-record viewing by {actor}",
          description: f"{n} records viewed by actor {actor} in {{ $d.bulkView.window }}",
          entity: {actor: actor, organization: org, ip: ip},
          time: now(),
        }
        publish "findings"
      restart-on-error: 10s
{{- if .geo }}

    20-unusual-country:
      name: "detect: sign-in from unusual country (T1078.004)"
      definition: |
        subscribe "audit"
        where action == "auth.sign_in" and outcome == "success" and ip != null
        context_enrich "geoip-city", key=ip, into=geo
        country = geo.country?.iso_code
        where country != null and not (country in [{{ range $i, $c := $.Values.geoip.allowedCountries }}{{ if $i }}, {{ end }}"{{ $c }}"{{ end }}])
        this = {
          signal: "unusual_country", severity: "warning", attck: "T1078.004",
          ocsf_class_uid: 3002,
          title: f"Sign-in from {country}",
          description: f"Actor {actor} signed in from {country} ({ip})",
          entity: {actor: actor, organization: organization, ip: ip, country: country},
          time: occurred_at,
        }
        publish "findings"
      restart-on-error: 10s

    21-impossible-travel:
      name: "detect: impossible travel (multi-country; T1078)"
      definition: |
        // Country-based, not city geo-velocity: Tenzir has no trig functions
        // (no haversine), and country-level geoip is far more reliable than
        // noisy city coords. If ONE actor signs in from >=2 distinct countries
        // within the window, they can't physically be in both → impossible
        // travel. Over-triggers on VPN/country-hopping; tune the window.
        subscribe "audit"
        where action == "auth.sign_in" and outcome == "success" and ip != null
        context_enrich "geoip-city", key=ip, into=geo
        country = geo.country?.iso_code
        where country != null
        every {{ $d.impossibleTravel.window }} {
          summarize actor, countries=distinct(country), org=first(organization)
        }
        where countries.length() >= 2
        this = {
          signal: "impossible_travel", severity: "critical", attck: "T1078",
          ocsf_class_uid: 3002,
          title: f"Impossible travel for {actor}",
          description: f"Actor {actor} signed in from {countries.length()} countries in {{ $d.impossibleTravel.window }}: {countries}",
          entity: {actor: actor, organization: org, countries: countries},
          time: now(),
        }
        publish "findings"
      restart-on-error: 10s
{{- end }}

    90-route:
      name: "route: findings -> Alertmanager (Discord + email)"
      # Alertmanager v2 POST /api/v2/alerts wants a JSON *array* of alerts.
      # The body subpipeline reshapes each finding into an alert record and
      # encodes the whole batch with `write_json arrays_of_objects=true`, which
      # emits ONE valid JSON array per request (all findings in a to_http batch
      # in a single `[ {...}, {...} ]` body). The earlier approach — building a
      # per-event `"[" + print_json(alert) + "]"` string and `write_lines` —
      # produced ADJACENT arrays (`[{...}]\n[{...}]`) when >1 finding landed in
      # one batch, which is not a valid single request body.
      #
      # EGRESS NOTE (geo findings): unusual_country/impossible_travel put actor,
      # ip and country into the finding `description`/`entity`, which this route
      # forwards to Alertmanager → Discord + Postmark email. That means a client
      # IP + resolved country leave the cluster to Discord/email. Accepted: these
      # are security-team alert channels (same path as the non-geo findings and
      # falcosidekick), and the geo fields are the actionable signal. If that
      # egress is ever unwanted, keep the geo fields Tenzir-only by dropping
      # them from the annotations below (label routing still works).
      #
      # DEDUP NOTE: the alert labels carry no per-entity label (only signal/
      # severity/attck), so Alertmanager groups ALL findings of one signal into a
      # single alert — two different actors tripping impossible_travel dedup into
      # one notification. Acceptable for phase-1 alert volume; add an `entity`/
      # `actor` label here if per-entity notifications are needed later.
      definition: |
        subscribe "findings"
        this = {
          labels: {
            alertname: f"security_{signal}",
            severity: severity,
            signal: signal,
            attck: attck,
            source: "tenzir",
          },
          annotations: {
            summary: title,
            description: description,
          },
          startsAt: time,
        }
        to_http "{{ $.Values.alertmanager.url }}", method="POST", headers={"Content-Type": "application/json"} {
          write_json arrays_of_objects=true
        }
      restart-on-error: 30s
{{- if .geo }}

  # GeoIP context loaded from the MaxMind DB the init container fetched. Only
  # present in the geo variant — a context pointing at a missing db crashes the
  # node (v6.13.0 exits 139), so the no-geo variant must omit it entirely.
  #
  # MUST be nested under `tenzir:` (as `tenzir.contexts.<name>`): tenzir parses
  # contexts from the `tenzir.contexts` config section, not a document-root
  # `contexts` key. Rendered at document root the context is silently ignored and
  # GeoIP enrichment is never configured.
  contexts:
    geoip-city:
      type: geoip
      arguments:
        db-path: /geoip/GeoLite2-City.mmdb
{{- end }}
{{- end }}
