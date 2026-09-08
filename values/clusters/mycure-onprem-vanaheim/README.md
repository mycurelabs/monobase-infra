# mycure-onprem-vanaheim — on-prem k3d cluster (staging + preprod)

A local **k3d** cluster on the vanaheim workstation that hosts the **`mycure-staging`**
and **`mycure-preprod`** environments (preprod moved here from DOKS — PR #409
decommission, mycure#4135 standup), reachable **only over Tailscale**. It runs its
**own in-cluster ArgoCD** (standalone GitOps — not managed by the DOKS ArgoCD), so it
can be nuked and rebuilt independently without touching production.

```
values/clusters/mycure-onprem-vanaheim/
  terraform/   # provisioning: k3d cluster via the local-k3d module (tofu)
  argocd/      # this cluster's ArgoCD config: infra values, secrets registry,
               # argocd install values, bootstrap override
```

- **Cluster ≠ environment.** Cluster = `mycure-onprem-vanaheim`; app envs/namespaces =
  `mycure-staging` + `mycure-preprod`.
- **Footprint — staging:** lean — hapihub + frontends (mycure/dashboard/pxp) +
  HA Postgres + valkey + minio + mailpit. AI stack and cadence are OFF.
- **Footprint — preprod:** clone of `mycure-production` (HA Postgres + read plane,
  hapihub API/worker split, cadence hub + relay, HPA, prod image tags) with
  local-cluster deltas commented in the overlay. Prod-rehearsal + cadence
  box-testing hub.
- **Secrets:** each env's own GCP keys (`mycure-staging-*` / `mycure-preprod-*`,
  NOT prod's), read by the scoped `external-secrets-staging` SA (its IAM condition
  must cover both prefixes). **Google OAuth / Stripe / GCS storage are stubs** —
  those integrations don't function until real values are provided.

## Prerequisites (on the vanaheim host)

- `docker`, `k3d`, `tofu`, `kubectl`, `helm`, `bun`, `mise`, `gcloud` (authed to `mc-v4-prod`), `tailscale` (up).
- `gh` authed as **mycurebot** (repo scope) — used for ArgoCD's private-repo access.

## Provision the cluster

```bash
mise run cluster-plan  mycure-onprem-vanaheim     # review
mise run cluster-apply mycure-onprem-vanaheim     # creates k3d + Gateway API CRDs + node labels + CoreDNS AAAA fix
# context: k3d-mycure-onprem-vanaheim
```

The `local-k3d` module drives the `k3d` CLI (the `pvotal-tech/k3d` tofu provider is broken).
It bakes in: `node-pool=infra` node labels, the NGF **experimental** Gateway API CRD bundle
(v2.6.7), and CoreDNS AAAA suppression (host has no IPv6 egress → external Helm pulls hang otherwise).

## Bootstrap ArgoCD + deploy staging

ArgoCD needs a few one-time seeds that aren't yet automated in `bootstrap.ts`:

```bash
KCTX=k3d-mycure-onprem-vanaheim
kubectl --context $KCTX create ns argocd external-secrets-system tailscale

# 1. ESO auth: mint a key for the scoped SA -> gcpsm-secret (reads mycure-staging-* + tailscale/cloudflare tokens only)
gcloud iam service-accounts keys create /tmp/eso.json \
  --iam-account=external-secrets-staging@mc-v4-prod.iam.gserviceaccount.com --project=mc-v4-prod
kubectl --context $KCTX -n external-secrets-system create secret generic gcpsm-secret \
  --from-file=secret-access-credentials=/tmp/eso.json && rm -f /tmp/eso.json

# 2. Install ArgoCD (repo-server needs headroom for ESO CRD render)
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update argo
helm upgrade --install argocd argo/argo-cd --kube-context $KCTX -n argocd --version 9.0.3 --wait --timeout 8m
kubectl --context $KCTX -n argocd set env deploy/argocd-repo-server ARGOCD_EXEC_TIMEOUT=300s
kubectl --context $KCTX -n argocd set env statefulset/argocd-application-controller ARGOCD_REPO_SERVER_TIMEOUT_SECONDS=300
kubectl --context $KCTX -n argocd set resources deploy/argocd-repo-server --limits=cpu=1,memory=2Gi --requests=cpu=250m,memory=1Gi

# 3. ArgoCD private-repo creds (mycurebot token)
kubectl --context $KCTX -n argocd apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata: { name: repo-monobase-infra, namespace: argocd, labels: { argocd.argoproj.io/secret-type: repository } }
stringData: { type: git, url: https://github.com/mycurelabs/monobase-infra.git, username: mycurebot, password: $(gh auth token) }
EOF

# 4. Apply the bootstrap objects (infra root + auto-discover ApplicationSet, staging-only)
helm template argocd-bootstrap charts/argocd-bootstrap \
  -f values/clusters/mycure-onprem-vanaheim/argocd/bootstrap.yaml | kubectl --context $KCTX apply -f -
```

ArgoCD then deploys ESO → tailscale-operator → nginx-gateway → cert-manager → the
`mycure-staging` app stack. Watch: `kubectl --context $KCTX -n argocd get applications`.

## Cluster-tracking branch (IMPORTANT)

