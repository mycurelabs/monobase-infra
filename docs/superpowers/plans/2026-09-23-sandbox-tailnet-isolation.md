# Sandbox Tailnet Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `mycure-sandbox` on a separate Tailscale account while staging and preprod keep the existing shared device.

**Architecture:** The sandbox's four gateway listeners move to a new `nginx-sandbox-gateway` (ClusterIP, not annotated for the operator). A new `tailscale-proxy` chart runs one unprivileged `tailscale/tailscale` pod in `mycure-sandbox` that joins the new tailnet with an OAuth-client key and TCP-forwards :443 to that gateway's Service via `tailscale serve`. The sandbox overlay points `global.gateway.name` at the new gateway and enables the proxy through the existing app registry.

**Tech Stack:** Helm 3, ArgoCD app-of-apps (`charts/argocd-applications`), NGINX Gateway Fabric, External Secrets Operator (ClusterSecretStore `gcp-secretstore`), Tailscale containerboot v1.98.9, `yq` v4 for render assertions, `mise` tasks for lint.

**Spec:** `docs/superpowers/specs/2026-09-23-sandbox-tailnet-isolation-design.md`

**Working directory for every task:** `mycure-infra/.claude/worktrees/feat-sandbox-tailnet` (branch `feat/sandbox-tailnet`). Never edit the main checkout.

**Scratch dir for render output:** `$SCRATCH` = the session scratchpad directory (not `/tmp`).

**Amendments after review (2026-09-23, Tasks 1–8 done):** the shipped
`deployment.yaml` additionally sets `TS_SOCKET=/var/run/tailscale/tailscaled.sock`
(containerboot's default `/tmp/tailscaled.sock` is not where the `tailscale` CLI
looks, so the `tailscale ip -4` commands in Tasks 9–10 need it) and
`readOnlyRootFilesystem: true`. Task 9 must not push until the GCP secret exists:
between commit A and commit B the sandbox is unreachable from every tailnet.

---

## File map

| Path | Responsibility |
| --- | --- |
| `charts/tailscale-proxy/Chart.yaml` | Chart identity, appVersion pins the tailscale image tag. |
| `charts/tailscale-proxy/values.yaml` | All knobs: hostname, tag, authkey source, target, image, resources. |
| `charts/tailscale-proxy/templates/_helpers.tpl` | Names, labels, namespace, state/auth Secret names. |
| `charts/tailscale-proxy/templates/configmap.yaml` | `serve.json` (TCP 443 → target). |
| `charts/tailscale-proxy/templates/deployment.yaml` | The proxy pod. |
| `charts/tailscale-proxy/templates/externalsecret.yaml` | Auth key from GCP Secret Manager. |
| `charts/tailscale-proxy/templates/rbac.yaml` | ServiceAccount + Role + RoleBinding for the state Secret. |
| `charts/tailscale-proxy/templates/networkpolicy.yaml` | Egress allow-list (DNS, gateway ns, control plane, WireGuard). |
| `values/deployments/base.yaml` | Registry entry + disabled `tailscaleProxy` block. |
| `values/deployments/mycure-sandbox.yaml` | Gateway override + enabled `tailscaleProxy` block. |
| `values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml` | Gateway split. |
| `mise.toml` | Leaf-chart render line in `lint-helm`. |
| `values/clusters/mycure-onprem-vanaheim/README.md` | Access docs for the sandbox device. |

---

### Task 1: Chart scaffold (Chart.yaml, values.yaml, helpers)

**Files:**

- Create: `charts/tailscale-proxy/Chart.yaml`
- Create: `charts/tailscale-proxy/values.yaml`
- Create: `charts/tailscale-proxy/templates/_helpers.tpl`

- [ ] **Step 1: Run the render to verify the chart does not exist yet**

Run: `helm template t charts/tailscale-proxy`
Expected: `Error: ... charts/tailscale-proxy: no such file or directory` (or similar "path not found").

- [ ] **Step 2: Create `Chart.yaml`**

```yaml
apiVersion: v2
name: tailscale-proxy
description: One unprivileged tailscale node that joins a tailnet and TCP-forwards :443 to a cluster Service (per-namespace tailnet exposure when the cluster-wide operator serves a different tailnet)
type: application
version: 1.0.0
appVersion: "v1.98.9"
home: https://github.com/mycurelabs/monobase-infra
sources:
  - https://github.com/tailscale/tailscale
```

- [ ] **Step 3: Create `values.yaml`**

```yaml
# tailscale-proxy — a single userspace tailscale node that exposes ONE cluster
# Service on a tailnet by TCP-forwarding tailnet :443 to it (tailscale serve).
#
# Why not the tailscale-operator? The operator joins exactly one tailnet. When
# a namespace must live on a DIFFERENT account (mycure-sandbox on vanaheim),
# it gets its own node via this chart instead. Runs non-root, no NET_ADMIN,
# no tun device — fits PSA=restricted tenant namespaces.

global:
  namespace: ""      # injected by the argocd-applications factory
  partOf: ""         # app.kubernetes.io/part-of; factory injects the tenant value
  gateway:
    namespace: nginx-gateway-system   # netpol: where the forward target lives

enabled: false

nameOverride: ""
fullnameOverride: ""

image:
  repository: ghcr.io/tailscale/tailscale
  tag: ""            # empty -> Chart.appVersion
  pullPolicy: IfNotPresent

# Tailnet device name (TS_HOSTNAME). Required.
hostname: ""

# ACL tag advertised on join (--advertise-tags). Required: an OAuth-client
# secret used as an auth key only works with one of the client's tags.
tag: ""

# Auth key source. The GCP secret VALUE must be the OAuth client secret with
# node options appended, e.g.
#   tskey-client-xxxx?ephemeral=false&preauthorized=true
# ephemeral=false is load-bearing: OAuth-derived keys default to ephemeral,
# and an ephemeral node is deleted (new IP) on every pod restart.
authkey:
  secretStore: gcp-secretstore
  secretStoreKind: ClusterSecretStore
  refreshInterval: 1h
  remoteKey: ""      # required

# host:port that tailnet :443 is forwarded to (raw TCP, TLS passes through so
# the backend still sees the SNI). Required.
target: ""

resources:
  requests:
    cpu: 10m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi

nodeSelector: {}
tolerations: []
```

