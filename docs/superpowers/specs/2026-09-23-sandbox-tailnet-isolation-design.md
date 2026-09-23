# Isolate `mycure-sandbox` on its own tailnet

Date: 2026-09-23. Cluster: `mycure-onprem-vanaheim` (k3d). Tracks monobase-mycure#4509.

## Goal

Reach the sandbox (`*.sandbox.localfirsthealth.com`) only from a new,
separate Tailscale account. Staging and preprod stay on the current MyCure
tailnet, unchanged.

## Current state

The vanaheim cluster has one Tailscale connection. The Tailscale operator
(namespace `tailscale`, OAuth client `infrastructure-tailscale-operator-oauth-*`)
exposes the Service `nginx-internal-gateway-nginx` as device
`nginx-staging-gateway-1` (`100.124.242.71`). Staging, preprod, and sandbox
all publish their routes on that gateway, so they share the device.

The operator joins exactly one tailnet. Its chart (v1.98.9) has no namespace
scoping and no support for a second instance, so it cannot expose the sandbox
on a different account.

## Decisions

| Question | Decision |
| --- | --- |
| Scope | Sandbox only. Staging and preprod keep their device and IP. |
| Credential | OAuth client on the new tailnet, used as a non-expiring auth key. |
| Reachability | New tailnet only. The sandbox disappears from the MyCure tailnet. |
| Public exposure | Rejected. The host is a LAN workstation on a dynamic ISP address; a tunnel would cost more than this design and would expose mailpit and MinIO, which have no login. |
| Second operator | Rejected. Two operators fight over CRDs and over every annotated Service. |

## Design

### 1. Sandbox gets its own Gateway

File: `values/clusters/mycure-onprem-vanaheim/argocd/infrastructure.yaml`.

Move the four sandbox listeners (`https-sandbox-mycure`, `https-sandbox-hapihub`,
`https-sandbox-lfh`, `http-sandbox-lfh`) from `nginx-internal-gateway` to a new
`extraGateways` entry:

```yaml
- name: nginx-sandbox-gateway
  gatewayClassName: nginx
  annotations:
    external-dns.alpha.kubernetes.io/target: "<tailnet-B IP, set in rollout step B>"
  # No tailscale.com/expose: the MyCure operator must ignore this gateway.
  nginxProxy:
    serviceType: ClusterIP
    replicas: 1
  listeners: <the four sandbox listeners, unchanged>
```

Listener names stay the same, so every `sectionName` in the sandbox overlay
still resolves. The TLS Secrets already live in `nginx-gateway-system` and
need no change. NGINX Gateway Fabric names the data-plane Service
`nginx-sandbox-gateway-nginx`.

### 2. New chart `charts/tailscale-proxy`

One unprivileged pod that joins a tailnet and forwards TCP 443 to a cluster
Service. It follows Tailscale's own `docs/k8s/userspace-sidecar.yaml`
(non-root, userspace networking, state in a Kubernetes Secret).

Templates:

| Template | Purpose |
| --- | --- |
| `deployment.yaml` | 1 replica, `strategy: Recreate` (the state Secret has one owner). Image `ghcr.io/tailscale/tailscale:v1.98.9`. `runAsNonRoot`, UID/GID 1000, drop ALL, no privilege escalation, `RuntimeDefault` seccomp. emptyDir at `/var/run/tailscale`, `/var/lib/tailscale`, `/tmp`. Liveness/readiness `GET /healthz` on 9002. |
| `configmap.yaml` | `serve.json`: `{"TCP":{"443":{"TCPForward":"<target>"}}}`. TLS passes through; nginx still terminates it and sees the SNI. |
| `externalsecret.yaml` | `<fullname>-auth` from `gcp-secretstore` (ClusterSecretStore), key `authkey` ← `authkey.remoteKey`. |
| `serviceaccount.yaml`, `rbac.yaml` | Role: `create` on secrets; `get/update/patch` on `<fullname>-state`; `get/create/patch` on events. Same as upstream `docs/k8s/role.yaml`. |
| `networkpolicy.yaml` | Egress only: UDP/TCP 53 → `kube-system`; TCP 443 → `nginx-gateway-system`; TCP 443, UDP 41641, UDP 3478 → `0.0.0.0/0`. No ingress rule: tailnet traffic arrives inside outbound-established WireGuard/DERP flows. |

Container environment:

| Variable | Value | Why |
| --- | --- | --- |
| `TS_AUTHKEY` | secretKeyRef `<fullname>-auth/authkey` | OAuth client secret with `?ephemeral=false&preauthorized=true`. |
| `TS_EXTRA_ARGS` | `--advertise-tags=<tag>` | Required when the auth key is an OAuth client secret. |
| `TS_HOSTNAME` | `<hostname>` | Device name on the tailnet. |
| `TS_USERSPACE` | `true` | No tun device, no NET_ADMIN; passes PSA `restricted`. |
| `TS_KUBE_SECRET` | `<fullname>-state` | Node identity survives restarts, so the tailnet IP is stable. |
| `TS_AUTH_ONCE` | `true` | Reuse the stored identity instead of re-logging in. |
| `TS_ACCEPT_DNS` | `false` | Keep cluster DNS; the serve target is a cluster hostname. |
| `TS_SERVE_CONFIG` | `/etc/tailscale/serve.json` | Applied once tailscaled is up; the file is watched. |
| `TS_ENABLE_HEALTH_CHECK` | `true` | Serves `/healthz` on `TS_LOCAL_ADDR_PORT` (default `[::]:9002`). |
| `TS_SOCKET` | `/var/run/tailscale/tailscaled.sock` | containerboot defaults to `/tmp/tailscaled.sock`; the `tailscale` CLI looks in `/var/run/tailscale/`. Aligning them makes `kubectl exec … tailscale ip -4` work. |
| `POD_NAME`, `POD_UID` | fieldRef | Upstream example; containerboot records them as data keys in the state Secret. It sets no ownerReference, so the Secret outlives the pod. |

