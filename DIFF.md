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

- [ ] Decide: Option A vs B vs C (deferred until Tier 4 actually needs the capacity)
- [ ] Plan resize/add-node maintenance window when Tier 4 work begins

## 3.5 syncd replica strategy

- [x] Production syncd reduced to `replicaCount: 1`, autoscaling `min=1, max=2` (2026-04-06)
  - was: `replicaCount: 5`, autoscaling `max=5` — was contributing to MongoDB load
  - Lower cap reduces sync-logs query pressure until syncd is migrated/retired in Tier 5/6

---

# 🟠 TIER 4 — Infrastructure Prep for 11.x

These prepare production to RECEIVE the new stack, but don't change hapihub yet. Reversible if needed.

## 4.1 Create production GCP secrets for 11.x stack

11.x needs new secret keys that staging already has but production doesn't.

- [ ] `mycure-production-auth-secret` (new — for legacy `AUTH_SECRET`)
- [ ] `mycure-production-better-auth-secret` (new — better-auth signing key)
- [ ] `mycure-production-postgresql-password` (new — for in-cluster or managed PG)
- [ ] `mycure-production-valkey-password` (new — already needed by ExternalSecret)
- [ ] Verify `mycure-production-private-key` exists and is the right key for 11.x JWKS

## 4.2 Provision PostgreSQL in production

11.x requires PG for better-auth + cadence metadata.

- [ ] Decide: in-cluster Bitnami PG vs DigitalOcean Managed PG
- [ ] If in-cluster: ensure PVC storage class supports growth, plan backup via Velero
- [ ] If managed: provision instance, configure VPC peering, store URI in GCP secret
- [ ] Create `database` and `username` for hapihub
- [ ] Add `postgresql-credentials` ExternalSecret to `database-secrets` chart (already exists in staging)
- [ ] Verify connectivity from hapihub namespace
- [ ] Document backup/restore procedure

## 4.3 Enable Valkey in production

- [ ] Set `valkey.enabled: true` in `mycure-production.yaml`
- [ ] Apply staging-tested resource sizing: `1Gi` request / `2Gi` limit (per the 2026-04-06 OOM lessons)
- [ ] Apply `primary.resourcesPreset: none` chart fix (already merged 2026-03-29)
- [ ] Use ServerSideApply (already in valkey ArgoCD app template)
- [ ] Verify `valkey-credentials` ExternalSecret syncs successfully
- [ ] Smoke test: `redis-cli` from hapihub namespace

## 4.4 Enable Cadence in production

Depends on 4.2 (PG) and 4.3 (Valkey).

- [ ] Add `cadence:` block to `mycure-production.yaml` (mirror staging structure)
- [ ] Use `0.4.0` image with `--primary-db` CLI workaround (already in chart from 2026-03-27)
- [ ] Apply scope rules + explicit `accounts`/`personal_details` collections (already in chart values)
- [ ] Verify NetworkPolicies are deployed (allow-gateway-to-cadence, allow-cadence-to-valkey, allow-cadence-egress)
- [ ] Smoke test: `/status` endpoint, JWKS validation, change log polling
- [ ] Decide: cadence stays alongside syncd, or replaces it eventually?

---

# 🔴 TIER 5 — HapiHub 10 → 11 Migration

The big one. Requires a runbook, downtime window or blue/green, data migration, and rollback plan.

## 5.1 Pre-migration analysis

- [ ] Document complete env var diff between hapihub 10.11.15 and 11.2.8 (which legacy `ENC_*`, `STORAGE_*`, `MONGO_URI`, `PUBLIC_KEY`, `STRIPE_KEY` are still consumed?)
- [ ] Identify which production data needs to migrate to PG vs stay in MongoDB
- [ ] Identify schema differences in `account` / `accounts` / `personal_details` between versions
- [ ] Verify the password sync script from 2026-04-01 covers all accounts (or refresh it)

## 5.2 Migration runbook

- [ ] Draft step-by-step runbook with rollback steps
- [ ] Define maintenance window (or blue/green strategy)
- [ ] Define success/failure criteria (smoke tests, key user flows)
- [ ] Identify stakeholders to notify
- [ ] Prepare DB snapshots (Velero + MongoDB dump + PG dump pre-migration)

## 5.3 Staging dress rehearsal

Don't migrate prod blind — rehearse against a prod data clone in staging.

- [ ] Restore latest production MongoDB snapshot to a parallel staging environment
- [ ] Run migration scripts end-to-end
- [ ] Smoke test login (better-auth + legacy users)
- [ ] Smoke test billing, medical encounters, queue items
- [ ] Smoke test sync-logs / cadence flows
- [ ] Document any issues / edge cases discovered

## 5.4 Cutover

- [ ] Execute runbook
- [ ] Monitor health metrics during migration
- [ ] Verify smoke tests post-cutover
- [ ] Keep rollback path warm for 24-48h after

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
