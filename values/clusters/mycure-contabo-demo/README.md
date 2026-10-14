# mycure-contabo-demo — public k3d cluster (mycure-demo)

A **k3d** cluster on the demo **Contabo** VPS (`vmi3315250`, public IP `62.146.233.59`) that hosts
the **`mycure-demo`** environment: a client-facing demo / sales / training copy of
MyCure, reachable from the **public internet** at `*.demo.localfirsthealth.com`. It
runs its **own in-cluster ArgoCD** (standalone, like vanaheim), tracking **`main`**
(see "Git ref" below — it is long-lived, so no `cluster/<name>` branch).

```
values/clusters/mycure-contabo-demo/
  terraform/   # k3d cluster via the local-k3d module (tofu, local state)
  argocd/      # this cluster's ArgoCD config: infra values, secrets registry,
               # argocd install values, bootstrap override
```

- **Cluster ≠ environment.** Cluster = `mycure-contabo-demo`; env/namespace = `mycure-demo`
  (`values/deployments/mycure-demo.yaml`).
- **Footprint:** full prod shape like preprod — HA Postgres + read replica, hapihub
  API/worker split, least-privilege DB roles, HPA, cadence hub + relay, MinIO, mailpit,
  frontends (mycure, dashboard, pxp, mycurelocal, myaccount, docs, developer-portal).
  Prod image tags. Medical AI, tenzir, Loki, monitoring, velero are OFF.
- **Data:** SYNTHETIC ONLY, seeded fresh. This cluster is on the internet — never load
  prod data here.
- **Secrets:** the env's own `mycure-demo-*` GCP keys, read by the scoped
  `external-secrets-demo` SA. **Google OAuth and Stripe are stubs.**
- **Long-lived:** PV data lives under `/var/lib/k3d/mycure-contabo-demo` (persistent), not
  `/tmp`, so a **reboot** keeps the database. A cluster **recreate** does NOT — see
  "Nuke & rebuild".

## Traffic path (and what it costs)

```
client ──TCP 80/443, UDP 6472/7842──▶ VPS (docker-published ports)
       ──▶ k3d loadbalancer container (nginx stream proxy)
       ──▶ k3s servicelb on each node ──▶ nginx-public-gateway data plane ──▶ apps
```

- **Client source IPs are lost** at the k3d loadbalancer (no PROXY protocol). Every
  request looks like it comes from a docker-bridge IP, so better-auth's rate limit is
  effectively one shared bucket for all demo users. Fine for a handful of people.
  Raise `BETTER_AUTH_RATE_LIMIT_MAX` in the overlay if a group session trips it.
- The gateway Service uses `externalTrafficPolicy: Cluster` for the same reason.
- **This host filters Docker traffic with ufw ("ufw-docker" rules in
  `/etc/ufw/after.rules`).** Its `DOCKER-USER` chain drops new inbound TCP and
  UDP (ports 0-32767) to containers unless allowed — so on THIS VPS, plain Docker
  publishing is NOT enough. 80/443/6472/7842 are opened with `ufw route allow`
  (Prerequisites). Symptom when missing: everything works from the VPS itself
  (local/private sources are exempt) but times out from the internet.
- The **Kubernetes API is bound to `127.0.0.1:6445`** (`api_port`), never public.

## Prerequisites (on the VPS)

