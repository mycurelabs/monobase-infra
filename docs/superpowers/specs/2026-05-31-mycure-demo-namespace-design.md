# mycure-demo: low-traffic demo namespace + seed — Design

**Date:** 2026-05-31
**Repo:** `mycure-infra` (`git@github.com:mycurelabs/monobase-infra.git`)
**Author:** jofftiquez (with Claude)
**Status:** Draft — awaiting review

## 1. Goal

Stand up a new environment **`mycure-demo`**, a sibling of `mycure-preprod`, that runs **only** the three MyCure apps the user wants — `hapihub` (API), `mycure-dashboard` (admin UI), and `mycure` (the "mycureapp" patient/clinic web app, image `mycureapp`) — plus the minimum backing services those apps need to function. It is sized for **≤5 concurrent users**. After it is healthy, run the **mycure seed script** against it to populate demo data.

It lands on the **same DOKS cluster** as `mycure-preprod`/`mycure-production`, reached via the shared NGINX gateway on a new `*.demo.localfirsthealth.com` subdomain.

## 2. Decisions (locked during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Tenant / repo | `mycure-infra` | Only repo with a `preprod` sibling; ArgoCD on the mycure DOKS cluster reads from this repo. |
| Env name / namespace | `mycure-demo` (namespace + domain). NOTE: `global.environment` must be `staging` — chart schemas only allow development\|staging\|preprod\|production, so `demo` is rejected; it's just a label and the env identity comes from namespace/domain. | Matches `{client}-{environment}` convention for naming; `environment` label constrained by schema. |
| Database backend | **PostgreSQL only** | Lightest footprint; platform's forward direction. Mongo + migrator + cadence dropped. |
| Hostnames | New subdomain `*.demo.localfirsthealth.com` | Mirrors preprod's naming; wildcard TLS feasible via existing Cloudflare DNS-01 issuer. |
| Secrets / storage | **Approach C — hardened reuse** | Reuse `mycure-production-*` **ENC + JWT/auth keys** via `secretPrefix` (so crypto/login work out of the box), but route object storage to **in-cluster MinIO** and **omit the Stripe / Google-OAuth / GCP-storage** secret keys. No prod bucket writes, no prod Stripe calls. Residual linkage: the demo namespace holds copies of prod's encryption + token-signing keys (see §8). |
| Seed execution | **Run locally with `--api-url`** | `scripts/seed.ts` `--api-url` short-circuits its hardcoded env map (verified line 229); `CMS_URL` is cosmetic only. No code change. |

## 3. How it works (mechanics)

`mycure-infra` uses an **ApplicationSet auto-discovery** pattern (`argocd/bootstrap/applicationset-auto-discover.yaml`, git generator over `values/deployments/*.yaml`):

- Creating `values/deployments/mycure-demo.yaml` and pushing it causes ArgoCD to **auto-create** a `mycure-demo-root` Application — **no manual ArgoCD `Application` registration**.
- The namespace `mycure-demo` is created automatically (`CreateNamespace=true` + the `namespace.yaml` template, derived from `global.namespace`).
- Each component is gated by `<component>.enabled: true|false`; the app-of-apps templates wrap each spec in `{{- if .Values.<component>.enabled }}`.

## 4. Files to create / edit

### 4.1 CREATE `values/deployments/mycure-demo.yaml`

Cloned from `mycure-preprod.yaml`, then trimmed. Key contents:

**Globals**
```yaml
global:
  domain: demo.localfirsthealth.com
  namespace: mycure-demo
  environment: staging         # schema enum (development|staging|preprod|production); "demo" rejected — label only, identity is namespace/domain
  nodePool: "staging"          # same DOKS pool as preprod — see capacity caveat §10
  secretPrefix: "mycure-production"   # Approach C: provisions DB/valkey/minio secrets; hapihub reuses prod ENC/auth keys only
  gateway:
    name: nginx-shared-gateway
    namespace: nginx-gateway-system
  storage:
    provider: ""
    className: ""
```

**Component on/off matrix**