- [ ] **Step 4: Create `templates/_helpers.tpl`**

```
{{/*
Expand the name of the chart.
*/}}
{{- define "tailscale-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. The argocd-applications factory releases this chart
as "tailscale-proxy", which contains the chart name, so fullname == release.
*/}}
{{- define "tailscale-proxy.fullname" -}}
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

{{- define "tailscale-proxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tailscale-proxy.labels" -}}
helm.sh/chart: {{ include "tailscale-proxy.chart" . }}
{{ include "tailscale-proxy.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.global.partOf | default "mycureapp" }}
{{- end }}

{{- define "tailscale-proxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tailscale-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "tailscale-proxy.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/* Kubernetes Secret holding tailscaled state (TS_KUBE_SECRET). */}}
{{- define "tailscale-proxy.stateSecret" -}}
{{- include "tailscale-proxy.fullname" . }}-state
{{- end }}

{{/* Kubernetes Secret (ESO target) holding the auth key. */}}
{{- define "tailscale-proxy.authSecret" -}}
{{- include "tailscale-proxy.fullname" . }}-auth
{{- end }}

{{- define "tailscale-proxy.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
```

- [ ] **Step 5: Verify the chart lints and renders nothing while disabled**

Run: `helm lint charts/tailscale-proxy && helm template t charts/tailscale-proxy | grep -c '^kind:'`
Expected: `1 chart(s) linted, 0 chart(s) failed` and then `0` (no resources rendered; the grep returning exit 1 with `0` is fine).

- [ ] **Step 6: Commit**

```bash
git add charts/tailscale-proxy
git commit -m "feat(tailscale-proxy): chart scaffold — values + helpers for a per-namespace tailnet node"
```

---

### Task 2: Deployment + serve ConfigMap

**Files:**

- Create: `charts/tailscale-proxy/templates/configmap.yaml`
- Create: `charts/tailscale-proxy/templates/deployment.yaml`

- [ ] **Step 1: Write the render check and confirm it fails (nothing rendered yet)**

Save as `$SCRATCH/render.sh` (not committed):

```bash
#!/usr/bin/env bash
# Renders charts/tailscale-proxy with sandbox-shaped values to stdout.
set -eu
helm template tailscale-proxy charts/tailscale-proxy \
  --namespace mycure-sandbox \
  --set enabled=true \
  --set hostname=nginx-sandbox-gateway \
  --set tag=tag:sandbox-gateway \
  --set authkey.remoteKey=mycure-sandbox-tailscale-authkey \
  --set target=nginx-sandbox-gateway-nginx.nginx-gateway-system.svc.cluster.local:443 \
  --set global.namespace=mycure-sandbox \
  --set global.partOf=mycureapp
```

Run: `chmod +x $SCRATCH/render.sh && $SCRATCH/render.sh | yq -N 'select(.kind=="Deployment") | .spec.template.spec.containers[0].env[] | select(.name=="TS_HOSTNAME") | .value'`
Expected: empty output (no Deployment yet).

- [ ] **Step 2: Create `templates/configmap.yaml`**

```yaml
{{- if .Values.enabled }}
{{- $target := required "tailscale-proxy: `target` is required (host:port that tailnet :443 is forwarded to)" .Values.target }}
# ipn.ServeConfig applied by containerboot (TS_SERVE_CONFIG). Raw TCP forward:
# tailscaled does NOT terminate TLS, so the target (nginx) still sees the SNI.
# TCPForward is dialed with the system resolver, so a cluster DNS name works.
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "tailscale-proxy.fullname" . }}-serve
  namespace: {{ include "tailscale-proxy.namespace" . }}
  labels:
    {{- include "tailscale-proxy.labels" . | nindent 4 }}
data:
  serve.json: {{ dict "TCP" (dict "443" (dict "TCPForward" $target)) | toJson | quote }}
{{- end }}
```

- [ ] **Step 3: Create `templates/deployment.yaml`**

