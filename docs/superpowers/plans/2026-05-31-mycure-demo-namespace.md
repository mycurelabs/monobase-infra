# mycure-demo Namespace + Seed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `mycure-demo`, a sibling of `mycure-preprod` on the same DOKS cluster, running only hapihub + mycure-dashboard + mycure (mycureapp) plus their minimum backing services, then seed it with demo data.

**Architecture:** GitOps via ArgoCD ApplicationSet auto-discovery. A new `values/deployments/mycure-demo.yaml` is auto-discovered into a `mycure-demo-root` Application; an additive gateway listener + wildcard TLS cert in `values/infrastructure/main.yaml` serves `*.demo.localfirsthealth.com`. Storage is in-cluster MinIO (no prod bucket); Stripe/OAuth omitted; ENC/auth keys reused from prod via `secretPrefix`. The seed runs locally against the public hapihub URL.

**Tech Stack:** Helm, ArgoCD, Gateway API (NGINX Gateway Fabric), External Secrets Operator (GCP), Bun (seed), mise (task runner).

**Spec:** `docs/superpowers/specs/2026-05-31-mycure-demo-namespace-design.md`

**Branch:** `feat/mycure-demo-namespace` (already created; the design spec is committed there).

**Note on testing:** Infra changes have no unit tests; the repo's verification path is `mise run check` (lint + validate) + `helm template` dry-render + post-deploy `kubectl`/ArgoCD checks. We use those as the "tests" in each task. No new Helm unit tests are added (YAGNI — they're chart-level, not per-deployment).

---

### Task 1: Create the deployment values file

**Files:**
- Create: `values/deployments/mycure-demo.yaml`

- [ ] **Step 1: Write `values/deployments/mycure-demo.yaml`**

