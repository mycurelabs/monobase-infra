# HapiHub 10.11.15 → 11.2.8 Production Migration Runbook

> **Status**: planning
> **Created**: 2026-04-07
> **Owner**: TBD
> **See also**: [DIFF.md](./DIFF.md) Tier 5 — this document is the executable runbook for that tier.

---

## Context

Production runs HapiHub 10.11.15 (MongoDB only). Staging runs 11.2.8 (PostgreSQL only). The migration moves the **entire database** from MongoDB to PostgreSQL. Tier 4 has already deployed the PG HA cluster, Valkey, and Cadence in production with empty schemas.

The migration is performed by the dedicated `hapihub-migrator` tool at `~/Projects/mycure/monobase/services/hapihub-migrator` (v3.6.0+). It was already used for the staging migration.

**Assumption**: The migrator has a `MODE=reverse-cdc` mode (PG → MongoDB CDC) implemented per a separate plan, available before this migration begins. This mode tails PG WAL and replays writes to MongoDB. Without this mode, the cutover is irreversible after the first 11.x write. With this mode, MongoDB stays in sync with PG during the bake-in, making rollback safe within the reverse-CDC lag window.

---

## ⚠️ Prerequisite: reverse-cdc mode not yet shipped

As of 2026-04-07, `~/Projects/mycure/monobase/services/hapihub-migrator` v3.6.0
implements only `bulk | cdc | verify` modes. The mode dispatcher in
`src/config.ts:3` does not accept `reverse-cdc` yet, even though this runbook
treats it as the foundation of the rollback story.

**Phase 6 cutover MUST NOT proceed until** the migrator repo ships a release
that:

1. Adds `reverse-cdc` to the `MODE` union in `src/config.ts`
2. Implements PG → MongoDB CDC with re-encryption of `ENC_*` collections
3. Has a passing round-trip integration test (write to PG → assert in MongoDB)
4. Is published to `ghcr.io/mycurelabs/hapihub-migrator` with a version > 3.6.0

When that release is ready, bump `hapihubMigrator.image.tag` in
`values/deployments/mycure-production.yaml` to the new version BEFORE starting
Phase 6.

The mono-infra IaC scaffolding (chart, ArgoCD app, secrets) is already in place
and works for Phases 0–5. Phase 6 is the hard gate.

If reverse CDC is not available by the time Phases 3/4 complete, see DIFF.md
for the "proceed without reverse CDC" alternative — but treat that as a
re-plan, not a continuation of this runbook.

---

## Architecture (corrected understanding)

HapiHub 11.x is **PostgreSQL-only**. There is no `mongodb` package in `package.json`, no MongoDB client anywhere in `src/`. The Feathers-style model names like `accounts.accounts` are now backed by Drizzle PG services (`pg-service.ts`), not MongoDB. Production PG already has 117 tables seeded by the migrator's prior staging run, including `accounts`, `medical_records`, `billing_invoices`, `personal_details`, etc.

Once 11.x is serving traffic, all writes go to PG. MongoDB stops being authoritative the moment the cutover happens. The reverse-CDC mode is what keeps MongoDB warm as a rollback target during the bake-in.

---

## Reversibility — the actual story (with reverse CDC)

| State | Rollback cost |
|---|---|
| Pre-cutover (forward CDC running, 10.x serving) | ✅ **Zero cost.** Stop migrator, throw away PG data, 10.x continues. |
| Cutover window (traffic frozen, no writes happening) | ✅ **Zero cost.** Restart 10.x. |
| **Post-cutover with reverse CDC running** | ✅ **Lag-window cost.** ~60s of writes potentially lost (whatever the reverse-CDC lag is at the moment of rollback). MongoDB is otherwise current. Restart 10.x against the current MongoDB. |
| Post-cutover after reverse CDC is stopped (Phase 8) | ❌ **Moderate-high cost.** MongoDB freezes again. From this point forward, rollback means losing everything since reverse CDC was disabled. |
| 24h+ after Phase 8 | ❌ **Effectively non-reversible.** Forward-fix only. |

**The "point of no return" is defined by when you stop reverse CDC**, not by the cutover itself. This decouples cutover risk from bake-in length — you can run hapihub 11.x in production for as long as you need to gain confidence, with reverse CDC continuously protecting the rollback path.

### Reverse CDC limitations to verify before relying on it