- `docker` (user in the `docker` group), `mise` (provides `k3d`, `kubectl`, `helm`,
  `tofu`, `bun` from the repo's `mise.toml`): `curl https://mise.run | sh && mise install`.
- Host ports **80, 443 (TCP)** and **6472, 7842 (UDP)** free. Check:
  `ss -tlnup | grep -E ':(80|443|6472|7842) '`.
- Those ports **allowed through ufw to Docker** (one-time, needs sudo; `ufw route`
  rules land in `ufw-user-forward`, which `DOCKER-USER` checks before its drop). The
  k3d loadbalancer listens on the same port numbers inside its container, so these
  match:

  ```bash
  sudo ufw route allow proto tcp from any to any port 80
  sudo ufw route allow proto tcp from any to any port 443
  sudo ufw route allow proto udp from any to any port 6472
  sudo ufw route allow proto udp from any to any port 7842
  ```

  Verify from OUTSIDE the VPS (a check from the VPS itself always passes), e.g.
  `curl -sI https://mycure.demo.localfirsthealth.com` from your laptop. Any
  provider-side firewall (Contabo panel) must allow the same ports.
- A workstation with `gcloud` authed to `mc-v4-prod` (IAM + Secret Manager steps).

## 1. GCP: scoped ESO service account + demo secrets (workstation)

```bash
P=mc-v4-prod
PN=$(gcloud projects describe $P --format='value(projectNumber)')

# Scoped SA: reads ONLY mycure-demo-* + the shared Cloudflare token.
gcloud iam service-accounts create external-secrets-demo --project=$P \
  --display-name="ESO (mycure-contabo-demo)"
gcloud projects add-iam-policy-binding $P \
  --member="serviceAccount:external-secrets-demo@$P.iam.gserviceaccount.com" \
  --role=roles/secretmanager.secretAccessor \
  --condition="title=mycure-demo-only,expression=resource.name.startsWith(\"projects/$PN/secrets/mycure-demo-\") || resource.name.startsWith(\"projects/$PN/secrets/infrastructure-cloudflare-api-token\")"
# Compare with the existing staging SA's binding if anything differs:
#   gcloud projects get-iam-policy $P --flatten=bindings --filter='bindings.members:external-secrets-staging' --format=json

put() { printf '%s' "$2" | gcloud secrets create "mycure-demo-$1" --project=$P --data-file=- \
        || printf '%s' "$2" | gcloud secrets versions add "mycure-demo-$1" --project=$P --data-file=-; }

# DB/cache/storage — HEX ONLY (DATABASE_URI does no urlencoding).
for k in postgresql-password postgresql-replication-password valkey-password \
         postgresql-migrator-password postgresql-app-rw-password postgresql-cadence-password; do
  put $k "$(openssl rand -hex 24)"
done
put minio-root-user     "demo$(openssl rand -hex 6)"
put minio-root-password "$(openssl rand -hex 24)"

# Auth
put auth-secret        "$(openssl rand -base64 48)"
put better-auth-secret "$(openssl rand -base64 48)"

# PRIVATE_KEY — must be an ECDSA P-256 (ES256) PKCS#8 PEM: hapihub's config schema
# ("ECDSA private key for JWT signing") and generateJWKS() import it as ES256, so an
# RSA key makes /.well-known/jwks.json 500 ("Data provided to an operation does not
# meet requirements"). Single-line \n-escaped is fine (hapihub un-escapes). Do NOT
# copy another env's key TYPE without checking — sandbox's is RSA and has this bug.
put private-key "$(openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2>/dev/null | awk '{printf "%s\\n",$0}')"

# cadence OAuth AS signing key — EdDSA PEM, SINGLE-LINE \n-escaped (hapihub un-escapes).
put cadence-issuer-key-pem "$(openssl genpkey -algorithm ed25519 | awk '{printf "%s\\n",$0}')"

# Stubs (integrations off until real demo values exist)
put google-oauth-client-id     stub
put google-oauth-client-secret stub
put stripe-checkout-success-url https://mycure.demo.localfirsthealth.com/
put stripe-checkout-cancel-url  https://mycure.demo.localfirsthealth.com/
put cadence-sa-api-key          placeholder   # real value minted after the seed (step 5)

# SA key for the cluster (copy to the VPS, then delete)
gcloud iam service-accounts keys create /tmp/eso-demo.json \
  --iam-account=external-secrets-demo@$P.iam.gserviceaccount.com --project=$P
```

## 2. Provision the cluster (VPS)

```bash
mise run cluster-init  mycure-contabo-demo
mise run cluster-plan  mycure-contabo-demo     # review: 3 to add
mise run cluster-apply mycure-contabo-demo     # k3d + Gateway API CRDs + node labels + CoreDNS AAAA fix
# context: k3d-mycure-contabo-demo   (API at https://127.0.0.1:6445)
```

## 3. Bootstrap ArgoCD (VPS)

Run from a checkout of **`main`** on the VPS. Two one-time seeds come first; then
`mise run bootstrap` does the rest (ArgoCD install with `argocd/argocd.yaml`, which
already carries the repo-server timeouts/resources, plus the infra root and the
auto-discover ApplicationSet from `argocd/bootstrap.yaml`).

```bash
KCTX=k3d-mycure-contabo-demo

# 1. ESO auth: the scoped SA key from step 1 -> gcpsm-secret (bootstrap.ts does
#    not create it; ESO, cert-manager and external-dns all depend on it).
kubectl --context $KCTX create ns external-secrets-system
kubectl --context $KCTX -n external-secrets-system create secret generic gcpsm-secret \
  --from-file=secret-access-credentials=/tmp/eso-demo.json && shred -u /tmp/eso-demo.json

# 2. Install ArgoCD + bootstrap. bootstrap.ts uses the CURRENT context (it ignores
#    --context) and defaults --cluster-name to mycure-doks-main (PRODUCTION) —
#    so switch context first and ALWAYS pass --cluster-name.
#    --skip-github-app: monobase-infra is public; ArgoCD reads it anonymously.
kubectl config use-context $KCTX
mise run bootstrap -- --cluster-name mycure-contabo-demo --skip-github-app
```

Repo credentials are not needed (public repo). Add a repository Secret only if
GitHub rate-limits the repo-server.

ArgoCD then deploys ESO → cert-manager → nginx-gateway → external-dns → the
`mycure-demo` stack. Watch: `kubectl --context $KCTX -n argocd get applications`.

## 4. Verify the public path

```bash
kubectl --context $KCTX get certificate -A                 # all Ready
dig +short mycure.demo.localfirsthealth.com                # 62.146.233.59
curl -sI https://mycure.demo.localfirsthealth.com | head -1
curl -s  https://hapihub.demo.localfirsthealth.com/health
curl -sI https://mail.demo.localfirsthealth.com            # must NOT serve mailpit (no route)
```

## 5. Seed + cadence key

```bash
# The seed has no default password: --password is required. Choose one when
# you run it; read it silently so it stays out of shell history.
read -rs SEED_PASSWORD
mise run seed -- --app mycure --env demo --password "$SEED_PASSWORD"
# Mint the cadence service-account API key into mycure-demo-cadence-sa-api-key
# (needs gcloud ADC; run where gcloud is available, pointing at the demo API):
mise run seed -- --app mycure --env demo --password "$SEED_PASSWORD" \
  --provision-cadence-key --gcp-project mc-v4-prod

# cadence-secrets refreshes only hourly: force ESO to re-read the new key now.
kubectl --context $KCTX -n mycure-demo annotate externalsecret cadence-secrets \
  force-sync=$(date +%s) --overwrite

# Wait (max 5 min) until the Secret holds a REAL key — not missing, not the
# placeholder — and only then restart cadence. On timeout nothing restarts.
deadline=$((SECONDS + 300)); ok=
while [ "$SECONDS" -lt "$deadline" ]; do
  v=$(kubectl --context $KCTX -n mycure-demo get secret cadence-secrets \
        -o jsonpath='{.data.sa-api-key}' 2>/dev/null | base64 -d)
  if [ -n "$v" ] && [ "$v" != placeholder ]; then ok=1; break; fi
  sleep 5
done
if [ -n "$ok" ]; then
  kubectl --context $KCTX -n mycure-demo rollout restart deploy/cadence
else
  echo "cadence-secrets never picked up the minted key within 5 min." >&2
  echo "Check the mint step's output and: kubectl --context $KCTX -n mycure-demo describe externalsecret cadence-secrets" >&2
fi
unset v ok deadline SEED_PASSWORD
```

Demo users log in at `https://mycure.demo.localfirsthealth.com` and
`https://mycure-dashboard.demo.localfirsthealth.com` with the seeded accounts and the
password given at seed time. A reseed (`--reset`) must pass that same password.

## Hostnames

Every host is named after its product: `<app>.demo.localfirsthealth.com`.

| Host | Serves |
|---|---|
| `mycure.demo` | MyCure clinic app (login) |
| `hapihub.demo` | HapiHub API |
| `hapihub-docs.demo` | API docs |
| `mycure-dashboard.demo` | Admin dashboard |
| `mycure-pxp.demo` | Patient app |
| `mycurelocal.demo` | MyCure Local |
| `mycure-myaccount.demo` | Account portal |
| `mycure-developer-portal.demo` | Developer portal |
| `mycure-cadence.demo` | Cadence sync hub, **the EasyJoey anchor** (+ QUIC on UDP 6472) |
| `mycure-cadence-relay.demo` | Cadence relay (+ QUIC on UDP 7842) |
| `easyjoey.demo` | EasyJoey web app |
| `easyjoey-website.demo` | EasyJoey marketing website |
| `easyjoey-accounts.demo` | EasyJoey accounts (sign-up / sign-in) |

## EasyJoey

The demo also runs EasyJoey, set up the same way as staging (owner decision 2026-10-12):

- **hapihub runs the EasyJoey build,** `11.20.135-easyjoey.0-staging.cb7e137` (feat/easyjoey).
  Plain prod tags lack EasyJoey; don't move to one while EasyJoey runs here.
- **The single cadence hub is the EasyJoey anchor** (`easyjoey/1`, fleet `easyjoey-demo`,
  client `easyjoey-native`, `requireEntitlement: easyjoey.cloud`). It no longer serves MyCure
  boxes. One cadence engine per hapihub DB, so there is no second hub.
- **Three static frontends** on the hosts above, built for the demo (URLs are baked in).

### One-time database prerequisite

This DB was created by prod `11.20.135`. Its `0112_add_clock_correction_requests`
(2026-10-05) sits above EasyJoey's migrations 0112–0119 (2026-10-04), so Drizzle and
hapihub's history reconciler would leave those 8 **blocked** (logged as errors, exit 0) and
EasyJoey would run on a half-migrated schema. Before hapihub moves to the EasyJoey build,
an operator runs the back-fill (it also tags the cadence key, see below):

```bash
eval "$(~/.local/bin/mise env -s bash)"
SUP=$(kubectl --context k3d-mycure-contabo-demo -n mycure-demo get secret postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)
kubectl --context k3d-mycure-contabo-demo -n mycure-demo exec -i postgresql-primary-0 -c postgresql -- \
  env PGPASSWORD="$SUP" psql -h 127.0.0.1 -U postgres -d hapihub -v ON_ERROR_STOP=1 --single-transaction -f - \
  < ~/backups/mycure-demo/easyjoey-demo-db-changes.sql
unset SUP
```

The script (on the VPS, `~/backups/mycure-demo/`) was tested on a restored copy of this DB:
without it the EasyJoey migrate reports the 8 blocked; with it 0120–0123 apply with zero
errors and hapihub boots as `app_rw`. A full backup taken before it sits next to it.

### Cadence: follow mode and the trusted key

- **Follow mode** enrolls every EasyJoey-realm clinic hapihub lists, and re-enrolls when one
  is added or removed. Until the first EasyJoey clinic exists (sign up at
  `easyjoey-accounts.demo`), the hub logs `no easyjoey-native clinics yet; waiting` and the
  30-minute startup probe restarts it. That is expected.
- **The `sa-api-key` must be a trusted service key:** `api_key.metadata` =
  `{"serviceAccount":true}` (hapihub `auth/authorizer.ts`). A key minted by
  `scripts/seed.ts --provision-cadence-key` is **not** tagged. Re-tag after every re-mint
  (PART 2 of the script above, with the new key id).

### Frontend images (local, not in ghcr.io)

`easyjoey:0.2.0-demo.102d596`, `easyjoey-website:0.1.0-demo.102d596` and
`easyjoey-accounts:0.1.0-demo.102d596` were built **on the VPS** and loaded into the nodes
(`k3d image import`). The release workflow only builds on `feat/easyjoey` with staging URLs.
After a cluster rebuild, rebuild and re-import them:

```bash
# monobase-mycure at 102d596 (the web build staging validated with hapihub cb7e137), in
# ~/workspace/easyjoey-demo-build/monobase-mycure, plus apps/*/deploy/demo.env:
bun install --frozen-lockfile
for a in easyjoey-website lf-accounts easyjoey; do (cd apps/$a && DEPLOY_ENV=demo ./build-docker.sh); done
k3d image import -c mycure-contabo-demo \
  ghcr.io/mycurelabs/easyjoey:0.2.0-demo.102d596 \
  ghcr.io/mycurelabs/easyjoey-website:0.1.0-demo.102d596 \
  ghcr.io/mycurelabs/easyjoey-accounts:0.1.0-demo.102d596
```

`demo.env` = the app's `staging.env` with `.staging.` replaced by `.demo.` (public URLs
only).