```yaml
{{- if .Values.enabled }}
{{- $hostname := required "tailscale-proxy: `hostname` is required (tailnet device name)" .Values.hostname }}
{{- $tag := required "tailscale-proxy: `tag` is required (e.g. tag:sandbox-gateway — must be one of the OAuth client's tags)" .Values.tag }}
# Follows tailscale's own docs/k8s/userspace-sidecar.yaml: non-root, userspace
# networking (no tun, no NET_ADMIN), state in a Kubernetes Secret. Fits
# PSA=restricted tenant namespaces.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "tailscale-proxy.fullname" . }}
  namespace: {{ include "tailscale-proxy.namespace" . }}
  labels:
    {{- include "tailscale-proxy.labels" . | nindent 4 }}
spec:
  # ponytail: single replica by design — node identity lives in ONE state
  # Secret; a second pod would fight over it. Recreate so the old pod releases
  # the Secret before the new one starts.
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      {{- include "tailscale-proxy.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/serve-config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "tailscale-proxy.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "tailscale-proxy.fullname" . }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: tailscale
          image: {{ include "tailscale-proxy.image" . | quote }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          env:
            - name: TS_AUTHKEY
              valueFrom:
                secretKeyRef:
                  name: {{ include "tailscale-proxy.authSecret" . }}
                  key: authkey
            # Required when TS_AUTHKEY is an OAuth client secret.
            - name: TS_EXTRA_ARGS
              value: "--advertise-tags={{ $tag }}"
            - name: TS_HOSTNAME
              value: {{ $hostname | quote }}
            - name: TS_USERSPACE
              value: "true"
            # Node identity persists here -> stable tailnet IP across restarts.
            - name: TS_KUBE_SECRET
              value: {{ include "tailscale-proxy.stateSecret" . }}
            - name: TS_AUTH_ONCE
              value: "true"
            # Keep cluster DNS: the serve target is a cluster hostname.
            - name: TS_ACCEPT_DNS
              value: "false"
            - name: TS_SERVE_CONFIG
              value: /etc/tailscale/serve.json
            - name: TS_ENABLE_HEALTH_CHECK
              value: "true"
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_UID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.uid
          ports:
            - name: health
              containerPort: 9002
              protocol: TCP
          # /healthz is 200 once tailscaled is up and holds a tailnet IP.
          readinessProbe:
            httpGet:
              path: /healthz
              port: health
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: health
            initialDelaySeconds: 60
            periodSeconds: 30
            failureThreshold: 6
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          volumeMounts:
            - name: serve-config
              mountPath: /etc/tailscale
              readOnly: true
            - name: run
              mountPath: /var/run/tailscale
            - name: state
              mountPath: /var/lib/tailscale
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: serve-config
          configMap:
            name: {{ include "tailscale-proxy.fullname" . }}-serve
        - name: run
          emptyDir: {}
        - name: state
          emptyDir: {}
        - name: tmp
          emptyDir: {}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
```

- [ ] **Step 4: Verify the render**

Run:

```bash
$SCRATCH/render.sh | yq -N 'select(.kind=="Deployment") | .spec.template.spec.containers[0].env[] | select(.name=="TS_HOSTNAME" or .name=="TS_EXTRA_ARGS" or .name=="TS_KUBE_SECRET") | .name + "=" + .value'
$SCRATCH/render.sh | yq -N 'select(.kind=="Deployment") | .spec.strategy.type + " " + (.spec.template.spec.securityContext.runAsUser|tostring) + " " + .spec.template.spec.containers[0].image'
$SCRATCH/render.sh | yq -N 'select(.kind=="ConfigMap") | .data["serve.json"]'
```

Expected, in order:

```
TS_EXTRA_ARGS=--advertise-tags=tag:sandbox-gateway
TS_HOSTNAME=nginx-sandbox-gateway
TS_KUBE_SECRET=tailscale-proxy-state
Recreate 1000 ghcr.io/tailscale/tailscale:v1.98.9
{"TCP":{"443":{"TCPForward":"nginx-sandbox-gateway-nginx.nginx-gateway-system.svc.cluster.local:443"}}}
```

(env order may differ; the three lines must all appear.)

- [ ] **Step 5: Verify the required-value guards fire**

Run: `helm template t charts/tailscale-proxy --set enabled=true --set tag=tag:x --set authkey.remoteKey=k --set target=svc:443 2>&1 | grep -c 'hostname. is required'`
Expected: `1` (the render aborts with the `required` message naming `hostname`).

- [ ] **Step 6: Commit**

```bash
git add charts/tailscale-proxy/templates/configmap.yaml charts/tailscale-proxy/templates/deployment.yaml
git commit -m "feat(tailscale-proxy): deployment + serve config (userspace, non-root, TCP 443 forward)"
```

---

### Task 3: ExternalSecret, ServiceAccount, RBAC

**Files:**

- Create: `charts/tailscale-proxy/templates/externalsecret.yaml`
- Create: `charts/tailscale-proxy/templates/rbac.yaml`

- [ ] **Step 1: Confirm the render has no Role yet**

Run: `$SCRATCH/render.sh | yq -N 'select(.kind=="Role") | .metadata.name'`
Expected: empty.

- [ ] **Step 2: Create `templates/externalsecret.yaml`**

```yaml
{{- if .Values.enabled }}
{{- $remoteKey := required "tailscale-proxy: `authkey.remoteKey` is required (GCP secret holding `tskey-client-…?ephemeral=false&preauthorized=true`)" .Values.authkey.remoteKey }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ include "tailscale-proxy.authSecret" . }}
  namespace: {{ include "tailscale-proxy.namespace" . }}
  labels:
    {{- include "tailscale-proxy.labels" . | nindent 4 }}
spec:
  refreshInterval: {{ .Values.authkey.refreshInterval }}
  secretStoreRef:
    name: {{ .Values.authkey.secretStore }}
    kind: {{ .Values.authkey.secretStoreKind }}
  target:
    name: {{ include "tailscale-proxy.authSecret" . }}
    creationPolicy: Owner
  data:
    - secretKey: authkey
      remoteRef:
        key: {{ $remoteKey }}
{{- end }}
```

- [ ] **Step 3: Create `templates/rbac.yaml`** (mirrors tailscale `docs/k8s/role.yaml`)

