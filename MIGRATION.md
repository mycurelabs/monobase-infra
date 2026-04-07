# HapiHub 10.11.15 → 11.2.8 Production Migration Runbook

> **Status**: planning
> **Created**: 2026-04-07
> **Owner**: TBD
> **See also**: [DIFF.md](./DIFF.md) Tier 5 — this document is the executable runbook for that tier.

---

## Context

Production runs HapiHub 10.11.15 (MongoDB only). Staging runs 11.2.8 (PostgreSQL only). The migration moves the **entire database** from MongoDB to PostgreSQL. Tier 4 has already deployed the PG HA cluster, Valkey, and Cadence in production with empty schemas.

The migration is performed by the dedicated `hapihub-migrator` tool at `~/Projects/mycure/monobase/services/hapihub-migrator` (v3.6.0+). It was already used for the staging migration.

**Reverse CDC is capture-only** in `hapihub-migrator` v3.7.0 (`MODE=reverse-cdc`). It installs PostgreSQL triggers on an allowlist of tables (computed from `collections.ts`, excludes history tables, better_auth tables, and PG-native tables) that record every INSERT/UPDATE/DELETE into a new `_pg_changelog` table — atomically inside the same PG transaction as the source write. It does **not** replay those records back to MongoDB; replay is explicit operator work if rollback is needed (or accept the drift). The `_pg_changelog` is the forensic trail that makes manual rollback possible.

---

## Architecture

HapiHub 11.x is **PostgreSQL-only**. There is no `mongodb` package in `package.json`, no MongoDB client anywhere in `src/`. The Feathers-style model names like `accounts.accounts` are now backed by Drizzle PG services (`pg-service.ts`), not MongoDB. Production PG already has 117 tables seeded by the migrator's prior staging run, including `accounts`, `medical_records`, `billing_invoices`, `personal_details`, etc.

Once 11.x is serving traffic, all writes go to PG. MongoDB stops being authoritative the moment the cutover happens. Reverse-CDC keeps a per-row audit trail of every PG write so an operator can reconstruct the delta if rollback is required.

---

## Reversibility story

| State | Rollback cost |
|---|---|
| Pre-cutover (forward CDC running, 10.x serving) | ✅ **Zero cost.** Stop migrator, throw away PG data, 10.x continues. |
| Cutover window (traffic frozen, no writes happening) | ✅ **Zero cost.** Restart 10.x. |
| **Post-cutover, reverse-cdc capture active** | ⚠️ **Manual replay cost.** All PG writes since cutover are in `_pg_changelog`. Operator either (a) replays them into MongoDB by hand, or (b) accepts the drift and restarts 10.x against the stale MongoDB. The cost is operator-time + whatever subset of writes can't be replayed. |
| Post-cutover after reverse-cdc triggers torn down | ❌ **No forensic trail.** MongoDB is frozen, PG drift is unrecoverable from the migrator's records. Forward-fix only. |
| 24h+ after teardown | ❌ **Effectively non-reversible.** |

**The point of no return is teardown of the reverse-cdc triggers**, not the cutover itself. Bake-in length is decoupled from rollback feasibility — leave the triggers installed for as long as confidence in 11.x is being built up. The triggers run inside source PG transactions, so worst-case overhead is per-write trigger latency, not async lag.

### Reverse-cdc capture properties

- **Trigger-based** (NOT logical replication): no `wal_level` change, no superuser, atomic with the source write, survives MongoDB outages because MongoDB isn't in the loop.
- **Allowlist** comes from `collections.ts` and excludes history tables, better_auth tables, and all PG-native tables (`_migration_*`, `_pg_changelog`, `__drizzle_migrations`, `pg-boss`, `cadence_*`).
- **Delete events** capture only the PK — full OLD-row capture would inflate `_pg_changelog` significantly.
- **Mutual exclusivity** with forward CDC: startup refuses if `_cdc_resume_tokens` was updated within 60s. Forward and reverse CDC cannot run concurrently against the same PG.
- **Idempotent install**: `installMissing()` skips tables that already have a trigger. Operator teardown via `POST /reverse-cdc/triggers/teardown`.
- **PG-only**: `MODE=reverse-cdc` does not connect to MongoDB at all. `MONGO_SOURCE_URI` is unused.

---

## The migration tool

`hapihub-migrator` v3.7.0 (Bun process with HTTP dashboard on :3000), image `ghcr.io/mycurelabs/hapihub-migrator:3.7.0`:

| Mode | Purpose |
|---|---|
| `MODE=bulk` | Phase 1 batch copy. Reads 83 MongoDB collections, decrypts encrypted fields (medical/billing/personal-details), writes to PG via Drizzle. Idempotent (`ON CONFLICT DO UPDATE`). Tracks per-collection checkpoints in `_migration_checkpoints` so it's resumable. |
| `MODE=cdc` | Forward CDC (MongoDB → PG). Tails MongoDB change stream into a `_migration_changelog` table; replayer applies events to PG continuously. Closes the gap between bulk cutoff and cutover. **Requires MongoDB to be a replica set** (production already is — `rs0`). |
| `MODE=reverse-cdc` | Reverse CDC capture (PG only). Installs PG triggers on the allowlist; every INSERT/UPDATE/DELETE writes to `_pg_changelog`. **Capture only** — no MongoDB replay. Used during the post-cutover bake-in as the rollback forensic trail. |
| `MODE=verify` | Compares row counts and samples between MongoDB and PG. Auto-runs after bulk by default. Available on-demand via HTTP `POST /verify`. |

**No-gap handoff**: the changelog collector starts BEFORE the bulk phase, so changes during bulk are captured into the changelog and replayed by Phase 2.

**Encryption keys** needed: `ENC_BILLING_INVOICES`, `ENC_BILLING_ITEMS`, `ENC_BILLING_PAYMENTS`, `ENC_MEDICAL_RECORDS`, `ENC_PERSONAL_DETAILS` (all already in production GCP secrets — Tier 4.1). Reverse CDC needs the same keys to re-encrypt.

**GridFS → S3**: optional; only relevant if production hapihub uses GridFS for file storage. Production already uses GCS — verify this is still true and skip GridFS migration if so.

---

## Phase 0 — Verify migrator coverage against production ✅ DONE 2026-04-07

Production MongoDB enumerated against `~/Projects/mycure/monobase/services/hapihub-migrator/src/collections.ts` (83 registered collections: 79 main + 4 better-auth).

**Verdict**: production has 188 collections; migrator covers 83; the 105 uncovered collections are **all intentionally not migrated** (confirmed by user 2026-04-07). No `collections.ts` changes required, no migrator image rebuild required for coverage reasons.

The intentional skip ledger below is the audit trail — every uncovered collection with non-zero document count is enumerated so the data-loss scope is explicit and reviewable.

### Intentional skip ledger (collections NOT migrated, with prod doc counts)

**Legacy auth + sync infra (retired in 11.x):**

| Collection | Docs | Reason |
|---|---:|---|
| `authentication` | 5,848,603 | Replaced by better-auth |
| `permissions` | 383,176 | Replaced by better-auth/authz |
| `authz.permissions` | 0 | (empty) |
| `sync-logs` | 183,200,580 | syncd retired; cadence is the replacement |
| `sync-clients` | 58 | syncd retired |
| `sync-instances` | 236 | syncd retired |
| `sync.logsIncoming` | 0 | (empty) |
| `sync.metrics` | 0 | (empty) |
| `system-syncbases` | 23 | syncd retired |
| `system-syncbase-markers` | 35 | syncd retired |

**MongoDB internals (not application data):**

| Collection | Docs | Reason |
|---|---:|---|
| `system.profile` | 659 | MongoDB diagnostic profiler |
| `system.views` | n/a | MongoDB internal |

**Substantial uncovered collections (intentional, accepting data loss):**

| Collection | Docs | Notes |
|---|---:|---|
| `bir.logs` | 216,595 | PH BIR audit log — retained in MongoDB only / not needed in 11.x |
| `bff.encounterServiceIndex` | 564,217 | Derived index, rebuildable from source data |
| `issues` | 49,550 | Internal issue tracker, not needed in 11.x |
| `metrics.metrics` | 312,908 | Legacy analytics, replaced/retired |
| `metrics.metricsv2` | 31,096 | Legacy analytics |
| `metrics.metricsRaw` | 8,546 | Legacy analytics |
| `appointments` | 14,385 | Replaced by `booking.bookings` (which IS migrated) |
| `system-counters` | 11,256 | Distinct from `counters` (which is migrated); legacy counters |

**History tables not in 11.x:**

| Collection | Docs |
|---|---:|
| `billing-invoices-history` | 103 |
| `billing-items-history` | 75 |
| `billing.creditAccounts-history` | 52 |

(11.x keeps history for medical-records, personal-details, inventory-stocks, diagnostic-order-tests only.)

**Smaller uncovered (all intentional):**

