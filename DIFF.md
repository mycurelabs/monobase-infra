# Staging vs Production: Drift Tracker

> **Last updated**: 2026-04-06
> **Snapshot source**: `values/deployments/mycure-{staging,production}.yaml` + live cluster state
>
> Items are ordered from **least impact** (top, safest) to **greatest impact** (bottom, riskiest).
> Work top-down. Tick boxes as items are resolved.

---

## TL;DR

Staging is running the **HapiHub 11.x stack** (better-auth + PostgreSQL + Valkey + Cadence) while production is still on the **HapiHub 10.x stack** (legacy MongoDB-only). The full migration is at the **bottom** of this list. Many smaller items can be resolved independently first.

## Status Legend

- [ ] open
- [x] resolved
- [~] in-progress / partial
- [!] blocked

---

# 🟢 TIER 1 — Trivial / No Risk

Cosmetic, parity, and "obvious" cherry-picks. No migration, no downtime, no schema changes.

## 1.1 Reverse-port mycurelocal `1.4.0` to staging

Production is **ahead** of staging on this app, so staging needs to catch up for parity testing.

- [x] Bump `mycurelocal.image.tag` to `1.4.0` in `values/deployments/mycure-staging.yaml`
- [ ] Optionally also add a staging equivalent for `find.mycure.md` (e.g., `find.stg.localfirsthealth.com`) so the hostname routing pattern is exercised in staging — moved to Tier 3.1

## 1.2 Frontend version cherry-picks (staging → production)

Bump production tags to match staging. These are forward-only, low-risk.

- [x] `mycure` v10: `10.3.9` → `10.3.47`
- [x] `mycurev8`: `8.24.5` → `8.24.6`
- [x] `mycure-myaccount`: `1.0.0` → `1.0.1`

## 1.3 Document MYCURE_X_URL parity

The `MYCURE_X_URL` env var was added to both env files on 2026-04-06 (`mycure.localfirsthealth.com` for prod, `mycure.stg.localfirsthealth.com` for staging). Already in sync — verify no further action needed.

- [x] Confirm production mycurev8 pod has `MYCURE_X_URL` env var set after next reconcile (verified post-rollout)

## 1.4 Per-env config values

- [x] `ACCOUNTS_SERVICE_ACCOUNT_EMAILS` — different value per env (not a test fixture)
  - staging: `service@test.com`
  - production: `service@mycure.md` (added 2026-04-06, commit `33d7f33`)

---

# 🟢 TIER 2 — Cleanup / Decisions Only

Resolves operational noise. No deploys, no config changes — just decisions or cosmetic fixes.

## 2.1 Silence stale ExternalSecret warnings in production

Currently throwing `UpdateFailed` events because secrets don't exist (valkey + minio are disabled in prod):
- `valkey-credentials` → `mycure-production-valkey-password`
- `minio-credentials` → `mycure-production-minio-root-user` + `mycure-production-minio-root-password`

- [x] Created proper GCP secrets (2026-04-06): `mycure-production-valkey-password` (random 30 chars), `mycure-production-minio-root-user` (`minioadmin`), `mycure-production-minio-root-password` (random 40 chars). Forward-looking — these will be reused when valkey/minio are enabled in Tier 4.
- [x] All 6 production ExternalSecrets now report `SecretSynced`

## 2.2 Disabled apps in production — confirmed intentional

Confirmed 2026-04-06 by user: all of these are intentionally disabled in production. No action required, but kept here for awareness.

- [x] `dentalemon` — intentionally disabled in prod
- [x] `dentalemon-website` — intentionally disabled in prod
- [x] `dentalemon-myaccount` — intentionally disabled in prod
- [x] `hapihub-docs` — enabled in prod 2026-04-06 at `docs.localfirsthealth.com`
- [x] `mailpit` — intentionally disabled in prod (replaced by real SMTP)
- [x] `minio` — intentionally disabled in prod (uses GCS via `STORAGE_*` secrets)

## 2.3 HapiHub config knobs — resolved

- [x] `CLUSTER_INSTANCES: max` — removed from staging (2026-04-06); will not propagate to prod
- [x] `BETTER_AUTH_SESSION_COOKIE_CACHE_ENABLED: false` — added to staging (2026-04-06) to mirror prod
- [x] `ACCOUNTS_SERVICE_ACCOUNT_EMAILS` — added to prod as `service@mycure.md` on 2026-04-06 (commit `33d7f33`)