```yaml
{{- if .Values.enabled }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "tailscale-proxy.fullname" . }}
  namespace: {{ include "tailscale-proxy.namespace" . }}
  labels:
    {{- include "tailscale-proxy.labels" . | nindent 4 }}
---
# containerboot stores tailscaled state in TS_KUBE_SECRET. `create` cannot be
# scoped by resourceName; everything else is pinned to the one state Secret.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "tailscale-proxy.fullname" . }}
  namespace: {{ include "tailscale-proxy.namespace" . }}
  labels:
    {{- include "tailscale-proxy.labels" . | nindent 4 }}
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: [{{ include "tailscale-proxy.stateSecret" . | quote }}]
    verbs: ["get", "update", "patch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "create", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "tailscale-proxy.fullname" . }}
  namespace: {{ include "tailscale-proxy.namespace" . }}
  labels:
    {{- include "tailscale-proxy.labels" . | nindent 4 }}
subjects:
  - kind: ServiceAccount
    name: {{ include "tailscale-proxy.fullname" . }}
    namespace: {{ include "tailscale-proxy.namespace" . }}
roleRef:
  kind: Role
  name: {{ include "tailscale-proxy.fullname" . }}
  apiGroup: rbac.authorization.k8s.io
{{- end }}
```

- [ ] **Step 4: Verify**

Run:

```bash
$SCRATCH/render.sh | yq -N 'select(.kind=="Role") | .rules[1].resourceNames[0]'
$SCRATCH/render.sh | yq -N 'select(.kind=="ExternalSecret") | .spec.secretStoreRef.kind + " " + .spec.secretStoreRef.name + " " + .spec.data[0].remoteRef.key + " -> " + .spec.target.name'
$SCRATCH/render.sh | yq -N 'select(.kind=="Deployment") | .spec.template.spec.serviceAccountName'
```

Expected:

```
tailscale-proxy-state
ClusterSecretStore gcp-secretstore mycure-sandbox-tailscale-authkey -> tailscale-proxy-auth
tailscale-proxy
```

- [ ] **Step 5: Commit**

```bash
git add charts/tailscale-proxy/templates/externalsecret.yaml charts/tailscale-proxy/templates/rbac.yaml
git commit -m "feat(tailscale-proxy): auth key ExternalSecret + RBAC for the state Secret"
```

---

### Task 4: NetworkPolicy

**Files:**

- Create: `charts/tailscale-proxy/templates/networkpolicy.yaml`

Context: `mycure-sandbox` carries `default-deny-egress` from security-baseline. Without this policy the pod can't reach DNS, the control plane, the API server (state Secret, k3d apiserver on TCP 6443), or the gateway.

- [ ] **Step 1: Confirm no NetworkPolicy renders yet**

Run: `$SCRATCH/render.sh | yq -N 'select(.kind=="NetworkPolicy") | .metadata.name'`
Expected: empty.

- [ ] **Step 2: Create `templates/networkpolicy.yaml`**

```yaml
{{- if .Values.enabled }}
# Egress allow-list for the tailscale node (the namespace default-denies egress).
# No ingress rule: tailnet traffic arrives inside WireGuard/DERP flows the pod
# itself opened outbound, so conntrack admits the replies.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "tailscale-proxy.fullname" . }}
  namespace: {{ include "tailscale-proxy.namespace" . }}
  labels:
    {{- include "tailscale-proxy.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "tailscale-proxy.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    # Cluster DNS (resolves the serve target).
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # The forward target: the gateway data plane.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.global.gateway.namespace }}
      ports:
        - protocol: TCP
          port: 443
    # Tailscale control plane + DERP relays (TCP 443), Kubernetes API server
    # for the state Secret (TCP 443 managed / 6443 k3s), direct WireGuard
    # (UDP 41641) and STUN (UDP 3478). DERP alone suffices if UDP is blocked.
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 6443
        - protocol: UDP
          port: 41641
        - protocol: UDP
          port: 3478
{{- end }}
```

- [ ] **Step 3: Verify**

Run: `$SCRATCH/render.sh | yq -N 'select(.kind=="NetworkPolicy") | (.spec.egress | length | tostring) + " rules; gw ns=" + .spec.egress[1].to[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] + "; world ports=" + ([.spec.egress[2].ports[] | .protocol + "/" + (.port|tostring)] | join(","))'`
Expected: `3 rules; gw ns=nginx-gateway-system; world ports=TCP/443,TCP/6443,UDP/41641,UDP/3478`

- [ ] **Step 4: Full chart lint**

Run: `helm lint charts/tailscale-proxy --set enabled=true --set hostname=x --set tag=tag:x --set authkey.remoteKey=k --set target=svc:443`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 5: Commit**

```bash
git add charts/tailscale-proxy/templates/networkpolicy.yaml
git commit -m "feat(tailscale-proxy): egress NetworkPolicy (DNS, gateway ns, control plane, WireGuard)"
```

---

### Task 5: Registry wiring in `base.yaml` + lint line

**Files:**

- Modify: `values/deployments/base.yaml` (the `appRegistry` map, and the "Registry apps with no base config" section that ends with the `pgLogicalBackup:` block around line 142)
- Modify: `mise.toml` (`[tasks.lint-helm]`, after the `monitoring-resources` render line ~106)

- [ ] **Step 1: Confirm the factory refuses an unknown key (baseline)**

Run: `helm template lint charts/argocd-applications -f values/deployments/base.yaml -f values/deployments/mycure-sandbox.yaml --set argocd.repoURL=lint --set argocd.targetRevision=lint | yq -N 'select(.kind=="Application") | .metadata.name' | grep -c tailscale-proxy`
Expected: `0`

- [ ] **Step 2: Add the registry entry**

In `values/deployments/base.yaml`, inside `appRegistry:` after the `pg-logical-backup:` entry, add:

```yaml
  tailscale-proxy:
    key: tailscaleProxy
```

- [ ] **Step 3: Add the disabled config block**