`account-tasks` (44), `account-waitlist` (21), `agendaJobs` (1,945), `chat-messages` (563), `chat-rooms` (121), `chat-sessions` (5), `consultation-sessions` (70), `medical.organizations` (914), `unified.directory` (949), `metrics.customers` (459), `metrics.days` (146), `metrics.subscriptions` (4), `schedule-slots` (636), `sms` (754), `prm.groups` (1), `prm.workflows` (4), `pharmacy-accreditations` (1), `philhealth-configurations` (2), `subscription.products` (26), `billing-payment-gateways` (11), `billing-payment-intents` (26), `billing.products` (2), `developer.appConfigs` (2), `export.metrics` (9), `hl7-messages` (8), `license.products` (2), `rating.ratings` (8), `publishing.entries` (3), `file-links` (16), `twoFactor` (1), `medical-records-error` (1), `billing-invoices-error` (2), `bir-machines` (1), `bir.readings` (15), `booking.calendars` (21), `booking.eventTypes` (28), `booking.eventTypesDeleted` (5), `booking.schedules` (11), `booking.schedulesDeleted` (1), `comms.messages` (1), `comms.providers` (1), `comms.threads` (1), `organization.flat_address` (1,326)

**GridFS files (intentional skip — production migrated to GCS):**

| Collection | Docs |
|---|---:|
| `files.files` | 11 |
| `files.chunks` | 11 |

11 GridFS files are stale/orphaned residue from before the GCS cutover. Accepted loss.

**Empty collections (0 docs — trivially intentional):**

`hmo.*` (8 collections — entire HMO module unused), `ward-beds`, `ward-occupants`, `ward-rooms`, `visit-logs`, `tenants`, `reminders`, `request.orders`, `reviews`, `ratings`, `rewards.*` (3), `messaging.messages`, `email.emails`, `fares.*` (4), `mci.transactions`, `bookingv2.bookings`, `chat-bots`, `accounts.onboardingConfigurations`, `license.licenses`, `license.packages`, `subscription.events`, `billing-orders`, `billing-payouts`, `billing.invoices` (dotted variant — distinct from migrated `billing-invoices`), `billing.payouts`, `billing.subscriptions`, `billing.accountingTransactions`, `organization-affiliations`, `organization-partners`, `organization-vouchings`, `bir-accreditations`

**Note on `public-profiles`:** registered in `collections.ts` but does not exist in production MongoDB. Harmless — migrator will simply skip it.

### Phase 0 sign-off

- [x] Collections enumerated (188 in production)
- [x] Migrator coverage verified (83 collections in `collections.ts`)
- [x] Gap analysis complete with doc counts
- [x] All uncovered collections confirmed intentionally skipped (user, 2026-04-07)
- [x] Intentional skip ledger documented above for audit trail

---

## Phase 1 — Build & publish migrator image ✅ DONE 2026-04-07

- [x] v3.7.0 published to `ghcr.io/mycurelabs/hapihub-migrator:3.7.0` (also tagged `:latest`)
- [x] Built on freyr.vanaheim from monobase HEAD `71b97d80`
- [x] Image digest: `sha256:7ad117b2a0aa2690a63204e6c76bb8db5c3e7b27cf893de2fdbc9a62e568c111`
- [x] Includes the v3.7.0 reverse-cdc capture feature (commit `d0133927`) and the bundled drizzle-pg migrations through `0009_pg_changelog`

### Known issue (separate workstream)

`services/hapihub-migrator/Dockerfile.dockerignore` is broken: it excludes `*` then re-includes paths under `services/hapihub-migrator/...`, which only resolves correctly when the build context is the monorepo root. `build-docker.sh` runs `docker build .` from inside the migrator directory, so the un-ignore patterns don't match anything and the build context is empty (`transferring context: 2B done`). The build fails at `COPY bins/hapihub-migrator-linux-*.tar.gz ./` with `lstat /bins: no such file or directory`.

**Workaround used for v3.7.0**: temporarily move `Dockerfile.dockerignore` aside, run the build, restore it.

**Permanent fix** (TODO in the migrator repo): either rewrite `Dockerfile.dockerignore` for migrator-relative paths, or change `build-docker.sh` to chdir to the monorepo root and pass `-f services/hapihub-migrator/Dockerfile`.

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
10. [ ] **Switch the migrator to `MODE=reverse-cdc`** to install PG triggers that capture every 11.x write into `_pg_changelog`. Verify in logs: `Reverse-CDC mode active. Triggers capturing writes to _pg_changelog`.
    - Reverse-cdc refuses to start if forward CDC was active in the last 60s — wait for the cursor to idle out, or this is a no-op.
    - Triggers attach atomically; from this point forward, every write to an allowlisted table is also recorded in `_pg_changelog`.
11. [ ] Smoke test from outside:
    - `https://hapihub.localfirsthealth.com/.well-known/jwks.json` returns JWKS
    - `/health` endpoint
    - Login with a known account
    - Password reset flow
    - Read a medical encounter, billing invoice, queue item
    - **Create a new patient or encounter** — verify the row appears in `_pg_changelog` (`SELECT * FROM _pg_changelog ORDER BY id DESC LIMIT 5`)
