# mycure-onprem-vanaheim — on-prem k3d staging cluster

A local **k3d** cluster on the vanaheim workstation that hosts the **`mycure-staging`**
environment, reachable **only over Tailscale**. It runs its **own in-cluster ArgoCD**
(standalone GitOps — not managed by the DOKS ArgoCD), so it can be nuked and rebuilt
independently without touching production.

```
values/clusters/mycure-onprem-vanaheim/
  terraform/   # provisioning: k3d cluster via the local-k3d module (tofu)
  argocd/      # this cluster's ArgoCD config: infra values, secrets registry,
               # argocd install values, bootstrap override
```

- **Cluster ≠ environment.** Cluster = `mycure-onprem-vanaheim`; app env/namespace = `mycure-staging`.
- **Footprint:** lean clone of preprod — hapihub + frontends (mycure/dashboard/pxp) +
  standalone Postgres + valkey + minio + mailpit. AI stack, cadence, and HA Postgres are OFF.
- **Secrets:** its own `mycure-staging-*` GCP secrets (NOT prod's). Internal ones are
  generated; **Google OAuth / Stripe / GCS storage are stubs** — those integrations don't
  function until real staging values are provided.

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

> Pre-merge testing: add `argocd.targetRevision: <branch>` to `bootstrap.yaml` so ArgoCD
> pulls staging from the feature branch. Revert to HEAD after merge.

## Access (tailnet-only)

The `nginx-internal-gateway` is exposed on the tailnet by the tailscale operator as device
`nginx-staging-gateway` (a tailnet IP, e.g. `100.67.121.122`). DNS + TLS:

- **TLS:** real Let's Encrypt wildcard cert for `*.staging.localfirsthealth.com` (cert-manager + Cloudflare DNS-01).
- **DNS:** `*.staging.localfirsthealth.com` **A records → the gateway's tailnet IP**, in Cloudflare.

Reach it (with Tailscale up), always over **https://**:
- `https://mycure.staging.localfirsthealth.com` (login), `mycure-dashboard`, `mycure-pxp`
- `https://hapihub.staging.localfirsthealth.com/health`

HTTP (port 80) has no app routes (deny-first) → nginx 404; use HTTPS.

If your client won't resolve it (some tailnets shadow the domain), add `/etc/hosts` entries
`<gateway-tailnet-ip> mycure.staging.localfirsthealth.com …`, or set a Tailscale admin
split-DNS for `localfirsthealth.com` → `1.1.1.1`.

## Nuke & rebuild

```bash
mise run cluster-destroy mycure-onprem-vanaheim   # or: k3d cluster delete mycure-onprem-vanaheim
```
Then re-provision + re-bootstrap. **The gateway's tailnet IP changes on rebuild** — update
the A records in Cloudflare and the `external-dns.alpha.kubernetes.io/target` annotation in
`argocd/infrastructure.yaml` to the new IP (`tailscale status | grep nginx-staging-gateway`).

## Known caveats / follow-ups

- **DNS is manual A records** (external-dns disabled here — with the tailscale-operator gateway
  it emits a flaky CNAME to the `.ts.net` status address). Re-add A records after a rebuild.
- **cert-manager/external-dns node image pulls are slow** (registry egress via a tailnet-routed
  mirror) — `docker pull` on the host + `k3d image import` if a rebuild stalls.
- **Stub integrations:** Google OAuth, Stripe, GCS storage — provide real staging values to
  enable those features.
- The ESO `gcpsm-secret`, ArgoCD repo-creds, repo-server tuning, and namespace pre-creation are
  still manual bootstrap steps (candidates to fold into `bootstrap.ts` / a `mise` task).