In the same file, directly after the `pgLogicalBackup:` block (before the `# ===== HEALTHCARE: MyCure PXP` header), add:

```yaml
# Per-namespace tailnet node (charts/tailscale-proxy). Off everywhere except an
# overlay that must live on a DIFFERENT Tailscale account than the cluster-wide
# operator (mycure-sandbox on vanaheim, monobase-mycure#4509).
tailscaleProxy:
  enabled: false
```

- [ ] **Step 4: Add the leaf-chart render to `mise.toml`**

In `[tasks.lint-helm]`, after the `charts/monitoring-resources` line, add:

```
helm template lint charts/tailscale-proxy --set enabled=true --set hostname=lint --set tag=tag:lint --set authkey.remoteKey=lint --set target=lint.svc:443 --set global.namespace=lint > /dev/null
```

- [ ] **Step 5: Verify the registry renders and nothing new appears anywhere**

Run:

```bash
for ov in mycure-production mycure-staging mycure-preprod mycure-sandbox; do
  printf '%s: ' "$ov"
  helm template lint charts/argocd-applications -f values/deployments/base.yaml -f values/deployments/$ov.yaml --set argocd.repoURL=lint --set argocd.targetRevision=lint | yq -N 'select(.kind=="Application") | .metadata.name' | grep -c tailscale-proxy || true
done
./scripts/lint-app-registry.sh | tail -1
```

Expected: `0` for all four overlays (sandbox is enabled in Task 6), then `[app-registry] OK`.

- [ ] **Step 6: Commit**

```bash
git add values/deployments/base.yaml mise.toml
git commit -m "feat(registry): register tailscale-proxy app (off by default) + lint render"
```

---

### Task 6: Sandbox overlay — gateway override + proxy enabled

**Files:**

- Modify: `values/deployments/mycure-sandbox.yaml` (`global:` block at the top; new block after `securityBaseline:`)

- [ ] **Step 1: Set the gateway override**

In `global:`, replace the comment pair

```yaml
  # No global.gateway override: inherit the DENY-FIRST tailnet-only
  # nginx-internal-gateway from base (sandbox is tailnet-only, like preprod).
```

with

```yaml
  # Sandbox-OWN gateway (values/clusters/mycure-onprem-vanaheim/argocd/
  # infrastructure.yaml). Same namespace as the shared internal gateway, but
  # exposed on the SANDBOX tailnet by the tailscale-proxy below, not by the
  # MyCure operator. Listener names are unchanged, so every sectionName holds.
  gateway:
    name: nginx-sandbox-gateway
```

- [ ] **Step 2: Enable the proxy**

Directly after the `securityBaseline:` block, add:

```yaml
# ===== TAILNET: sandbox-own Tailscale account (monobase-mycure#4509) =====
# The cluster-wide operator serves the MyCure tailnet (staging/preprod). The
# sandbox joins a SEPARATE account via this unprivileged node, which forwards
# tailnet :443 to the sandbox gateway. Device: nginx-sandbox-gateway.
# Prereqs (new tailnet admin console + GCP): tag:sandbox-gateway in tagOwners,
# an auth_keys OAuth client carrying that tag, and GCP secret
# mycure-sandbox-tailscale-authkey = tskey-client-…?ephemeral=false&preauthorized=true
tailscaleProxy:
  enabled: true
  hostname: nginx-sandbox-gateway
  tag: tag:sandbox-gateway
  authkey:
    remoteKey: mycure-sandbox-tailscale-authkey
  target: nginx-sandbox-gateway-nginx.nginx-gateway-system.svc.cluster.local:443
```

- [ ] **Step 3: Verify the Application renders with the right values, only for sandbox**

Run:

```bash
helm template lint charts/argocd-applications -f values/deployments/base.yaml -f values/deployments/mycure-sandbox.yaml --set argocd.repoURL=lint --set argocd.targetRevision=lint \
  | yq -N 'select(.kind=="Application" and .metadata.name=="mycure-sandbox-tailscale-proxy") | .spec.source.path + " ns=" + .spec.destination.namespace + " gw=" + .spec.source.helm.valuesObject.global.gateway.name + " target=" + .spec.source.helm.valuesObject.target'
helm template lint charts/argocd-applications -f values/deployments/base.yaml -f values/deployments/mycure-sandbox.yaml --set argocd.repoURL=lint --set argocd.targetRevision=lint \
  | yq -N 'select(.kind=="Application" and .metadata.name=="mycure-sandbox-hapihub") | .spec.source.helm.valuesObject.global.gateway.name'
for ov in mycure-production mycure-staging mycure-preprod; do
  helm template lint charts/argocd-applications -f values/deployments/base.yaml -f values/deployments/$ov.yaml --set argocd.repoURL=lint --set argocd.targetRevision=lint | yq -N 'select(.kind=="Application") | .metadata.name' | grep -c tailscale-proxy || true
done
```

Expected:

```
charts/tailscale-proxy ns=mycure-sandbox gw=nginx-sandbox-gateway target=nginx-sandbox-gateway-nginx.nginx-gateway-system.svc.cluster.local:443
nginx-sandbox-gateway
0
0
0
```

- [ ] **Step 4: Render the leaf chart with the exact overlay values (what ArgoCD will do)**

Run:

```bash
helm template lint charts/argocd-applications -f values/deployments/base.yaml -f values/deployments/mycure-sandbox.yaml --set argocd.repoURL=lint --set argocd.targetRevision=lint \
  | yq 'select(.kind=="Application" and .metadata.name=="mycure-sandbox-tailscale-proxy") | .spec.source.helm.valuesObject' > "$SCRATCH/sandbox-tsproxy-values.yaml"
helm template tailscale-proxy charts/tailscale-proxy -f "$SCRATCH/sandbox-tsproxy-values.yaml" | yq -N '.kind + "/" + .metadata.name'
```