```yaml
# MyCure Demo Configuration
# Low-traffic demo environment (<=5 users), sibling of mycure-preprod on the
# same DOKS cluster. Runs ONLY the three MyCure apps + their minimum backing
# services: hapihub (API), mycure-dashboard (admin UI), mycure (mycureapp).
# Postgres-only. Object storage is in-cluster MinIO (uploads never touch the
# prod bucket). Stripe and Google OAuth are omitted; email is captured by
# mailpit. ENC/auth keys are REUSED from mycure-production via secretPrefix
# (accepted trade-off — see
# docs/superpowers/specs/2026-05-31-mycure-demo-namespace-design.md §8).
# Tear down with `kubectl delete ns mycure-demo`.

global:
  domain: demo.localfirsthealth.com
  namespace: mycure-demo
  # Chart schemas restrict environment to development|staging|preprod|production ("demo" rejected); label only.
  environment: staging
  nodePool: "staging"
  secretPrefix: "mycure-production"   # provisions DB/valkey/minio secrets; hapihub reuses prod ENC/auth keys only
  gateway:
    name: nginx-shared-gateway
    namespace: nginx-gateway-system
  storage:
    provider: ""
    className: ""

# ===== HEALTHCARE: HapiHub API =====
hapihub:
  enabled: true
  image:
    repository: ghcr.io/mycurelabs/hapihub
    tag: "11.16.0"
    pullPolicy: IfNotPresent
  replicaCount: 1
  resources:
    requests:
      cpu: 300m
      memory: 768Mi
    limits:
      cpu: "1500m"
      memory: 1536Mi
  gateway:
    hostnames:
      - hapihub.demo.localfirsthealth.com
    sectionName: https-demo-lfh
    snippetsPolicy:
      enabled: false
  betterAuth:
    passkey:
      rpName: "Mycure (demo)"
      rpId: "demo.localfirsthealth.com"
  config:
    CORS_ORIGINS: "https://hapihub.demo.localfirsthealth.com,https://mycure-dashboard.demo.localfirsthealth.com,https://mycure.demo.localfirsthealth.com"
    CORS_STRICT: "true"
    CORS_ALLOW_LOCAL_NETWORK: "false"
    CORS_ALLOW_MOBILE_APPS: "true"
    ACCOUNTS_SERVICE_ACCOUNT_EMAILS: "service@mycure.md"
  env:
    - name: BETTER_AUTH_RATE_LIMIT_ENABLED
      value: "true"
    - name: BETTER_AUTH_RATE_LIMIT_WINDOW
      value: "60"
    - name: BETTER_AUTH_RATE_LIMIT_MAX
      value: "300"
    - name: BETTER_AUTH_SESSION_COOKIE_CACHE_ENABLED
      value: "false"
  livenessProbe:
    enabled: true
  readinessProbe:
    enabled: true
  podDisruptionBudget:
    enabled: false
  autoscaling:
    enabled: false
  # Reuse ONLY the prod encryption + token-signing keys (Approach C). No
  # STORAGE_* (MinIO is used instead), no STRIPE_* (Stripe disabled), no
  # GOOGLE_* (email+password login). All these chart env refs are
  # optional:true, so omitting the keys is safe.
  externalSecrets:
    enabled: true
    secretStore: gcp-secretstore
    secretStoreKind: ClusterSecretStore
    refreshInterval: 1h
    secrets:
      - secretKey: ENC_BILLING_INVOICES
        remoteKey: mycure-production-enc-billing-invoices
      - secretKey: ENC_BILLING_ITEMS
        remoteKey: mycure-production-enc-billing-items
      - secretKey: ENC_BILLING_PAYMENTS
        remoteKey: mycure-production-enc-billing-payments
      - secretKey: ENC_MEDICAL_RECORDS
        remoteKey: mycure-production-enc-medical-records
      - secretKey: ENC_PERSONAL_DETAILS
        remoteKey: mycure-production-enc-personal-details
      - secretKey: PRIVATE_KEY
        remoteKey: mycure-production-private-key
      - secretKey: PUBLIC_KEY
        remoteKey: mycure-production-public-key
      - secretKey: AUTH_SECRET
        remoteKey: mycure-production-auth-secret
      - secretKey: BETTER_AUTH_SECRET
        remoteKey: mycure-production-better-auth-secret
  postgresql:
    enabled: true
    external: false
    serviceName: postgresql
    auth:
      database: hapihub
      username: postgres
      existingSecret: postgresql

# ===== HEALTHCARE: MyCure Dashboard (operator/admin web UI) =====
mycure-dashboard:
  enabled: true
  image:
    repository: ghcr.io/mycurelabs/dashboard
    tag: "0.13.0"
    pullPolicy: IfNotPresent
  replicaCount: 1
  resources:
    requests:
      cpu: 25m
      memory: 48Mi
    limits:
      cpu: 150m
      memory: 128Mi
  gateway:
    hostname: ""   # defaults to mycure-dashboard.demo.localfirsthealth.com
    sectionName: https-demo-lfh
  config:
    API_URL: "https://hapihub.demo.localfirsthealth.com"
  podDisruptionBudget:
    enabled: false

# ===== HEALTHCARE: Frontend Application (mycureapp) =====
mycure:
  enabled: true
  image:
    repository: ghcr.io/mycurelabs/mycureapp
    tag: "10.18.0"
    pullPolicy: IfNotPresent
  replicaCount: 1
  resources:
    requests:
      cpu: 25m
      memory: 48Mi
    limits:
      cpu: 150m
      memory: 128Mi
  gateway:
    hostname: ""   # defaults to mycure.demo.localfirsthealth.com
    sectionName: https-demo-lfh
  config:
    API_URL: "https://hapihub.demo.localfirsthealth.com"
    HAPIHUB_URL: "https://hapihub.demo.localfirsthealth.com"
  podDisruptionBudget:
    enabled: false

# ===== DATABASE: PostgreSQL (standalone) =====
postgresql:
  enabled: true
  fullnameOverride: "postgresql"
  architecture: standalone
  image:
    repository: bitnamilegacy/postgresql
    tag: 16.4.0-debian-12-r13
  auth:
    enabled: true
    database: hapihub
    username: postgres
    existingSecret: postgresql
    secretKeys:
      adminPasswordKey: postgres-password
  primary:
    persistence:
      enabled: true
      storageClass: ""
      size: 20Gi
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1536Mi
  podDisruptionBudget:
    enabled: false

# ===== CACHE: Valkey (Redis) =====
valkey:
  enabled: true
  global:
    security:
      allowInsecureImages: true
  auth:
    existingSecret: valkey
  architecture: standalone
  image:
    repository: bitnamilegacy/valkey
    tag: 8.0.1-debian-12-r2
  master:
    persistence:
      enabled: true
      storageClass: ""
      size: 2Gi
    resources:
      requests:
        cpu: 50m
        memory: 256Mi
      limits:
        cpu: 250m
        memory: 512Mi

# ===== STORAGE: MinIO Object Storage (in-cluster; keeps uploads off prod) =====
minio:
  enabled: true
  fullnameOverride: "minio"
  image:
    repository: bitnamilegacy/minio
    tag: "2025.7.23-debian-12-r3"
  mode: standalone
  statefulset:
    replicaCount: 1
  auth:
    existingSecret: minio
  persistence:
    enabled: true
    storageClass: ""
    size: 5Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  defaultBuckets: "monobase-files"
  buckets:
    - name: "monobase-files"
  region: "us-east-1"
  podSecurityContext:
    enabled: true
    fsGroup: 1001
    fsGroupChangePolicy: "OnRootMismatch"
  containerSecurityContext:
    enabled: true
    runAsUser: 1001
    runAsGroup: 1001
    runAsNonRoot: true
    privileged: false
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    seccompProfile:
      type: RuntimeDefault
  # No public MinIO host needed: hapihub reaches MinIO via the in-cluster
  # service (minio.mycure-demo.svc:9000). NOTE: the chart sets
  # STORAGE_PUBLIC_ENDPOINT to that internal URL, so browser-side presigned
  # upload/download is not reachable from outside — same as preprod. Out of
  # scope here; expose MinIO publicly later if interactive uploads are needed.
  gateway:
    enabled: false

# ===== EMAIL TESTING: Mailpit (captures all outbound mail) =====
mailpit:
  enabled: true
  resources:
    requests:
      cpu: 25m
      memory: 32Mi
    limits:
      cpu: 100m
      memory: 64Mi
  gateway:
    enabled: true
    hostname: "mail.demo.localfirsthealth.com"

# ===== DISABLED COMPONENTS (enabled:false stubs required by app-of-apps templates) =====
api:
  enabled: false
account:
  enabled: false
mycure-pxp:
  enabled: false
mycurelocal:
  enabled: false
mycure-myaccount:
  enabled: false
dentalemon-myaccount:
  enabled: false
mycure-deploydash:
  enabled: false
hapihub-docs:
  enabled: false
dentalemon-website:
  enabled: false
dentalemon:
  enabled: false
syncd:
  enabled: false
mycurev8:
  enabled: false
mongodb:
  enabled: false
cadence:
  enabled: false
hapihubMigrator:
  enabled: false
backup:
  enabled: false

# ===== SECURITY =====
podSecurityStandards:
  enabled: true
  level: restricted

# ===== RESOURCE QUOTAS =====
resourceQuotas:
  enabled: false
```