### Stubbed until real values exist

- **Stripe:** the existing `mycure-demo-stripe-*` placeholders. Checkout won't work.
- **Backups (#4956):** no `BACKUPS_*` or master key, so the backup endpoints answer 503.
  Needs a `mycure-demo-easyjoey-backups-master-key` secret and a public MinIO route.
- **Google sign-in:** placeholder, as for MyCure.

## Internal UIs (no public routes)

The mailpit UI has no auth and the MinIO console is admin-only, so neither is routed.

```bash
kubectl --context $KCTX -n mycure-demo port-forward svc/mailpit-http 8025:80   # http://localhost:8025
kubectl --context $KCTX -n mycure-demo port-forward svc/minio 9001:9001       # MinIO console, http://localhost:9001
```

## Git ref: `main`

This cluster tracks **`main` (HEAD)**, the chart default — `argocd/bootstrap.yaml`
deliberately sets no `argocd.targetRevision`. Rule (docs/architecture/GITOPS-ARGOCD.md
→ "Branch Conventions"): **long-lived clusters track `main`; `cluster/<name>` branches
are throwaway refs for disposable dev clusters only.** The demo serves clients, so it is
long-lived.

- **Deploy** = PR to `main` and merge. That is the only thing that changes the demo.
- **App versions** are pinned in `values/deployments/mycure-demo.yaml`; bump them there
  (a prod bump in `mycure-production.yaml` does not move the demo).
- `charts/argocd-bootstrap` and `argocd/bootstrap.yaml` changes only apply on
  re-bootstrap (step 3), not on merge.

## Nuke & rebuild

```bash
mise run cluster-destroy mycure-contabo-demo
sudo rm -rf /var/lib/k3d/mycure-contabo-demo    # reclaim disk: the old volumes are orphaned anyway
```

**A recreate is a data reset.** k3s local-path names each volume directory
`pvc-<UID>_<namespace>_<pvc>`. A new cluster creates new PVCs with new UIDs, so Postgres,
MinIO and Valkey start on new, empty directories; the old ones stay on disk, orphaned
(recoverable only by hand). Then re-provision + re-bootstrap (steps 2-3) from a checkout of
`main`, reseed and re-mint the cadence key (step 5) — better-auth keys die with the DB.

If the VPS IP ever changes, update `external-dns.alpha.kubernetes.io/target` in
`argocd/infrastructure.yaml` and `cadence.publicAddr` in
`values/deployments/mycure-demo.yaml`. external-dns is `upsert-only` on the shared
prod zone, so stale records must be removed by hand in Cloudflare.

## Known caveats / follow-ups

- **Changing ports, storage_path, api_port, k3s_version or node counts recreates the
  cluster** (k3d can't change them live) — and a recreate is a data reset (see "Nuke &
  rebuild"). Fine for synthetic demo data; pin static PVs first if that ever changes.
- **Cadence QUIC through the k3d loadbalancer is unproven** — UDP is proxied by k3d's
  nginx stream proxy. Validate a box enroll + sync; if sessions drop, check the proxy's
  UDP timeouts.
- **Stub integrations:** Google OAuth, Stripe.
- The ESO `gcpsm-secret`, ArgoCD repo creds, repo-server tuning and namespace
  pre-creation are still manual (same as vanaheim).