- **Schema gaps**: PG tables with no MongoDB equivalent (`cadence_*` tables, `_migration_*` metadata, better-auth's `passkey`/`api_key`/etc.) should be excluded from reverse CDC
- **New columns**: PG columns that don't exist in MongoDB collections — reverse CDC needs a mapping or it'll either error or silently drop the field
- **Encrypted fields**: medical, billing, personal-details — reverse CDC must re-encrypt with the same encryption keys before writing to MongoDB
- **Conflict handling**: if a record exists in both PG (new write from 11.x) and MongoDB (stale 10.x copy), reverse CDC needs a tiebreaker (likely "PG wins")
- **Idempotency**: reverse CDC must be idempotent so a restart doesn't double-apply

---

## The migration tool

`hapihub-migrator` (v3.6.0+, Bun process with HTTP dashboard on :3000):

| Mode | Purpose |
|---|---|
| `MODE=bulk` | Phase 1 batch copy. Reads 88 MongoDB collections, decrypts encrypted fields (medical/billing/personal-details), writes to PG via Drizzle. Idempotent (`ON CONFLICT DO UPDATE`). Tracks per-collection checkpoints in `_migration_checkpoints` so it's resumable. |
| `MODE=cdc` | Forward CDC (MongoDB → PG). Tails MongoDB change stream into a `_migration_changelog` table; replayer applies events to PG continuously. Closes the gap between bulk cutoff and cutover. **Requires MongoDB to be a replica set** (production already is — `rs0`). |
| `MODE=reverse-cdc` | Reverse CDC (PG → MongoDB). Tails PG WAL or `_pg_changelog`, re-encrypts where needed, applies writes back to MongoDB. Used during the post-cutover bake-in. |
| `MODE=verify` | Compares row counts and samples between MongoDB and PG. Auto-runs after bulk by default. Available on-demand via HTTP `POST /verify`. |

**No-gap handoff**: the changelog collector starts BEFORE the bulk phase, so changes during bulk are captured into the changelog and replayed by Phase 2.

**Encryption keys** needed: `ENC_BILLING_INVOICES`, `ENC_BILLING_ITEMS`, `ENC_BILLING_PAYMENTS`, `ENC_MEDICAL_RECORDS`, `ENC_PERSONAL_DETAILS` (all already in production GCP secrets — Tier 4.1). Reverse CDC needs the same keys to re-encrypt.

**GridFS → S3**: optional; only relevant if production hapihub uses GridFS for file storage. Production already uses GCS — verify this is still true and skip GridFS migration if so.

---

## Phase 0 — Verify migrator coverage against production

Tasks (read-only, no production impact):

- [ ] Connect to production MongoDB (`mongodb-0` in `mycure-production`) and run `db.getCollectionNames()` to list all collections
- [ ] Compare against `~/Projects/mycure/monobase/services/hapihub-migrator/src/collections.ts` (currently 88 collections registered)
- [ ] Specifically check for collections that may be missing from the migrator:
  - `license.licenses`
  - `license.packages`
  - `billing.invoices` (note: distinct from `billing-invoices`)
  - `hl7-messages`
  - `bir.logs`
  - `organization-partners`
- [ ] Confirm these are intentionally NOT migrated (legacy auth + sync infra retired in 11.x):
  - `authentication`
  - `permissions`
  - `sync-logs`
- [ ] If gaps found AND have data in production: blocker. Add to migrator's `collections.ts`, ship a new migrator image, OR document and accept the data loss.

---

## Phase 1 — Build & publish migrator image

The migrator repo has a build/publish script at `~/Projects/mycure/monobase/services/hapihub-migrator/build-docker.sh`. It reads the version from `package.json`, tags as `ghcr.io/mycurelabs/hapihub-migrator:${VERSION}` and `:latest`, and pushes to GHCR with `--push`.

- [ ] Bump `package.json` version if needed (check current `version` field — `3.6.0` at time of writing)
- [ ] Run from the migrator directory:
  ```bash
  cd ~/Projects/mycure/monobase/services/hapihub-migrator
  ./build-docker.sh --push
  ```
- [ ] Verify the image is available: `docker pull ghcr.io/mycurelabs/hapihub-migrator:<version>`
- [ ] Smoke test locally with `MODE=verify` against the staging DBs to confirm the binary works

---

## Phase 2 — Deploy migrator chart in mycure-production

The migrator is a long-lived process (not a Job), so use a `Deployment`.

- [ ] Create `charts/hapihub-migrator/` (mirror existing chart structure):
  - `Deployment` (1 replica, restart=Always)
  - `Service` (ClusterIP on port 3000 for the dashboard)
  - Optional `HTTPRoute` for `migrator.localfirsthealth.com` (gated, internal-only access)
  - `ExternalSecret` referencing existing GCP secrets for encryption keys + DB URIs
- [ ] Wire env vars:
  - `MONGO_SOURCE_URI` — built from in-cluster mongodb credentials (mongodb-0 service + root password from secret)
  - `PG_TARGET_URI` — `postgres://postgres:${POSTGRESQL_PASSWORD}@postgresql-primary.mycure-production.svc.cluster.local:5432/hapihub` (URL-safe v3 password from Tier 4.4)
  - `ENC_BILLING_INVOICES`, `ENC_BILLING_ITEMS`, `ENC_BILLING_PAYMENTS`, `ENC_MEDICAL_RECORDS`, `ENC_PERSONAL_DETAILS` — from existing prod GCP secrets
  - `STORAGE_*` — only if GridFS migration is needed
  - `MODE=bulk` initially
  - `EXIT_ON_BULK_END=false` (keep alive for dashboard + transition to CDC)
  - `BATCH_SIZE=1000`, `COLLECTION_CONCURRENCY=4` (defaults; tune based on throughput)
  - `RESUME_MIGRATION=true`
  - `MAX_ERROR_RATE=0.01`
- [ ] NetworkPolicies:
  - Egress from migrator to `mongodb-0` on 27017
  - Egress from migrator to `postgresql-primary` on 5432
  - Ingress from gateway (if dashboard exposed) or from a port-forward only
- [ ] Add `hapihubMigrator:` block to `values/deployments/mycure-production.yaml`
- [ ] Add `argocd/applications/templates/hapihub-migrator.yaml`

---

## Phase 3 — Bulk migration run

**Zero impact on production traffic.** 10.x continues serving while the migrator reads MongoDB and writes PG.

- [ ] Apply the chart, watch the migrator come up
- [ ] Port-forward the dashboard: `kubectl port-forward svc/hapihub-migrator 3000:3000 -n mycure-production`
- [ ] Open `http://localhost:3000`, watch Overview tab
- [ ] Monitor:
  - `/status` — overall progress
  - `/collector/status` — changelog collector should be running
  - `/collections` — per-collection progress and counts
  - `/audit` — warnings/errors
- [ ] **Estimate**: production has ~135 GB raw data + 32 GB indexes / 209 M docs across 193 collections. Bulk takes **24–48 hours** depending on PG write throughput. Plan for 48 hours worst case.
- [ ] After bulk completes:
  - All collections in `completed` state in `_migration_checkpoints`
  - Auto-verification report (in `_migration_verification` table) shows pass/warn/fail per collection
  - Audit log has no `error` severity events
- [ ] Address any failures: re-run with `RESUME_MIGRATION=true` or fix manually and resume

---

## Phase 4 — Forward CDC mode

Switch the migrator to forward CDC so any writes 10.x makes during the prep window get replicated to PG.

- [ ] Change `MODE` env var to `cdc` (via the Deployment, restart pod)
- [ ] Verify `/cdc/status` shows the replayer running and lag < 60s
- [ ] Run on-demand verification: `curl -X POST http://localhost:3000/verify`
- [ ] Review report: row counts match MongoDB, sampled rows match within tolerance
- [ ] Let CDC run for at least 24 hours to confirm stability
- [ ] Watch lag metric — if it grows unboundedly, investigate before proceeding

---

## Phase 5 — Production hapihub secrets prep

Update production hapihub's ExternalSecret to add the new 11.x keys, but keep the old ones for rollback safety.

- [ ] Add to `hapihub.externalSecrets.secrets` list:
  - `AUTH_SECRET` ← `mycure-production-auth-secret`
  - `BETTER_AUTH_SECRET` ← `mycure-production-better-auth-secret`
  - `DATABASE_URL` (or whatever 11.x's PG env var is — verify in `~/Projects/mycure/monobase/services/hapihub/src/config-env-map.ts`) constructed from the existing `postgresql` K8s secret
- [ ] **Keep all 10.x secrets**: `MONGO_URI`, `ENC_*`, `STORAGE_*`, `PUBLIC_KEY`, `STRIPE_KEY`, `STRIPE_CHECKOUT_*`. They're harmless to 11.x and required by 10.x for rollback. Cleanup happens in Tier 6.
- [ ] Force-sync ExternalSecret, verify K8s `hapihub-secrets` Secret has all keys
- [ ] Verify a cold restart of hapihub 10.x still works (rollback rehearsal of the secrets layer)

---

## Phase 6 — Cutover (15–30 min downtime)

### Pre-cutover checklist

- [ ] PG backup taken (Velero PVC snapshot AND `pg_dump -Fc` to GCS) — Tier 4.2.1 prerequisite
- [ ] MongoDB backup taken (Velero PVC snapshot AND `mongodump` to GCS) — worst-case rollback baseline
- [ ] Reverse CDC mode validated in the migrator's own test suite (no separate staging dress rehearsal — we trust the tool)
- [ ] Final forward CDC verification: `/verify` reports all collections green
- [ ] Forward CDC lag <5s at the moment of cutover
- [ ] Stakeholders notified of maintenance window
- [ ] Rollback values diff prepared
- [ ] On-call coverage in place

### Cutover steps

1. [ ] Announce "maintenance starting"
2. [ ] Scale hapihub 10.x to 0 replicas to freeze writes
3. [ ] Wait for forward CDC lag to drop to 0 (no more changes in `_migration_changelog`)
4. [ ] Final spot-check verification: `curl -X POST :3000/verify` — confirm pass
5. [ ] Stop forward CDC mode (the migrator pod will continue running, mode change next)
6. [ ] Update `values/deployments/mycure-production.yaml`:
   - Bump `hapihub.image.tag` from `10.11.15` to `11.2.8`
   - Confirm new env keys are present
7. [ ] Commit, push, force ArgoCD pickup
8. [ ] Watch the new pod come up. Drizzle migrations should be a no-op since the migrator already created all tables. Verify in logs: `Drizzle migrations: nothing to apply`
9. [ ] Verify hapihub readiness probe is green
10. [ ] **Switch the migrator to `MODE=reverse-cdc`** to start mirroring 11.x's PG writes back to MongoDB. Verify the dashboard shows reverse CDC lag <5s.
11. [ ] Smoke test from outside:
    - `https://hapihub.localfirsthealth.com/.well-known/jwks.json` returns JWKS
    - `/health` endpoint
    - Login with a known account
    - Password reset flow
    - Read a medical encounter, billing invoice, queue item
    - **Create a new patient or encounter** — verify it shows up in MongoDB within the reverse-CDC lag window
12. [ ] Watch error logs for 30 minutes
13. [ ] If green: declare cutover complete. **Leave the migrator running in reverse-CDC mode.** Move to Phase 7.
14. [ ] Announce "maintenance complete"

### Rollback procedure (during cutover or anytime in the bake-in window while reverse CDC is running)

1. [ ] `kubectl set image deployment/hapihub hapihub=ghcr.io/mycurelabs/hapihub:10.11.15 -n mycure-production` (faster than ArgoCD)
2. [ ] Watch the rollback pod come up
3. [ ] Wait for reverse CDC to drain pending events (dashboard shows lag — should hit 0 within seconds)
4. [ ] Stop the migrator's reverse-CDC mode
5. [ ] Verify 10.x is healthy and reading the up-to-date MongoDB
6. [ ] git revert the cutover commit, push, let ArgoCD reconcile
7. [ ] **Data loss = whatever was in flight in the reverse-CDC pipeline at the moment of rollback** (typically <60s of writes). Document them by querying the migrator's audit log for the rollback window.
8. [ ] If you want to retry later: drop PG `hapihub` tables and re-run the bulk migration from scratch, OR delta-sync via forward CDC

---

## Phase 7 — Bake-in (72h minimum, with reverse CDC running)

After cutover succeeds. The migrator stays running in `reverse-cdc` mode for the entire bake-in. Bake-in length is now decoupled from rollback risk — you can run for days without losing rollback capability.

- [ ] Monitor auth errors, login failures
- [ ] Monitor PG resource usage (memory, CPU, disk growth)
- [ ] Monitor MongoDB reverse-CDC writes — should track 11.x's PG write rate
- [ ] Monitor reverse-CDC lag — alert if it grows beyond 60s
- [ ] Monitor hapihub error rate, pod restarts
- [ ] Monitor cadence — real users should generate sync activity now
- [ ] Spot-check parity between PG and MongoDB:
  - Create an encounter in 11.x → verify it appears in MongoDB
  - Update a billing invoice → verify the change propagates to MongoDB
- [ ] Run periodic verification jobs: `curl -X POST :3000/verify`
- [ ] Keep the rollback runbook warm — train an on-call to execute it from memory

---

## Phase 8 — Stop reverse CDC (the actual point of no return)

When you're ready to commit fully to 11.x and accept that rollback now means data loss.

### Decision criteria

- Bake-in clean for 72+ hours
- No outstanding bug reports related to the migration
- PG metrics within projections
- Stakeholders signed off
- A retry plan exists in case of catastrophic failure (full restore from PG backups)

### Steps

- [ ] Final reverse-CDC verification: PG ↔ MongoDB delta is empty
- [ ] Stop the migrator: `kubectl scale deploy/hapihub-migrator --replicas=0 -n mycure-production`
- [ ] Take a final MongoDB snapshot — this is now the "frozen rollback baseline" if anything ever goes wrong with PG
- [ ] Mark MongoDB as read-only in operational docs (still queryable, but no longer authoritative)
- [ ] Update DIFF.md: Tier 5 complete, Tier 6 unblocked

---

## Phase 9 — Closure

- [ ] Mark Tier 5 as complete in DIFF.md
- [ ] Move to Tier 6 (cleanup): retire MongoDB, remove obsolete secrets, retire syncd, archive sync-logs

---

## Files to modify

| File | Change | Phase |
|---|---|---|
| `charts/hapihub-migrator/` (new directory) | New chart for the migrator deployment | Phase 2 |
| `argocd/applications/templates/hapihub-migrator.yaml` (new) | ArgoCD app for migrator | Phase 2 |
| `values/deployments/mycure-production.yaml` | Add `hapihubMigrator:` block, enabled | Phase 2 |
| `values/deployments/mycure-production.yaml` | Add new ExternalSecret keys to hapihub block; keep all legacy keys | Phase 5 |
| `values/deployments/mycure-production.yaml` | Bump `hapihub.image.tag` 10.11.15 → 11.2.8 | Phase 6 |

That's it for IaC. Drizzle migrations are run by hapihub itself on startup (and will be a no-op since the migrator already created the tables).

---

## Critical files (reference only)

| File | Purpose |
|---|---|
| `~/Projects/mycure/monobase/services/hapihub-migrator/README.md` | Migrator usage, env vars, modes |
| `~/Projects/mycure/monobase/services/hapihub-migrator/src/collections.ts` | The 88-collection registry — verify completeness against prod |
| `~/Projects/mycure/monobase/services/hapihub-migrator/src/index.ts` | Migrator entry point, mode dispatcher |
| `~/Projects/mycure/monobase/services/hapihub-migrator/Dockerfile` | Image build |
| `~/Projects/mycure/monobase/services/hapihub/src/cli/start.ts` | 11.x startup, DB wait loop |
| `~/Projects/mycure/monobase/services/hapihub/src/auth/migration.ts` | Lazy on-login user migration (separate from data migrator) |
| `~/Projects/mycure/monobase/services/hapihub/drizzle-pg/0000_lumpy_overlord.sql` | Initial PG schema (62KB) |
| `~/Projects/mycure/monobase/services/hapihub/src/config-env-map.ts` | 11.x env var → config mapping |

---

## Out of scope for Tier 5

| Item | Tracked in |
|---|---|
| Removing obsolete legacy secrets (`MONGO_URI`, `ENC_*` if confirmed unused, `STORAGE_*`, etc.) | DIFF.md Tier 6.1 |
| Retiring MongoDB entirely | DIFF.md Tier 6 |
| Retiring syncd | DIFF.md Tier 6.1 |
| PG backups setup | DIFF.md Tier 4.2.1 — **must be done before Phase 6 cutover** |
| Auto-failover for PG | DIFF.md Tier 4.2.2 |
| Staging dress rehearsal | **Skipped** — staging migration was already validated; the migrator's own test coverage is the rehearsal |

---

## Estimated timeline

| Phase | Duration | Requires downtime? |
|---|---|---|
| 0 — Verify collections coverage | 1–2 h | No |
| 1 — Build migrator image | 30 min | No |
| 2 — Deploy migrator chart | 1 h | No |
| 3 — Bulk migration run | **24–48 h** | No |
| 4 — Forward CDC mode | 24+ h | No |
| 5 — Hapihub secrets prep | 30 min | No |
| 6 — Cutover | **15–30 min downtime** | Yes |
| 7 — Bake-in (with reverse CDC) | **72 h minimum** | No |
| 8 — Stop reverse CDC | 30 min | No |
| 9 — Closure | 30 min | No |

**Total elapsed time: ~5–7 days** if everything goes smoothly.
**Production downtime: ~15–30 minutes** during the cutover step itself.
**Rollback safety**: maintained throughout phases 0–7 thanks to reverse CDC. Phase 8 is the actual point of no return.

---

## Success criteria

- Production hapihub running 11.2.8, zero crash loops
- Auth error rate at or below 10.x baseline
- All smoke tests pass: login, password change, billing read, medical encounter read, new record creation
- PG sizing within projections (memory, CPU, disk)
- Forward CDC verification report shows all collections in pass/warn (no fails)
- Reverse CDC operating with lag <60s consistently throughout bake-in
- Spot-checked parity: writes in PG visible in MongoDB within the lag window
- No clinician reports of data loss or login problems beyond the expected re-login window
- 72h bake-in clean
- Phase 8 sign-off received before stopping reverse CDC