- [ ] **Step 2: Lint YAML**

Run: `mise run lint-yaml`
Expected: PASS (no errors for `values/deployments/mycure-demo.yaml`).

- [ ] **Step 3: Validate Helm rendering across deployments**

Run: `mise run validate-helm`
Expected: PASS — the new deployment file renders without template errors. If it fails with a nil-pointer on a component key, add that component as an `enabled: false` stub (the disabled-components block already lists every component present in `mycure-preprod.yaml`).

- [ ] **Step 4: Dry-render the app-of-apps and confirm only the intended components are enabled**

Run:
```bash
helm template mycure-demo argocd/applications \
  -f values/deployments/mycure-demo.yaml \
  --set argocd.repoURL=https://github.com/mycurelabs/monobase-infra.git \
  --set argocd.targetRevision=main \
  | grep -E '^kind:|name: mycure-demo|app.kubernetes.io/name:' | sort -u
```
Expected: ArgoCD `Application` resources render for **hapihub, mycure-dashboard, mycure, postgresql, valkey, minio, mailpit** (plus the namespace and the secrets/externalsecret wave), and **none** for mongodb / cadence / syncd / hapihubMigrator / mycure-pxp / api / account / dentalemon* / mycurev8. If a disabled component still renders, set its `enabled: false` explicitly.

- [ ] **Step 5: Commit**

```bash
git add values/deployments/mycure-demo.yaml
git commit -m "feat: add mycure-demo deployment values (hapihub + dashboard + mycureapp)

New low-traffic demo env (<=5 users), sibling of mycure-preprod. Postgres-only,
in-cluster MinIO storage, Stripe/OAuth omitted, mailpit for email. Reuses prod
ENC/auth keys via secretPrefix. Hosts on *.demo.localfirsthealth.com.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add the gateway listener + wildcard TLS cert

**Files:**
- Modify: `values/infrastructure/main.yaml` (under `nginxGatewayResources.gateway.listeners` and `nginxGatewayResources.tls.certificates`)

- [ ] **Step 1: Add the `*.demo.localfirsthealth.com` listeners**

Find this block (the preprod listener pair) and append the demo pair after it.

Old:
```yaml
      # Preprod localfirsthealth.com (ephemeral prod-mirror env)
      - name: https-preprod-lfh
        port: 443
        protocol: HTTPS
        hostname: "*.preprod.localfirsthealth.com"
        tlsSecretName: nginx-gateway-tls-preprod
      - name: http-preprod-lfh
        port: 80
        protocol: HTTP
        hostname: "*.preprod.localfirsthealth.com"