| Component | enabled | Why |
|---|---|---|
| `hapihub` | ✅ | Backend API (requested). |
| `mycure-dashboard` | ✅ | Admin UI = "dashboard" (requested). |
| `mycure` | ✅ | "mycureapp" patient/clinic web app (requested). |
| `postgresql` | ✅ | hapihub datastore (Postgres-only choice). |
| `valkey` | ✅ | hapihub cache — required for the API to run. |
| `mailpit` | ✅ | Email capture — keeps demo from sending real mail. |
| `minio` | ✅ | In-cluster object storage. With `minio.enabled: true` the hapihub chart auto-wires `STORAGE_*` to `minio.<ns>.svc:9000` and **skips the GCP-bucket block** — so demo uploads never touch the prod bucket. |
| `mongodb` | ❌ | Postgres-only. |
| `hapihubMigrator` | ❌ | Mongo→PG migrator; nothing to migrate. |
| `cadence` | ❌ | P2P sync; not needed for a demo. |
| `syncd` | ❌ | Real-time sync; not needed. |
| `mycure-pxp` | ❌ | A *different* patient app (image `pxp`); not requested. |
| `api`, `account`, `mycure-myaccount`, `mycurelocal`, `mycure-deploydash`, `hapihub-docs`, `dentalemon*`, `mycurev8` | ❌ | Out of scope. |
| `backup`, `resourceQuotas` | ❌ | YAGNI for a small demo. |
| `podSecurityStandards` | ✅ (`restricted`) | Keep platform security baseline. |

**Per-app config**
- `hapihub.gateway.hostnames: [hapihub.demo.localfirsthealth.com]`, `sectionName: https-demo-lfh`, `snippetsPolicy.enabled: false`.
- `hapihub.betterAuth.passkey`: `rpName: "Mycure (demo)"`, `rpId: "demo.localfirsthealth.com"`.
- `hapihub.config.CORS_ORIGINS`: `https://hapihub.demo.localfirsthealth.com,https://mycure-dashboard.demo.localfirsthealth.com,https://mycure.demo.localfirsthealth.com` (+ `CORS_STRICT: "true"`).
- `hapihub.config.ACCOUNTS_SERVICE_ACCOUNT_EMAILS: "service@mycure.md"` — required so the seed can elevate its service account (mirrors preprod; verify against the email the seed uses).
- `hapihub.externalSecrets`: **trimmed** vs preprod — keep only the keys hapihub actually needs to function on seeded data, all `remoteKey: mycure-production-*`:
  - Encryption: `ENC_BILLING_INVOICES`, `ENC_BILLING_ITEMS`, `ENC_BILLING_PAYMENTS`, `ENC_MEDICAL_RECORDS`, `ENC_PERSONAL_DETAILS`
  - Token/auth: `PRIVATE_KEY`, `PUBLIC_KEY`, `AUTH_SECRET`, `BETTER_AUTH_SECRET`
  - **Dropped:** `STRIPE_*` (disables Stripe), `STORAGE_*` (MinIO used instead), `GOOGLE_CLIENT_ID/SECRET` (email+password login path; re-add only if Google sign-in is wanted — it would auth against the prod OAuth app). All these env refs are `optional: true` in the chart (deployment.yaml:211–380), so omitting the keys is safe — hapihub starts without them.