12. [ ] Watch error logs for 30 minutes
13. [ ] If green: declare cutover complete. **Leave the reverse-cdc triggers installed.** Move to Phase 7.
14. [ ] Announce "maintenance complete"

### Rollback procedure (anytime while reverse-cdc triggers are still installed)

1. [ ] `kubectl set image deployment/hapihub hapihub=ghcr.io/mycurelabs/hapihub:10.11.15 -n mycure-production` (faster than ArgoCD)
2. [ ] Watch the rollback pod come up
3. [ ] **Decide on the `_pg_changelog` delta**: query `SELECT collection, op, COUNT(*) FROM _pg_changelog GROUP BY 1, 2;` to see what 11.x wrote since cutover.
   - **Option A — replay**: write a one-shot script that reads `_pg_changelog`, looks up each PK in the corresponding PG table, re-encrypts where needed using the same `ENC_*` keys the migrator uses, and upserts into MongoDB. This is operator work — there is no automatic replayer.
   - **Option B — accept the drift**: skip the replay, restart 10.x against the stale MongoDB. Anything written between cutover and rollback is lost.
4. [ ] Tear down the reverse-cdc triggers via `POST /reverse-cdc/triggers/teardown` once the decision is made (so PG isn't carrying trigger overhead during the rollback)
5. [ ] Verify 10.x is healthy
6. [ ] `git revert` the cutover commit, push, let ArgoCD reconcile
7. [ ] Document the data-loss decision (which writes were replayed vs accepted as lost) — `_pg_changelog` is the audit trail.
8. [ ] If you want to retry later: drop PG `hapihub` tables and re-run the bulk migration from scratch, OR delta-sync via forward CDC

---

## Phase 7 — Bake-in (72h minimum, reverse-cdc triggers capturing)

After cutover succeeds. The reverse-cdc triggers stay installed for the entire bake-in. Bake-in length is decoupled from rollback feasibility — leave them in place for as long as confidence in 11.x is being built up. The triggers run inside source PG transactions, so worst case is per-write trigger latency, not async lag.

- [ ] Monitor auth errors, login failures
- [ ] Monitor PG resource usage (memory, CPU, disk growth — `_pg_changelog` table size)
- [ ] Monitor `_pg_changelog` write rate — should track 11.x's PG write rate
- [ ] Monitor hapihub error rate, pod restarts
- [ ] Monitor cadence — real users should generate sync activity now
- [ ] Periodically check `_pg_changelog` table size and consider truncating older rows once you're confident you won't need them for rollback (the changelog is operator-managed; the migrator does not auto-prune)
- [ ] Run periodic verification jobs against backups: `curl -X POST :3000/verify`
- [ ] Keep the rollback runbook warm — train an on-call to execute the manual replay path from memory

---

## Phase 8 — Tear down reverse-cdc triggers (the actual point of no return)

When you're ready to commit fully to 11.x and accept that rollback now means manual reconstruction without the changelog audit trail.

### Decision criteria

- Bake-in clean for 72+ hours
- No outstanding bug reports related to the migration
- PG metrics within projections
- `_pg_changelog` size is manageable; growth rate is known
- Stakeholders signed off
- A retry plan exists in case of catastrophic failure (full restore from PG backups)

### Steps

- [ ] Decide whether to archive `_pg_changelog` somewhere (S3/GCS) before teardown — once teardown happens you lose the per-row audit trail
- [ ] Tear down triggers: `curl -X POST http://localhost:3000/reverse-cdc/triggers/teardown` (port-forward into the migrator pod)
- [ ] Confirm via dashboard that triggers are gone
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
| 7 — Bake-in (reverse-cdc capture) | **72 h minimum** | No |
| 8 — Tear down reverse-cdc triggers | 30 min | No |
| 9 — Closure | 30 min | No |

**Total elapsed time: ~5–7 days** if everything goes smoothly.
**Production downtime: ~15–30 minutes** during the cutover step itself.
**Rollback safety**: maintained throughout phases 0–7 via the reverse-cdc forensic trail. Rollback after cutover requires manual replay (or accepting drift); Phase 8 teardown removes even that audit trail.

---

## Success criteria

- Production hapihub running 11.2.8, zero crash loops
- Auth error rate at or below 10.x baseline
- All smoke tests pass: login, password change, billing read, medical encounter read, new record creation
- PG sizing within projections (memory, CPU, disk)
- Forward CDC verification report shows all collections in pass/warn (no fails)
- Reverse-cdc triggers installed on the full allowlist; `_pg_changelog` writes track 11.x's PG write rate
- `_pg_changelog` table size growing within expected bounds (operator decides retention)
- No clinician reports of data loss or login problems beyond the expected re-login window
- 72h bake-in clean
- Phase 8 sign-off received before tearing down the triggers