This is a **dev cluster**: it may run unmerged work. The convention
(docs/architecture/GITOPS-ARGOCD.md → "Branch Conventions") is **one ref for the whole
cluster**, declared in `argocd/bootstrap.yaml` as `argocd.targetRevision:
cluster/vanaheim` — never ad-hoc `kubectl` pins on individual Applications. Deploy =
merge your feature branch into `cluster/vanaheim`; promote = PR to `main`; re-merge
`main` into the cluster branch regularly. Merge-only, no force-push (shared branch).

**Current state (2026-09-08) predates the convention — two live ad-hoc pins:**

| Live object | pinned ref |
|---|---|
| `monobase-auto-discover` AppSet (→ `mycure-staging-root`) | `deploy/medley-2.x-staging` (medley 2.x test) |
| `infrastructure` root + standalone `mycure-preprod-root` | `feat/preprod-on-vanaheim` (infra PR #418) |

Consolidation into a single `cluster/vanaheim` branch is pending: create it from the
union of both branches, set `argocd.targetRevision` in `bootstrap.yaml` on it, re-apply
the bootstrap objects, delete the standalone `mycure-preprod-root` (the AppSet takes
ownership).

**Caveats while any pin exists:**

- **Re-applying the bootstrap objects clobbers ad-hoc pins** (resets AppSet +
  infra root to the rendered `targetRevision`). `kubectl diff` first, always.
- The standalone `mycure-preprod-root` (label `managed-by: manual-branch-pin`) is NOT
  AppSet-owned; it must be deleted (non-cascading) when the AppSet takes over.
- `main`-only infra changes do NOT reach this cluster until re-merged into the
  pinned ref(s).
- Preprod extras still gated on operator steps: ESO SA IAM condition needs the
  `mycure-preprod-` prefix; `*.preprod.localfirsthealth.com` A records → the gateway
  tailnet IP; after first DB boot: `mise run seed -- --env preprod` + re-mint
  `mycure-preprod-cadence-sa-api-key` (the stored key belongs to the old DOKS-era DB).

## Access (tailnet-only)

The `nginx-internal-gateway` is exposed on the tailnet by the tailscale operator as device
`nginx-staging-gateway` (a tailnet IP, e.g. `100.67.121.122`). DNS + TLS:

- **TLS:** real Let's Encrypt certs for `*.staging.` and `*.preprod.localfirsthealth.com`
  (+ exact-host certs for the mycure/hapihub anti-coalescing pairs) — cert-manager + Cloudflare DNS-01.
- **DNS: external-dns (v0.19, enabled 2026-09-08)** publishes every attached route's
  hostname as a **direct A record → the gateway's tailnet IP** (from the
  `external-dns.alpha.kubernetes.io/target` annotation on `nginx-internal-gateway`).
  Owner id is cluster-unique (`mycure-onprem-vanaheim`) so it can never touch the DOKS
  instance's records. Preprod records are external-dns-owned; the staging A records
  predate this and are still MANUAL/unowned (external-dns skips them) — migrate by
  deleting them once and letting external-dns recreate.

Reach it (with Tailscale up), always over **https://**:
- `https://mycure.staging.localfirsthealth.com` (login), `mycure-dashboard`, `mycure-pxp`
- `https://hapihub.staging.localfirsthealth.com/health`
- preprod: same hostnames under `.preprod.localfirsthealth.com` (+ `cadence`,
  `cadence-relay`, `mail`, `docs`, `minio`); cadence QUIC = UDP 6473, relay UDP 7842
  on the same gateway IP.

HTTP (port 80) has no app routes (deny-first) → nginx 404; use HTTPS.

If your client won't resolve it (some tailnets shadow the domain), add `/etc/hosts` entries
`<gateway-tailnet-ip> mycure.staging.localfirsthealth.com …`, or set a Tailscale admin
split-DNS for `localfirsthealth.com` → `1.1.1.1`.

## Nuke & rebuild

```bash
mise run cluster-destroy mycure-onprem-vanaheim   # or: k3d cluster delete mycure-onprem-vanaheim
```
Then re-provision + re-bootstrap. **The gateway's tailnet IP changes on rebuild** (it also
changes if the tailscale operator re-creates the proxy device — it did on 2026-09-03,
appending `-1` to the device name). Update the `external-dns.alpha.kubernetes.io/target`
annotation in `argocd/infrastructure.yaml` and `cadence.publicAddr` in
`values/deployments/mycure-preprod.yaml` to the new IP
(`tailscale status | grep nginx-staging-gateway`); external-dns then re-points all owned
A records automatically (manual/unowned records must be fixed by hand — or deleted once
so external-dns takes ownership).

## Known caveats / follow-ups

- **DNS is external-dns-managed** (the old "flaky CNAME to `.ts.net`" disable reason is
  obsolete — v0.19 honors the Gateway target annotation). Caveats that bit during
  enablement: the chart NetworkPolicy needed TCP 6443 egress (self-hosted apiserver
  port, post-DNAT); `txtOwnerId` must be cluster-unique or two sync-policy instances
  delete each other's records; office/LAN resolvers can cache stale records past
  deletion.
- **cert-manager/external-dns node image pulls are slow** (registry egress via a tailnet-routed
  mirror) — `docker pull` on the host + `k3d image import` if a rebuild stalls.
- **Stub integrations:** Google OAuth, Stripe, GCS storage — provide real staging values to
  enable those features.
- The ESO `gcpsm-secret`, ArgoCD repo-creds, repo-server tuning, and namespace pre-creation are
  still manual bootstrap steps (candidates to fold into `bootstrap.ts` / a `mise` task).