- `hapihub.postgresql`: `enabled: true`, `external: false`, `serviceName: postgresql`, `auth.existingSecret: postgresql`.
- `minio` (NEW, mirror preprod's block, small): `enabled: true`, `fullnameOverride: "minio"`, `mode: standalone`, `statefulset.replicaCount: 1`, `auth.existingSecret: minio`, `defaultBuckets: "monobase-files"` (chart falls back to `hapihub-files` for the env if unset — keep `monobase-files` to match preprod), `gateway.enabled: false` (no public MinIO host needed for the demo). The hapihub chart reads the in-namespace `minio` secret (`root-user`/`root-password`) automatically.
- `mycure-dashboard.config.API_URL` and `mycure.config.{API_URL,HAPIHUB_URL}`: `https://hapihub.demo.localfirsthealth.com`; both `gateway.sectionName: https-demo-lfh`, `gateway.hostname: ""` (defaults to `<release>.demo.localfirsthealth.com`).

### 4.2 EDIT `values/infrastructure/main.yaml` (cluster-wide — additive)

Under `nginxGatewayResources.gateway.listeners`, add (mirroring the preprod pair):
```yaml
- name: https-demo-lfh
  port: 443
  protocol: HTTPS
  hostname: "*.demo.localfirsthealth.com"
  tlsSecretName: nginx-gateway-tls-demo
- name: http-demo-lfh
  port: 80
  protocol: HTTP
  hostname: "*.demo.localfirsthealth.com"
```
Under `nginxGatewayResources.tls.certificates`, add:
```yaml
- secretName: nginx-gateway-tls-demo
  clusterIssuer: letsencrypt-mycure-cloudflare-prod   # DNS-01 wildcard
  dnsNames:
    - "*.demo.localfirsthealth.com"
```
The `letsencrypt-mycure-cloudflare-prod` issuer already lists the `localfirsthealth.com` Cloudflare zone, so the wildcard cert is issuable exactly as preprod's is. **externalDNS** (Cloudflare, enabled) auto-creates the per-host DNS records from the HTTPRoutes.

## 5. Resource sizing (≤5 users)

| Component | replicas | requests | limits | storage |
|---|---|---|---|---|
| hapihub | 1 | 300m / 768Mi | 1500m / 1.5Gi | — |
| mycure-dashboard | 1 | 25m / 48Mi | 150m / 128Mi | — |
| mycure | 1 | 25m / 48Mi | 150m / 128Mi | — |
| postgresql (standalone) | 1 | 250m / 512Mi | 1000m / 1.5Gi | 20Gi |
| valkey (standalone) | 1 | 50m / 256Mi | 250m / 512Mi | 2Gi |
| minio (standalone) | 1 | 100m / 256Mi | 500m / 512Mi | 5Gi |
| mailpit | 1 | 25m / 32Mi | 100m / 64Mi | — |

Autoscaling **off**, PodDisruptionBudgets **off** for all. (hapihub keeps headroom because the seed run does real bulk writes.) Rough footprint: **~0.8 vCPU / ~2.5Gi** requested, well under one node.

## 6. Networking / DNS / TLS

- Shared `nginx-shared-gateway` in `nginx-gateway-system`, new `https-demo-lfh` listener.
- Wildcard cert `nginx-gateway-tls-demo` for `*.demo.localfirsthealth.com` via Cloudflare DNS-01.
- Hosts: `hapihub.demo`, `mycure-dashboard.demo`, `mycure.demo` `.localfirsthealth.com` (DNS auto-managed by externalDNS).

## 7. Seed plan

**Prerequisites (in order):**
1. `mycure-demo` deployed and **healthy** (hapihub `Running`/ready, external-secrets synced, Postgres up).
2. `https://hapihub.demo.localfirsthealth.com` resolving with a valid cert (DNS + cert-manager done).
3. Local toolchain: `mise install` (provides `bun`); run from repo root.
4. hapihub pod has `ACCOUNTS_SERVICE_ACCOUNT_EMAILS` set (from §4.1) — verify: `kubectl -n mycure-demo exec deploy/hapihub -- printenv ACCOUNTS_SERVICE_ACCOUNT_EMAILS`.

**Command (local, against the public endpoint):**
```bash
bun scripts/seed.ts --api-url https://hapihub.demo.localfirsthealth.com
# re-run / wipe-and-reseed:
bun scripts/seed.ts --api-url https://hapihub.demo.localfirsthealth.com --reset
```
Defaults seed 7 role users (password `Mycure123!`), 3 demo facilities, system fixtures, LIS/RIS/EMR/PME templates, inventory, partners, ~25 patients + a fixed demo patient, and 5 patient accounts. Flags `--patients N` / `--patient-accounts N` tune volume.

> Note: with `--api-url`, the script's "Login at:" line prints `(custom)` — cosmetic only; the real UI is `https://mycure.demo.localfirsthealth.com` (mycureapp) / `https://mycure-dashboard.demo.localfirsthealth.com`.

## 8. Does it touch prod? (Approach C blast-radius)

**Production data: never touched.** Separate namespace, separate Postgres pod + PVC, hapihub connects to the in-namespace `postgresql` service (`external: false`). The seed writes only to the demo DB. Prod's DB is never read, written, or deleted.

**Prod services: not touched under Approach C.**
- **Storage → in-cluster MinIO.** `minio.enabled: true` makes the chart point `STORAGE_*` at `minio.mycure-demo.svc:9000`; the GCP-bucket env block is skipped. **No writes to the prod bucket.** (This also corrects an earlier assumption — preprod has `minio.enabled: true` too, so preprod likewise uses in-cluster MinIO, not the prod bucket.)
- **Stripe: disabled.** `STRIPE_*` keys omitted; the chart's refs are `optional: true`, so no Stripe client is configured → no prod Stripe calls.
- **Google OAuth: omitted** (email+password login). No handshake against the prod OAuth app unless re-added.
- **Email → mailpit.** No real outbound mail.

**Residual prod linkage (the cost of reuse, accept or mitigate):**
- **Shared signing/encryption keys.** The demo reuses prod `PRIVATE_KEY`/`PUBLIC_KEY`/`AUTH_SECRET`/`BETTER_AUTH_SECRET` and `ENC_*`. These are **read-only** copies that live in the demo namespace and only ever encrypt/sign the demo's own data — they grant **no access to prod data**. The real risk is **trust-domain**: a token signed with these keys is cryptographically valid in prod, so a compromise of the demo namespace could be leveraged to forge prod sessions. For a ≤5-user internal demo this is usually acceptable; **the clean fix is Approach A (fresh `mycure-demo-*` keys)**. **Decision (2026-05-31): key reuse accepted** for this small internal demo; revisit if it gains untrusted users or a longer lifespan.
- **Fresh Postgres with reused password secret** is internally consistent (the new PVC initialises with the password from the `postgresql` secret; hapihub reads the same secret). No access to prod data — separate pod/PVC/namespace.
- **Shared cluster + ArgoCD.** Demo pods run on the same DOKS cluster (the `staging` node pool), with small limits.
- **One additive shared-infra edit.** `values/infrastructure/main.yaml` gains a `*.demo.localfirsthealth.com` listener + cert on the shared gateway that also serves prod hosts. Additive and low-risk, but `helm template` + review it before sync since prod routing rides the same gateway.

## 9. Rollout & verification

1. `mise run lint` / `mise run validate` on the new + edited files.
2. `helm template` the app-of-apps with `mycure-demo.yaml` to dry-run-render (sanity check enabled set + hosts).
3. Commit on a branch (conventional commit), open PR. Two logical changes: (a) `values/deployments/mycure-demo.yaml`, (b) `values/infrastructure/main.yaml` gateway/TLS.
4. After merge/push: ArgoCD auto-discovers `mycure-demo-root`; infra root picks up the new listener/cert. Watch sync + health (Health > Sync rule).
5. Verify: namespace exists; the 3 app pods + postgres/valkey/mailpit `Running`; ExternalSecret synced; cert `Ready`; the three hosts serve HTTPS.
6. Run the seed (§7); confirm login to dashboard/mycureapp with a seed user.

## 10. Open assumptions to confirm in the plan

- **Node-pool capacity:** demo schedules on the `staging` pool alongside preprod/prod — confirm headroom (~0.8 vCPU / 2.5Gi requested).
- **Seed service-account email:** assumes `service@mycure.md` matches what `seed.ts` elevates — verify in the script before the seed run.
- **GitOps rollout vs. dry-run-first:** assumes normal merge→auto-sync. If the user wants a manual `helm template`/staged sync gate before ArgoCD touches the cluster, note it.

## 11. Out of scope (YAGNI)

Mongo/migrator/cadence/syncd, backups, resource quotas, autoscaling, a dedicated in-cluster seed Job, fresh isolated GCP secrets (Approach A — the alternative if shared signing keys are a concern, see §8), and any new node pool.