Values:

```yaml
enabled: false
image: { repository: ghcr.io/tailscale/tailscale, tag: v1.98.9, pullPolicy: IfNotPresent }
hostname: ""      # required: tailnet device name
tag: ""           # required: tag advertised on join, e.g. tag:sandbox-gateway
authkey:
  secretStore: gcp-secretstore
  secretStoreKind: ClusterSecretStore
  remoteKey: ""   # required: GCP secret holding the OAuth client secret
target: ""        # required: host:port that TCP 443 forwards to
resources:
  requests: { cpu: 10m, memory: 64Mi }
  limits:   { cpu: 200m, memory: 256Mi }
```

`hostname`, `tag`, `authkey.remoteKey`, and `target` fail the render when empty.

### 3. Wiring

`values/deployments/base.yaml`:

```yaml
appRegistry:
  tailscale-proxy:
    key: tailscaleProxy
tailscaleProxy:
  enabled: false   # sandbox-only; the factory needs the key to exist
```

`values/deployments/mycure-sandbox.yaml`:

```yaml
global:
  gateway:
    name: nginx-sandbox-gateway   # namespace stays nginx-gateway-system
tailscaleProxy:
  enabled: true
  hostname: nginx-sandbox-gateway
  tag: tag:sandbox-gateway
  authkey:
    remoteKey: mycure-sandbox-tailscale-authkey
  target: nginx-sandbox-gateway-nginx.nginx-gateway-system.svc.cluster.local:443
```

Every sandbox chart resolves its HTTPRoute parent from `global.gateway`, so
the one-line override moves all routes. `strictGatewayIngress` keeps working:
the per-app NetworkPolicies allow ingress from the gateway *namespace*, and
the new gateway lives in the same one.

## Prerequisites (manual, new tailnet's admin console)

1. ACL: add `"tag:sandbox-gateway": ["autogroup:admin"]` to `tagOwners`, and a
   grant that lets sandbox users reach `tag:sandbox-gateway:443`.
2. OAuth client: scope `auth_keys` (write), tag `tag:sandbox-gateway`.
3. GCP Secret Manager (project `mc-v4-prod`): create
   `mycure-sandbox-tailscale-authkey` with value
   `tskey-client-…?ephemeral=false&preauthorized=true`. The vanaheim ESO
   service account already reads `mycure-sandbox-*` keys.

`ephemeral=false` is required: OAuth-derived keys default to ephemeral, and an
ephemeral device is deleted, and gets a new IP, on every pod restart.

## Rollout

Branch work happens on `feat/sandbox-tailnet` (worktree
`.claude/worktrees/feat-sandbox-tailnet`). Deploy by cherry-picking onto
`cluster/vanaheim`; promote with a PR to `main`. The touched files are
identical on both branches today.

1. **Commit A** — chart, registry, gateway split, overlay. Target annotation
   holds the current shared IP as a placeholder. After sync, read the new IP
   from `tailscale status` on any device on the new tailnet, or from the pod:
   `kubectl -n mycure-sandbox exec deploy/tailscale-proxy -- tailscale ip -4`.

   **Outage window.** From the moment A syncs until B syncs and DNS TTL
   expires, the sandbox is unreachable from everywhere: its listeners are gone
   from the shared gateway while `*.sandbox` DNS still points at the shared IP.
   Do not push A to `cluster/vanaheim` until the GCP secret exists, or the proxy
   pod sits in `CreateContainerConfigError` and the window stays open.
2. **Commit B** — set the `external-dns.alpha.kubernetes.io/target` annotation
   on `nginx-sandbox-gateway` to that IP. external-dns (`upsert-only`) updates
   the existing sandbox A records.
3. PR `feat/sandbox-tailnet` → `main`.

## Verification

- `helm template` of `charts/tailscale-proxy` with sandbox values renders and
  passes `mise run lint`. `helm template` of `charts/argocd-applications` with
  `base.yaml` + `mycure-sandbox.yaml` renders `mycure-sandbox-tailscale-proxy`
  and no new Application for staging, preprod, or production.
- On the cluster: `nginx-sandbox-gateway` is `Programmed`; the proxy pod is
  `Running` and `/healthz` returns 200; `tailscale status` in the pod shows the
  device logged in with `tag:sandbox-gateway`.
- From a device on the new tailnet:
  `curl -sI https://mycure.sandbox.localfirsthealth.com` returns 200.
- From a device on the MyCure tailnet: the same request fails to connect.
- `https://mycure.preprod.localfirsthealth.com` and the staging hosts still
  answer, and `nginx-staging-gateway-1` keeps `100.124.242.71`.

## Out of scope

- UDP on the sandbox gateway. Userspace serve forwards TCP only; the sandbox
  has no cadence QUIC legs, so nothing is lost.
- Direct WireGuard paths are best-effort (UDP 41641). DERP relays over TCP 443
  always work.
- The pre-existing `OutOfSync` state of the `tailscale-operator` Application.
- Any change to the DOKS production cluster.