Expected (order may vary):

```
ConfigMap/tailscale-proxy-serve
Deployment/tailscale-proxy
ExternalSecret/tailscale-proxy-auth
NetworkPolicy/tailscale-proxy
Role/tailscale-proxy
RoleBinding/tailscale-proxy
ServiceAccount/tailscale-proxy
```

- [ ] **Step 5: Commit**

```bash
git add values/deployments/mycure-sandbox.yaml
git commit -m "feat(sandbox): own gateway + tailscale-proxy on a separate tailnet [monobase-mycure#4509]"
```

---

### Task 7: Gateway split on vanaheim

**Files:**

- Modify: `values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml` (the `nginx-internal-gateway` entry under `nginxGatewayResources.extraGateways`, listeners block ending just before `tls:`)

- [ ] **Step 1: Capture the current listener layout (baseline)**

Run:

```bash
yq '.nginxGatewayResources' values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml > "$SCRATCH/ngr.yaml"
helm template lint charts/nginx-gateway -f "$SCRATCH/ngr.yaml" | yq -N 'select(.kind=="Gateway") | .metadata.name + ": " + ([.spec.listeners[].name] | join(","))'
```

Expected: one line for `nginx-internal-gateway` whose list contains `https-sandbox-mycure,https-sandbox-hapihub,https-sandbox-lfh,http-sandbox-lfh` at the end.

- [ ] **Step 2: Remove the sandbox listeners from `nginx-internal-gateway`**

Delete this block (comment plus four listeners) from the internal gateway's `listeners:`:

```yaml
        # ---- sandbox (isolated MediCard sandbox, monobase-mycure#4509). Same
        # anti-HTTP/2-coalescing pattern as preprod: exact-hostname listeners for
        # the app<->api pair + a wildcard for the rest. No QUIC legs — cadence is
        # disabled in the sandbox overlay (no box sync). ----
        - name: https-sandbox-mycure
          port: 443
          protocol: HTTPS
          hostname: "mycure.sandbox.localfirsthealth.com"
          tlsSecretName: nginx-gateway-tls-sandbox-mycure
        - name: https-sandbox-hapihub
          port: 443
          protocol: HTTPS
          hostname: "hapihub.sandbox.localfirsthealth.com"
          tlsSecretName: nginx-gateway-tls-sandbox-hapihub
        - name: https-sandbox-lfh
          port: 443
          protocol: HTTPS
          hostname: "*.sandbox.localfirsthealth.com"
          tlsSecretName: nginx-gateway-tls-sandbox
        - name: http-sandbox-lfh
          port: 80
          protocol: HTTP
          hostname: "*.sandbox.localfirsthealth.com"
```

- [ ] **Step 3: Add the sandbox gateway as a second `extraGateways` entry**

Insert right after the internal gateway entry (i.e. after its last listener `relay-quic-preprod`, still inside `extraGateways:`, before `tls:`):

```yaml
    # ---- SANDBOX gateway (isolated MediCard sandbox, monobase-mycure#4509).
    # Own Gateway so the sandbox can live on a SEPARATE Tailscale account:
    # NOT tailscale.com/expose'd (the MyCure operator must ignore it); instead
    # mycure-sandbox/tailscale-proxy joins the sandbox tailnet as device
    # nginx-sandbox-gateway and forwards tailnet :443 to this gateway's Service
    # (nginx-sandbox-gateway-nginx). Same anti-HTTP/2-coalescing listener
    # pattern as preprod. No QUIC legs — cadence is disabled in the sandbox.
    - name: nginx-sandbox-gateway
      gatewayClassName: nginx
      annotations:
        # external-dns publishes attached routes' hostnames as A records -> the
        # sandbox tailnet device IP. Assigned on first join; PLACEHOLDER = the
        # old shared IP until rollout step B pins the real one (get it with
        # `kubectl -n mycure-sandbox exec deploy/tailscale-proxy -- tailscale ip -4`).
        external-dns.alpha.kubernetes.io/target: "100.124.242.71"
      nginxProxy:
        serviceType: ClusterIP
        replicas: 1
      listeners:
        - name: https-sandbox-mycure
          port: 443
          protocol: HTTPS
          hostname: "mycure.sandbox.localfirsthealth.com"
          tlsSecretName: nginx-gateway-tls-sandbox-mycure
        - name: https-sandbox-hapihub
          port: 443
          protocol: HTTPS
          hostname: "hapihub.sandbox.localfirsthealth.com"
          tlsSecretName: nginx-gateway-tls-sandbox-hapihub
        - name: https-sandbox-lfh
          port: 443
          protocol: HTTPS
          hostname: "*.sandbox.localfirsthealth.com"
          tlsSecretName: nginx-gateway-tls-sandbox
        - name: http-sandbox-lfh
          port: 80
          protocol: HTTP
          hostname: "*.sandbox.localfirsthealth.com"
```

- [ ] **Step 4: Verify the split**

Run:

```bash
yq '.nginxGatewayResources' values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml > "$SCRATCH/ngr.yaml"
helm template lint charts/nginx-gateway -f "$SCRATCH/ngr.yaml" | yq -N 'select(.kind=="Gateway") | .metadata.name + ": " + ([.spec.listeners[].name] | join(","))'
helm template lint charts/nginx-gateway -f "$SCRATCH/ngr.yaml" | yq -N 'select(.kind=="Gateway" and .metadata.name=="nginx-sandbox-gateway") | (.spec.infrastructure.annotations["tailscale.com/expose"] // "none") + " " + .metadata.annotations["external-dns.alpha.kubernetes.io/target"]'
helm template lint charts/nginx-gateway -f "$SCRATCH/ngr.yaml" | yq -N 'select(.kind=="NginxProxy") | .metadata.name + " " + .spec.kubernetes.service.type'
helm template lint charts/argocd-infrastructure -f values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml --set argocd.repoURL=lint --set argocd.targetRevision=lint > /dev/null && echo infra-render-ok
```