```
New:
```yaml
      # Preprod localfirsthealth.com (ephemeral prod-mirror env)
      - name: https-preprod-lfh
        port: 443
        protocol: HTTPS
        hostname: "*.preprod.localfirsthealth.com"
        tlsSecretName: nginx-gateway-tls-preprod
      - name: http-preprod-lfh
        port: 80
        protocol: HTTP
        hostname: "*.preprod.localfirsthealth.com"
      # Demo localfirsthealth.com (low-traffic demo env, sibling of preprod)
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

- [ ] **Step 2: Add the wildcard certificate for the demo subdomain**

Find the preprod certificate entry and append the demo cert after it.

Old:
```yaml
      - secretName: nginx-gateway-tls-preprod
        clusterIssuer: letsencrypt-mycure-cloudflare-prod  # DNS-01, wildcard
        dnsNames:
          - "*.preprod.localfirsthealth.com"
```
New:
```yaml
      - secretName: nginx-gateway-tls-preprod
        clusterIssuer: letsencrypt-mycure-cloudflare-prod  # DNS-01, wildcard
        dnsNames:
          - "*.preprod.localfirsthealth.com"
      - secretName: nginx-gateway-tls-demo
        clusterIssuer: letsencrypt-mycure-cloudflare-prod  # DNS-01, wildcard
        dnsNames:
          - "*.demo.localfirsthealth.com"
```

- [ ] **Step 3: Validate the infrastructure template**

Run: `mise run validate-template && mise run validate-helm`
Expected: PASS — no hardcoded-value violations, infra chart renders.

- [ ] **Step 4: Dry-render the gateway + cert and confirm the demo entries appear**

Run:
```bash
helm template monobase-infra argocd/infrastructure \
  -f values/infrastructure/main.yaml \
  | grep -nE 'https-demo-lfh|http-demo-lfh|nginx-gateway-tls-demo|\*\.demo\.localfirsthealth\.com'
```
Expected: matches for both listeners (`https-demo-lfh`, `http-demo-lfh`), the `Certificate`/secret `nginx-gateway-tls-demo`, and the `*.demo.localfirsthealth.com` hostname/dnsName. Existing preprod/prod listeners must still be present (run without the grep to eyeball).

- [ ] **Step 5: Commit**

```bash
git add values/infrastructure/main.yaml
git commit -m "feat: add *.demo.localfirsthealth.com gateway listener and TLS cert

Additive listener pair (https-demo-lfh/http-demo-lfh) on nginx-shared-gateway
plus a wildcard cert (nginx-gateway-tls-demo) via the Cloudflare DNS-01 issuer,
for the new mycure-demo environment.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Roll out via GitOps and verify the environment is healthy

> **Cluster access:** use the repo's `/k8s` and `/argocd` skills to resolve the correct kubeconfig/context for the mycure DOKS cluster before running `kubectl`. Do NOT `kubectl apply` directly — ArgoCD owns these resources.

**Files:** none (operational)

- [ ] **Step 1: Push the branch and open a PR**

```bash
git push -u origin feat/mycure-demo-namespace
gh pr create --fill --title "feat: mycure-demo namespace + seed" \
  --body "New low-traffic demo env (hapihub + dashboard + mycureapp). See docs/superpowers/specs/2026-05-31-mycure-demo-namespace-design.md"
```

- [ ] **Step 2: Confirm which revision the ApplicationSet tracks**

Run:
```bash
kubectl -n argocd get applicationset monobase-auto-discover \
  -o jsonpath='{.spec.generators[*].git.revision}{"\n"}'