---

# 🟡 TIER 3 — Operational Improvements

Affects production but no schema/architecture changes. Work needed but well-scoped.

## 3.1 Long-term mycurelocal hostname strategy — SKIPPED

- [x] **Skipped per user (2026-04-06)**: prod-only multi-hostname routing for now. Staging will not mirror `find.mycure.md`.

## 3.2 `sync-logs` collection runaway growth — SKIPPED

- [x] **Skipped per user (2026-04-06)**: this collection will be migrated to the new PG-based system in Tier 5. No point in TTL/archival work on a collection that's about to be retired.

## 3.3 MongoDB production resource review — SKIPPED

- [x] **Skipped per user (2026-04-06)**: MongoDB will be migrated out as part of Tier 5 (HapiHub 11.x → PostgreSQL). The current 3/6Gi limits are sufficient until then.

## 3.4 Production node pool capacity

**Current state (2026-04-06):**
- 4 nodes × `s-4vcpu-8gb` = **16 vCPU / 32 GB total**
- Per-node memory requests: 38% / 79% / 9% / 40% (one node at ~80%)
- Per-node memory limits: 79% / 165% / 5% / 135% (overcommitted)
- Per-node CPU requests: 71% / 45% / 13% / 72%
- Per-node CPU limits: 128% / 128% / 0% / 159% (overcommitted)

**Recommended for Tier 4 (PG + Valkey + Cadence + 11.x hapihub HPA 3-5):**
- Estimated additional load: ~2 vCPU + ~6 GB requests
- **Option A**: Add 1-2 more `s-4vcpu-8gb` nodes (cheap, simple) → 5-6 nodes × 4/8 = 20-24 vCPU / 40-48 GB
- **Option B**: Resize to `s-4vcpu-16gb` (8 GB → 16 GB per node, double memory) → 16 vCPU / 64 GB. Better for memory-heavy services like Postgres, Valkey, MongoDB (until migrated).
- **Option C**: Migrate to `g-2vcpu-8gb` (general-purpose, dedicated CPU) for predictable performance
- **Recommended**: **Option B (resize to 16GB nodes)** — handles memory pressure, costs roughly 2x the memory tier, no node count increase, and gives MongoDB headroom during the 11.x migration window.

- [x] **Decided 2026-04-06: Option B** — resize to `s-4vcpu-16gb` nodes when Tier 4 begins. Doubles memory headroom without increasing node count, handles MongoDB pressure during the 11.x migration window.
- [ ] Plan resize maintenance window when Tier 4 work begins (DOKS pool resize is rolling — drain one node at a time)

## 3.5 syncd replica strategy

- [x] Production syncd reduced to `replicaCount: 1`, autoscaling `min=1, max=2` (2026-04-06)
  - was: `replicaCount: 5`, autoscaling `max=5` — was contributing to MongoDB load
  - Lower cap reduces sync-logs query pressure until syncd is migrated/retired in Tier 5/6

---

# 🟠 TIER 4 — Infrastructure Prep for 11.x

These prepare production to RECEIVE the new stack, but don't change hapihub yet. Reversible if needed.

## 4.1 Create production GCP secrets for 11.x stack — DONE

All 5 secrets verified in `mc-v4-prod` GCP Secret Manager (2026-04-06):