Expected:

```
nginx-internal-gateway: https-staging-mycure,...,relay-quic-preprod     (NO *sandbox* names)
nginx-sandbox-gateway: https-sandbox-mycure,https-sandbox-hapihub,https-sandbox-lfh,http-sandbox-lfh
none 100.124.242.71
nginx-internal-gateway-proxy-config ClusterIP
nginx-sandbox-gateway-proxy-config ClusterIP
infra-render-ok
```

- [ ] **Step 5: Commit**

```bash
git add values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml
git commit -m "feat(vanaheim): split sandbox listeners onto nginx-sandbox-gateway (not operator-exposed)"
```

---

### Task 8: Full repo lint + docs

**Files:**

- Modify: `values/clusters/mycure-onprem-vanaheim/README.md` (section `## Access (tailnet-only)`)

- [ ] **Step 1: Run the repo's helm lint and validate tasks**

Run: `mise run lint-helm && mise run validate-helm`
Expected: `✓ All trees render` and `Validating Helm charts...` with exit 0.

- [ ] **Step 2: Run yaml + shell lint**

Run: `mise run lint-yaml && mise run lint-shell`
Expected: exit 0. If `lint-yaml` complains about line length in the new files, wrap the offending comment lines.

- [ ] **Step 3: Document sandbox access in the vanaheim README**

At the end of the `## Access (tailnet-only)` section (after the `/etc/hosts` paragraph), add:

```markdown
### Sandbox: separate Tailscale account

`*.sandbox.localfirsthealth.com` is **not** on the MyCure tailnet. The sandbox has its
own `nginx-sandbox-gateway` (ClusterIP, not operator-exposed) and a
`mycure-sandbox/tailscale-proxy` pod that joins the **sandbox tailnet** as device
`nginx-sandbox-gateway` and forwards tailnet :443 to it (spec:
`docs/superpowers/specs/2026-09-23-sandbox-tailnet-isolation-design.md`).

- Reach it from a device on the sandbox tailnet: `https://mycure.sandbox.localfirsthealth.com`.
- Its tailnet IP is pinned in the `external-dns.alpha.kubernetes.io/target` annotation
  on `nginx-sandbox-gateway` (`argocd/infrastructure.yaml`). If the device is recreated
  (state Secret `tailscale-proxy-state` deleted, or cluster rebuilt) the IP changes:
  `kubectl -n mycure-sandbox exec deploy/tailscale-proxy -- tailscale ip -4`, then update
  the annotation.
- Credential: GCP secret `mycure-sandbox-tailscale-authkey` = OAuth client secret
  (`auth_keys` scope, tag `tag:sandbox-gateway`) with `?ephemeral=false&preauthorized=true`.
```

- [ ] **Step 4: Markdown lint**

Run: `mise run lint-md`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add values/clusters/mycure-onprem-vanaheim/README.md
git commit -m "docs(vanaheim): sandbox lives on its own tailnet — access + IP re-pin notes"
```

---

### Task 9: Deploy commit A to vanaheim (GATED — needs the user's prerequisites)

**Do not start until the user confirms all three:**

1. New tailnet ACL has `tag:sandbox-gateway` in `tagOwners` and a grant to it on :443.
2. OAuth client with `auth_keys` write scope and tag `tag:sandbox-gateway` exists.
3. GCP secret exists. Check without printing it:

Run: `gcloud secrets versions access latest --secret mycure-sandbox-tailscale-authkey --project mc-v4-prod | grep -c '^tskey-client-.*ephemeral=false.*preauthorized=true'`
Expected: `1`

- [ ] **Step 1: Cherry-pick the feature commits onto `cluster/vanaheim`**

Run (from the feature worktree):

```bash
FEAT_RANGE="$(git merge-base origin/main HEAD)..HEAD"
cd ../cluster-vanaheim
git fetch origin
git checkout cluster/vanaheim && git pull --ff-only origin cluster/vanaheim
git cherry-pick $(git -C ../feat-sandbox-tailnet rev-list --reverse $FEAT_RANGE)
git log --oneline -"$(git -C ../feat-sandbox-tailnet rev-list --count $FEAT_RANGE)"
```

Expected: the same commit subjects as on `feat/sandbox-tailnet`, no conflicts (the touched files are identical on both branches as of 2026-09-23).

- [ ] **Step 2: Push (this deploys — ArgoCD auto-syncs)**

Run: `git push origin cluster/vanaheim`

- [ ] **Step 3: Refresh and watch on vanaheim**

Run:

```bash
ssh freyr@100.120.88.93 '
K="mise x kubectl@1.31.1 -- kubectl --context k3d-mycure-onprem-vanaheim"
for a in nginx-gateway-resources mycure-sandbox-root; do $K -n argocd annotate application $a argocd.argoproj.io/refresh=hard --overwrite; done
sleep 60
$K -n argocd get applications | grep -E "nginx-gateway-resources|mycure-sandbox"
$K -n nginx-gateway-system get gateway,svc | grep -E "NAME|sandbox|internal"
$K -n mycure-sandbox get externalsecret tailscale-proxy-auth
$K -n mycure-sandbox get pods -l app.kubernetes.io/name=tailscale-proxy
$K -n mycure-sandbox logs deploy/tailscale-proxy --tail=30'
```