```
Expected: a branch (likely `main` / `HEAD`). The `mycure-demo-root` Application will only be created **after the PR is merged** to that revision. Merge the PR before continuing.

- [ ] **Step 3: After merge, confirm the root Application was auto-created**

Run: `kubectl -n argocd get applications | grep mycure-demo`
Expected: `mycure-demo-root` (and child apps) appear. Trigger a refresh if needed via the `/argocd` skill (hard-refresh the parent; see the ArgoCD app-of-apps resync note).

- [ ] **Step 4: Verify sync + health (Health > Sync rule)**

Run: `kubectl -n argocd get applications | grep mycure-demo`
Expected: each app `Synced` / `Healthy`. Investigate any `Degraded`/`OutOfSync` with the `/argocd` skill before proceeding.

- [ ] **Step 5: Verify the workload pods are running**

Run: `kubectl -n mycure-demo get pods`
Expected: `Running`/`Ready` pods for hapihub, mycure-dashboard, mycure, postgresql, valkey, minio, mailpit. No mongodb/cadence/syncd/migrator pods.

- [ ] **Step 6: Verify secrets synced and the cert is ready**

Run:
```bash
kubectl -n mycure-demo get externalsecret,secret | grep -E 'hapihub|postgresql|valkey|minio'
kubectl get certificate -A | grep nginx-gateway-tls-demo
```
Expected: the hapihub external secret is `SecretSynced`; the `postgresql`/`valkey`/`minio` secrets exist; the `nginx-gateway-tls-demo` certificate is `Ready=True`.

- [ ] **Step 7: Verify hapihub has the service-account env (needed by the seed)**

Run: `kubectl -n mycure-demo exec deploy/hapihub -- printenv ACCOUNTS_SERVICE_ACCOUNT_EMAILS`
Expected: `service@mycure.md`.

- [ ] **Step 8: Verify external reachability over HTTPS**

Run:
```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://hapihub.demo.localfirsthealth.com/health || true
curl -sS -o /dev/null -w '%{http_code}\n' https://mycure-dashboard.demo.localfirsthealth.com/
curl -sS -o /dev/null -w '%{http_code}\n' https://mycure.demo.localfirsthealth.com/
```
Expected: TLS handshake succeeds (valid cert) and each host returns a non-5xx status (hapihub health 200; frontends 200). If DNS doesn't resolve yet, wait for external-dns to publish the records (created from the HTTPRoutes), then retry.

---

### Task 4: Seed demo data

> Run from the repo root on your workstation. Requires the env to be healthy and `https://hapihub.demo.localfirsthealth.com` reachable (Task 3).

**Files:** none (uses `scripts/seed.ts` unchanged)

- [ ] **Step 1: Ensure the local toolchain (Bun) is installed**

Run: `mise install`
Expected: bun available — verify `bun --version`.

- [ ] **Step 2: Confirm the seed flags**

Run: `bun scripts/seed.ts --help`
Expected: usage shows `--api-url` (Override API URL, skips env lookup), `--reset`, `--patients`, `--patient-accounts`.

- [ ] **Step 3: Run the seed against the demo API**

Run:
```bash
mise run seed -- --api-url https://hapihub.demo.localfirsthealth.com
```
Expected: progress through the seed steps (7 users, 3 facilities, fixtures, LIS/RIS/EMR/PME templates, inventory, partners, ~25 patients + fixed demo patient, 5 patient accounts) and a final summary line `Login at: (custom)` (cosmetic — the real UI is `https://mycure.demo.localfirsthealth.com` / `https://mycure-dashboard.demo.localfirsthealth.com`). Re-running is safe; add `--reset` to wipe and re-seed.

- [ ] **Step 4: Verify the seed landed (log in)**

Open `https://mycure-dashboard.demo.localfirsthealth.com` and sign in with `superadmin@mycure.test` / `Mycure123!`.
Expected: login succeeds and the demo org "MyCure Demo Clinic" with seeded data is visible. (No commit — this task changes data, not the repo.)

---

## Self-Review

**1. Spec coverage:**
- §3/§4.1 new values file → Task 1 ✅
- §4.2 gateway listener + cert → Task 2 ✅
- §4.1 component matrix (3 apps + pg/valkey/minio/mailpit on, rest off) → Task 1 file + Step 4 dry-render ✅
- §4.1 trimmed externalSecrets (ENC + auth only) → Task 1 file ✅
- §5 sizing → Task 1 file ✅
- §6 networking/DNS/TLS → Task 2 + Task 3 Steps 6,8 ✅
- §7 seed plan → Task 4 ✅
- §8 isolation (MinIO storage, no Stripe/OAuth) → Task 1 file + comments ✅
- §9 rollout/verify → Task 3 ✅
- §10 open assumptions (node-pool headroom Task 3 Step 5; seed SA email Task 3 Step 7; rollout-vs-dry-run handled via PR/merge gate) ✅

**2. Placeholder scan:** No TBD/TODO; every step has the real file content or exact command + expected output.

**3. Type/name consistency:** Hostnames (`hapihub|mycure-dashboard|mycure.demo.localfirsthealth.com`), `sectionName: https-demo-lfh`, secret name `nginx-gateway-tls-demo`, namespace `mycure-demo`, and the seed URL match across Tasks 1–4 and the spec.