- [x] `mycure-production-auth-secret` — created (64-char base64 random)
- [x] `mycure-production-better-auth-secret` — created (64-char base64 random)
- [x] `mycure-production-postgresql-password` — already existed (2025-11-19)
- [x] `mycure-production-valkey-password` — created during Tier 2.1 (2026-04-06)
- [x] `mycure-production-private-key` — already exists (2025-11-22)
  - ⚠️ **Format check**: production key is `BEGIN EC PRIVATE KEY` (SEC1), staging key is `BEGIN PRIVATE KEY` (PKCS#8). Same EC key type, different wrapper. Verify hapihub 11.x accepts SEC1 — if not, convert via `openssl pkcs8 -topk8 -nocrypt -in old.pem -out new.pem` before migration cutover (Tier 5).

## 4.2 Provision PostgreSQL in production — DONE

Deployed 2026-04-06 in `mycure-production` namespace using Bitnami PG chart in **replication mode**:

- [x] **Decided**: in-cluster Bitnami PG with `architecture: replication` (1 primary + 1 read replica, manual failover)
- [x] **Sized**: 200 GiB PVC per replica, 500m/4Gi req → 2000m/8Gi limit per pod (sized for migrated 11.x dataset of ~35 GB useful from MongoDB + 18mo growth headroom)
- [x] Created `mycure-production-postgresql-replication-password` GCP secret
- [x] Created matching `mycure-staging-postgresql-replication-password` GCP secret (so the existing staging app keeps working)
- [x] Updated `charts/database-secrets/templates/postgresql-externalsecret.yaml` to sync both `postgres-password` and `postgres-replication-password`
- [x] Extended `argocd/applications/templates/postgresql.yaml` to support `primary.*` / `readReplicas.*` blocks (backward-compat with staging legacy values)
- [x] Added `postgresql:` block to `values/deployments/mycure-production.yaml` with `architecture: replication`, primary + readReplicas, PDB minAvailable: 1
- [x] Added `ServerSideApply=true` to the postgresql ArgoCD app sync options
- [x] **Verified**:
  - `postgresql-primary-0` 1/1 Running, `pg_is_in_recovery: f`, version PG 16.4
  - `postgresql-read-0` 1/1 Running, `pg_is_in_recovery: t`, replaying WAL
  - `pg_stat_replication` shows `streaming` / `async` / no lag
  - `hapihub` database created
  - Both PVCs bound at 200 GiB on `do-block-storage`
  - Cluster autoscaler added a 4th production node (`production-0w8sg`) automatically to fit the read replica
  - ExternalSecret `postgresql-credentials` reports `SecretSynced` with both keys
- [x] Cleaned up orphan `data-postgresql-0` PVC (8 GiB, from previous abandoned deployment)

### 4.2.1 PostgreSQL backups (deferred)

Not blocking 11.x rollout (no production PG data yet), but **must be in place before** Tier 5 cutover so the HapiHub 10→11 data migration is recoverable.

Recommended approach: **both** layers, defense-in-depth.

- [ ] **Velero schedule** for `mycure-production` namespace
  - Weekly full + daily incremental of all resources + PVC snapshots
  - Target: existing Velero backup location (verify it's configured)
  - Pros: fast restore (PVC-level), crash-consistent (PG handles replay on startup)
  - Cons: not portable across PG versions
- [ ] **Nightly `pg_dump` CronJob** → GCS bucket
  - Runs from inside the cluster as a Kubernetes CronJob using `bitnamilegacy/postgresql` image
  - Auth via `postgresql` secret + GCP service account for GCS write
  - Logical dump (`pg_dump -Fc -f /backup/hapihub-$(date).dump`) — portable across PG versions
  - Retention: 30 days hot in GCS, lifecycle rule moves to coldline after 7d
  - Reuses pattern from existing GCS storage secrets (`mycure-production-storage-*`)
- [ ] Document restore procedure (both Velero and `pg_restore` paths) in a runbook
- [ ] Test restore once into a staging-like namespace before relying on it

**Owner**: should be in place before Tier 5.4 (HapiHub 10→11 cutover).

### 4.2.2 PostgreSQL auto-failover (future upgrade path)

Current setup is **manual failover** — if `postgresql-primary-0` fails, the read replica continues serving reads but writes are down until an operator runs `pg_promote` (or deletes the primary StatefulSet pod and lets Kubernetes reschedule it on a healthy node).

Acceptable for the initial 11.x rollout. Upgrade path documented here for when downtime budget tightens.

Two options:

- [ ] **Option A** — switch to `bitnami/postgresql-ha` chart
  - Bundles repmgr (auto-failover) + pgpool (connection routing) + PgBouncer
  - Requires migrating data from `bitnami/postgresql` to `bitnami/postgresql-ha` (different chart, different StatefulSet names)
  - Migration via `pg_dump`/`pg_restore` during a maintenance window
  - More moving parts (4 components vs 1), more complex troubleshooting
- [ ] **Option B** — add Patroni operator separately (e.g., Zalando postgres-operator or Crunchy PGO)
  - Operators handle failover, backup, scaling, connection pooling
  - More invasive change; new CRDs, new mental model
  - Better long-term option if PG footprint grows beyond a single primary+replica
- [ ] **Option C** — accept manual failover and just document the runbook
  - Cheapest, no infra change
  - Operator drill: `kubectl exec postgresql-read-0 -- pg_ctl promote` then update `postgresql-primary` Service selector to point at the promoted pod
  - Requires monitoring/alerting on primary health (Prometheus + Alertmanager)

**Recommended**: stay on **Option C** until Tier 5 ships and we have real production load metrics. Revisit if SLO incidents occur.

- [ ] Decide between A/B/C **after** Tier 5 (HapiHub 11.x is stable in prod)
- [ ] Until then: ensure monitoring alerts fire when `postgresql-primary` becomes unreachable
- [ ] Write a manual-failover runbook (even Option C needs documented steps)

## 4.3 Enable Valkey in production — DONE

Deployed 2026-04-06 in `mycure-production`.

- [x] Set `valkey.enabled: true` in `mycure-production.yaml`
- [x] Auth wired to `existingSecret: valkey` (synced from GCP via tier 2.1)
- [x] Resource sizing inherited from staging: 100m/1Gi req → 500m/2Gi limit (per 2026-04-06 OOM lessons)
- [x] `primary.resourcesPreset: none` chart fix in place
- [x] `ServerSideApply=true` in valkey ArgoCD app template
- [x] **Fixed**: valkey ArgoCD app template was missing `nodeSelector` + `tolerations` injection from `global.nodePool`. Without it, the pod couldn't schedule onto production-pool nodes (which have the `node-pool=production` taint). Patched in `argocd/applications/templates/valkey.yaml`.
- [x] **Verified**: `valkey-primary-0` 1/1 Running on `production-03hu4`, ArgoCD app `Synced Healthy`

## 4.4 Enable Cadence in production — DONE

Deployed 2026-04-06 in `mycure-production`.

- [x] Added `cadence:` block to `mycure-production.yaml` (mirrors staging structure)
- [x] Image `0.4.0` (pullPolicy: Always), resources 200m/1Gi req → 2/4Gi limit
- [x] Points at PG primary service: `postgresql-primary` (the new HA primary from tier 4.2)
- [x] Points at valkey: `valkey-primary`
- [x] Gateway/HTTPRoute on `cadence.localfirsthealth.com` via `https-lfh` listener
- [x] Scope rules + explicit `accounts`/`personal_details` collections inherited from chart values
- [x] NetworkPolicies (`allow-gateway-to-cadence`, `allow-cadence-to-valkey`, `allow-cadence-egress`) deployed via security-baseline chart
- [x] **Fixed**: Production PG password originally had `/`, `=`, and trailing `\n` characters (created 2025-11-19 with a non-URL-safe random). Cadence builds the connection URL via `${POSTGRESQL_PASSWORD}` substitution in `--primary-db`, which fails URL parsing on those characters. Replaced with a 48-char hex (URL-safe) value (`mycure-production-postgresql-password` v3), ALTER USER on the running primary, force-synced ExternalSecret, restarted cadence.
- [x] **Verified**:
  - `cadence` deployment 1/1 Available
  - PG connection: `Auto-discovered 0 tables from wildcard` (correct — empty `hapihub` DB)
  - Valkey connection: `Using Valkey metadata backend`
  - PG applier: `connected to primary database, applying changes`
  - JWKS validation: enabled (1 endpoint)
  - WebSocket sync at `/sync`
  - API listening on port 7890
  - External endpoint `https://cadence.localfirsthealth.com/health` returns `{"status":"pass"}`
  - External endpoint `https://cadence.localfirsthealth.com/status` returns peer status
- [ ] **Decision deferred**: cadence vs syncd coexistence vs replacement. Tracked in tier 6.1.

---

# 🔴 TIER 5 — HapiHub 10 → 11 Migration

The big one. **Full executable runbook**: [MIGRATION.md](./MIGRATION.md).

## Architecture (corrected 2026-04-07)

HapiHub 11.x is **PostgreSQL-only**. There's no MongoDB client in `~/Projects/mycure/monobase/services/hapihub/src/`. The Feathers-style model names (`accounts.accounts`) are now backed by Drizzle PG services. The migration moves the entire database from MongoDB to PG — it is **not** a dual-DB architecture.

## Migration tooling

The dedicated `~/Projects/mycure/monobase/services/hapihub-migrator` (v3.6.0+) tool is the migration engine. Already used for staging (proven by `_migration_checkpoints` table in staging PG). Modes:
- `bulk` — initial full copy MongoDB → PG, encrypted-field aware
- `cdc` — forward CDC (MongoDB → PG) for the gap window
- `reverse-cdc` — reverse CDC (PG → MongoDB) per a separate plan, **assumed available before Tier 5 begins** — this is what makes the cutover reversible
- `verify` — count + sample comparison

## Reversibility story (with reverse CDC)

| State | Rollback cost |
|---|---|
| Pre-cutover (forward CDC running, 10.x serving) | ✅ Zero cost |
| Cutover window (traffic frozen) | ✅ Zero cost |
| **Post-cutover with reverse CDC running** | ✅ Lag-window cost (~60s of writes) |
| After reverse CDC stopped (Phase 9) | ❌ Moderate-high cost |
| 24h+ after Phase 9 | ❌ Effectively non-reversible |

The **point of no return shifts from "first 11.x write" to "stopping reverse CDC"**. This decouples bake-in length from rollback risk — you can run hapihub 11.x for as long as needed to gain confidence, with reverse CDC continuously protecting the rollback path.

## 5.0 Prerequisites

- [ ] Reverse CDC mode (`MODE=reverse-cdc`) implemented and tested in the migrator (per separate plan)
- [ ] Tier 4.2.1 PG backups in place (Velero + nightly pg_dump)
- [ ] Migrator container image published to `ghcr.io/mycurelabs/hapihub-migrator:3.6.0` or newer

## 5.1 Phase 0 — Verify migrator coverage against production MongoDB ✅ DONE 2026-04-07

- [x] All 188 production collections enumerated against migrator's 83-collection registry
- [x] All 105 uncovered collections confirmed intentionally NOT migrated by user
- [x] Full intentional skip ledger documented in MIGRATION.md Phase 0 (with doc counts) for audit trail
- [x] No `collections.ts` changes required; no migrator image rebuild needed for coverage reasons

## 5.2 Phase 1 — Build & publish migrator image ✅ DONE 2026-04-07

- [x] `ghcr.io/mycurelabs/hapihub-migrator:3.7.0` published from monobase HEAD `71b97d80` (built on freyr.vanaheim)
- [x] Image digest `sha256:7ad117b2a0aa2690a63204e6c76bb8db5c3e7b27cf893de2fdbc9a62e568c111`
- [x] v3.7.0 includes the `MODE=reverse-cdc` capture-only feature (commit `d0133927`) and bundles drizzle-pg migrations through `0009_pg_changelog`
- [x] mono-infra `hapihubMigrator.image.tag` and `charts/hapihub-migrator/Chart.yaml` appVersion bumped to `3.7.0`
- [ ] **Known issue**: `services/hapihub-migrator/Dockerfile.dockerignore` is broken (excludes everything because the un-ignore patterns assume monorepo-root context, but `build-docker.sh` runs `docker build .` from inside the migrator dir). Workaround: temporarily move the file aside before building. Permanent fix is a separate migrator-repo change.

## 5.3 Phase 2 — Deploy migrator chart in mycure-production ✅ DONE 2026-04-07

- [x] `charts/hapihub-migrator/` chart created (commit `62faf84`)
- [x] `argocd/applications/templates/hapihub-migrator.yaml` created (commit `62faf84`)
- [x] `hapihubMigrator:` block added to `values/deployments/mycure-production.yaml`
- [x] NetworkPolicies inherited from `security-baseline` chart — migrator → mongodb-headless:27017 and migrator → postgresql-primary:5432 working
- [x] Connection URIs assembled in-template from in-cluster K8s secrets (postgresql, mongodb), no GCP secret indirection for DB strings

## 5.4 Phase 3 — Bulk migration run ✅ DONE 2026-04-07

- [x] Migrator deployed and bulk run completed: **85/85 collections, 0 failed**
- [x] PG `hapihub` database now ~14 GB
- [x] Auto-verification: 78 passed, 6 warned (4 transformer field-drift suspected verify-pass false positives, 2 expected dedup), 0 failed
- [x] Estimated 24–48h became ~2h actual elapsed (incl. recovery rerun), thanks to fixes shipped along the way
- **Bugs found and fixed during this phase** (all in `hapihub-migrator` repo):
  - **Bug A** (v3.7.1) — `batch.ts` exceeded PG's 65535-parameter Bind limit on wide tables. Fix: column-aware proactive split + recursive halving fallback.
  - **Bug B** (v3.7.1) — `RESUME_MIGRATION=true` didn't actually auto-resume; required explicit `RUN_ID` env var. Fix: `CheckpointManager.findLatestInProgressRunId()` + new `index.ts` resume branch.
  - **Bug C** (v3.7.2) — `worker.ts` resume cursor wrapped `lastId` in `new ObjectId()` unconditionally; broke for collections storing `_id` as a string (e.g. `billing-items`). Fix: sample one doc at resume to detect `typeof _id`.
  - **Bug D** (v3.7.3) — history tables of encrypted parents (`personal-details-history`, `medical-records-history`) silently dropped every doc with `_eh` set, because `collections.ts` didn't declare encryption metadata. Fix: declare same metadata as parent.
  - **Bug E** (v3.7.3) — silently-dropped docs were not counted as errors; `processed` counter advanced through full batch length, letting collections "complete" with massive silent loss. Fix: count drops in errors total so `maxErrorRate` guard catches bulk-drop scenarios.

## 5.5 Phase 4 — Forward CDC mode ✅ DONE 2026-04-07

- [x] Migrator switched to `MODE=cdc` (commit `f1428ba`)
- [x] Replayer started fresh (lastSeq=0), collector resumed from lastSeq=120795
- [x] Replayer drained the ~120k-event backlog (most of it `inventory-trackers` updates from production's background tracker job)
- [x] Lag stable at **<5 events / <1 second** in steady state, replayer keeping up with production's ~18 events/sec write rate
- [x] 24h+ stable-lag soak waived by user — proceeded directly to cutover
- **Bug found and fixed during this phase**:
  - **Bug H** (v3.7.4) — replayer didn't dedupe events by primary key within a batch. Production hapihub writes hundreds of updates to the same `inventory-trackers` rows per minute, so every CDC batch contained many events for the same row, tripping PG's `ON CONFLICT DO UPDATE command cannot affect row a second time` error and falling back to per-row inserts at ~80 events/sec. Fix: dedup by PK before sending to `batchInsert`, keeping the latest event per PK (events are seq-sorted). Throughput jumped ~1000x.

## 5.7 Phase 6 — Cutover ✅ DONE 2026-04-07

Production cut over from `hapihub:10.11.15` (MongoDB) to `hapihub:11.2.8` (PostgreSQL).

- [x] **Commit X** (`6baf8d7`) — froze production: `hapihub.replicaCount: 0`, `autoscaling.enabled: false`, `syncd.enabled: false` (permanently retired). Required a chart-side schema fix (commit `568f945`) to allow `replicaCount: 0`.
- [x] **Commit Y** (`d0fd493`) — the actual cutover: `hapihub.image.tag: 10.11.15 → 11.2.8`, `replicaCount: 0 → 3`, `autoscaling.enabled: false → true`. New 11.x pods came up reading from `postgresql-primary` via the `DATABASE_URI` constructed from the K8s `postgresql` secret (Phase 5 prep).
- [x] **Commit Z** (`321057b`) — switched migrator to `MODE=reverse-cdc`. 76 PG capture triggers installed on the allowlist; `_pg_changelog` is now recording every PG write atomically inside the source transaction.
- [x] External `/health` and `/.well-known/jwks.json` both return HTTP 200
- [x] Reverse-CDC verified firing in production (120+ `inventory_trackers` UPDATE captures within minutes of cutover)
- **Issue caught + fixed during cutover**:
  - **Private key SEC1 → PKCS#8** — `mycure-production-private-key` GCP secret was in SEC1 format (`BEGIN EC PRIVATE KEY`); hapihub 11.x's better-auth requires PKCS#8 (`BEGIN PRIVATE KEY`). JWKS endpoint returned `500 "pkcs8" must be PKCS#8 formatted string` immediately after cutover. This was flagged in Tier 4.1 and warned about explicitly but not pre-converted. Fix executed live: `openssl pkcs8 -topk8 -nocrypt -in old.pem -out new.pem`, pushed as version 2 of the GCP secret, force-synced ExternalSecret, rolling-restarted hapihub. JWKS now returns the EC public key correctly (`kid: hapihub-2025-01, alg: ES256`).
- **Risks accepted by user (declined prerequisites)**:
  - PG backups (Tier 4.2.1) — declined; if 11.x corrupts PG there is no recovery path other than re-running the migrator
  - 24h+ stable-lag CDC soak — waived; proceeded with ~30 min of stable lag instead
  - Investigation of 4 transformer field-drift WARNs (`accounts`, `export.requests`, `inventory-trackers`, `personal-details`) — deferred; one of them (`personal-details.createdAt`) is now visibly causing OpenAPI response validation warnings post-cutover but requests still return 200
  - MongoDB snapshot at cutover moment — not taken; rollback would replay against whatever state MongoDB is in
  - Stakeholder notification — not sent
- **Total cutover downtime**: ~5 minutes (commit X drain → commit Y rollout → 11.x readiness)

## 5.6 Phase 5 — Production hapihub secrets prep ✅ DONE 2026-04-07

- [x] `AUTH_SECRET`, `BETTER_AUTH_SECRET` added to `hapihub.externalSecrets.secrets` (commit `62faf84`); both keys present in `hapihub-secrets` K8s secret
- [x] `hapihub.postgresql:` block added (commit `4180ce3`) — chart auto-builds `DATABASE_URI` from in-cluster `postgresql` K8s secret pointing at `postgresql-primary.mycure-production.svc.cluster.local:5432/hapihub`. No GCP secret indirection needed.
- [x] All 10.x legacy keys preserved (`MONGO_URI`, `ENC_*`, `STORAGE_*`, `STRIPE_*`, `PRIVATE_KEY`, `PUBLIC_KEY`, `GOOGLE_*`) for rollback safety
- [x] Cold restart of hapihub 10.x verified: rolling restart picked up new env vars cleanly, all 3 replicas 1/1 Ready 0 restarts, external `https://hapihub.localfirsthealth.com/health` returns 200

## 5.7 Phase 6 — Cutover (15–30 min downtime)

- [ ] Take MongoDB + PG snapshots (rollback baselines)
- [ ] Scale hapihub 10.x to 0
- [ ] Wait for forward CDC lag = 0
- [ ] Stop forward CDC
- [ ] Bump `hapihub.image.tag` to `11.2.8`
- [ ] **Switch migrator to `MODE=reverse-cdc`** immediately after hapihub 11.x is healthy
- [ ] Smoke test
- [ ] Verify reverse CDC lag <60s

## 5.9 Phase 8 — Bake-in (72h minimum, with reverse CDC running)

- [ ] Monitor auth, PG, MongoDB reverse-CDC writes, cadence, error rates
- [ ] Spot-check PG↔MongoDB parity via reverse CDC
- [ ] Periodic verification jobs
- [ ] Rollback runbook stays warm; on-call trained

## 5.10 Phase 9 — Stop reverse CDC (THE actual point of no return)

- [ ] Verify reverse CDC delta is empty
- [ ] Stop migrator
- [ ] Take final MongoDB snapshot (frozen rollback baseline)
- [ ] Mark MongoDB as read-only in operational docs

## 5.11 Phase 10 — Tier 5 closure

- [ ] Update DIFF.md
- [ ] Move to Tier 6 (cleanup)

---

# 🔴 TIER 6 — Post-migration Cleanup

Only after Tier 5 is stable.

## 6.1 Retire legacy stack pieces

- [ ] Remove obsolete production GCP secrets (`MONGO_URI`, `STORAGE_*` if no longer used, etc.)
- [ ] Decide fate of syncd: keep alongside cadence, or retire
- [ ] If retiring: cutover sync clients (Maestro app, etc.)
- [ ] Remove syncd ExternalSecret entries

## 6.2 sync-logs archival

- [ ] Archive or drop the 99GB `sync-logs` collection (after confirming cadence has its own change log)
- [ ] Free up MongoDB storage / reduce backup size

## 6.3 Documentation

- [ ] Update this DIFF.md to reflect the new "in-sync" baseline
- [ ] Update CLAUDE.md with the new architecture notes
- [ ] Archive the migration runbook for future reference

---

## Things Production Has That Staging Doesn't (PRESERVE)

When promoting staging → production, do **NOT** lose these:

- `mycurelocal` at `1.4.0` with `find.mycure.md` hostname routing
- `hapihub` multi-hostname routing (`hapihub.localfirsthealth.com` + `api.mycure.md`)
- Production-tuned resource limits (especially MongoDB at 6Gi after the 2026-04-01 incident)
- HPA configuration for hapihub (3-5 replicas) and syncd (max 5)
- All legacy `ENC_*` / `STORAGE_*` secrets (until 11.x migration confirms they're not needed)