Expected: `nginx-sandbox-gateway` `PROGRAMMED True`; Service `nginx-sandbox-gateway-nginx` ClusterIP with `80/TCP,443/TCP`; ExternalSecret `SecretSynced True`; pod `1/1 Running`; logs show `Startup complete` / serve config applied, no `permission denied`.

If the ExternalSecret is not Ready: the GCP secret name or the ESO SA grant is wrong. If the pod logs `--advertise-tags ... requested tags not permitted`: the tag is not on the OAuth client / not in tagOwners. If `/healthz` never turns 200 and logs show `control: ... dial`: egress is blocked, check `kubectl -n mycure-sandbox get netpol tailscale-proxy -o yaml`.

- [ ] **Step 4: Read the new device IP**

Run: `ssh freyr@100.120.88.93 'mise x kubectl@1.31.1 -- kubectl --context k3d-mycure-onprem-vanaheim -n mycure-sandbox exec deploy/tailscale-proxy -- tailscale ip -4'`
Expected: one `100.x.y.z` address. Record it for Task 10.

- [ ] **Step 5: Prove staging/preprod are untouched**

Run: `ssh freyr@100.120.88.93 'tailscale status | grep nginx-staging-gateway; curl -sI --max-time 10 https://hapihub.preprod.localfirsthealth.com/health | head -1'`
Expected: `100.124.242.71 nginx-staging-gateway-1 ...` and `HTTP/2 200`.

---

### Task 10: Commit B — pin the sandbox tailnet IP

**Files:**

- Modify: `values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml` (the `external-dns.alpha.kubernetes.io/target` annotation on `nginx-sandbox-gateway`)

- [ ] **Step 1: Replace the placeholder (in the feature worktree)**

Change

```yaml
        external-dns.alpha.kubernetes.io/target: "100.124.242.71"
```

under `nginx-sandbox-gateway` to the IP from Task 9 Step 4, and shorten its comment to:

```yaml
        # external-dns publishes attached routes' hostnames as A records -> the
        # sandbox tailnet device IP (assigned by the SANDBOX tailnet on first
        # join; changes if the tailscale-proxy state Secret is lost — re-read
        # with `kubectl -n mycure-sandbox exec deploy/tailscale-proxy -- tailscale ip -4`).
```

- [ ] **Step 2: Verify only that line changed**

Run: `git diff --stat && git diff | grep -c '^[-+] .*target:'`
Expected: one file, and `2` (one removed, one added target line).

- [ ] **Step 3: Commit, cherry-pick, push**

```bash
git add values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml
git commit -m "feat(vanaheim): pin nginx-sandbox-gateway external-dns target to the sandbox tailnet IP"
SHA=$(git rev-parse HEAD)
cd ../cluster-vanaheim && git cherry-pick "$SHA" && git push origin cluster/vanaheim
```

- [ ] **Step 4: Verify DNS moved**

Run (after ~2 min): `dig +short mycure.sandbox.localfirsthealth.com @1.1.1.1; dig +short hapihub.sandbox.localfirsthealth.com @1.1.1.1`
Expected: both print the new sandbox tailnet IP.

- [ ] **Step 5: End-to-end from a device on the sandbox tailnet (user runs this)**

Run: `curl -sI https://mycure.sandbox.localfirsthealth.com | head -1 && curl -s https://hapihub.sandbox.localfirsthealth.com/health`
Expected: `HTTP/2 200` and hapihub's health JSON.

- [ ] **Step 6: Negative check from the MyCure tailnet (this Mac)**

Run: `curl -sI --max-time 10 https://mycure.sandbox.localfirsthealth.com | head -1 || echo unreachable`
Expected: `unreachable` (the IP belongs to a different tailnet).

---

### Task 11: Promote to main

- [ ] **Step 1: Push the feature branch and open the PR**

Run (from the feature worktree):

```bash
git push -u origin feat/sandbox-tailnet
gh pr create --base main --head feat/sandbox-tailnet \
  --title "feat(sandbox): isolate mycure-sandbox on its own Tailscale account [monobase-mycure#4509]" \
  --body "$(cat <<'EOF'
## Summary
- New `charts/tailscale-proxy`: one unprivileged userspace tailscale node that joins a tailnet via OAuth-client key and TCP-forwards :443 to a cluster Service.
- vanaheim: sandbox listeners split off `nginx-internal-gateway` onto `nginx-sandbox-gateway` (ClusterIP, not operator-exposed).
- `mycure-sandbox` overlay: `global.gateway.name=nginx-sandbox-gateway`, `tailscaleProxy` enabled.
- Staging/preprod keep device `nginx-staging-gateway-1` / `100.124.242.71` — unchanged.

Spec: `docs/superpowers/specs/2026-09-23-sandbox-tailnet-isolation-design.md`

## Test plan
(tick each box only after the step has actually been run and observed)
- [x] `mise run lint-helm` / `validate-helm`
- [ ] Deployed on `cluster/vanaheim`; `nginx-sandbox-gateway` Programmed; proxy `/healthz` 200
- [ ] `*.sandbox` A records point at the sandbox tailnet IP; 200 from the sandbox tailnet; unreachable from the MyCure tailnet
- [ ] preprod/staging hosts still 200

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

- [ ] **Step 2: Hand off**

Report the PR URL, the sandbox device IP, and the two follow-ups: (a) invite the users who need the sandbox to the new tailnet, (b) `nginx-internal-gateway` no longer serves `*.sandbox` on the MyCure tailnet.
