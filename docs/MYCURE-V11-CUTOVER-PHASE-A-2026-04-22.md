# MyCure v11 Cutover — Phase A (Completed)

**Date:** 2026-04-22
**Status:** ✅ Live in production
**Fix commit:** `20d32a3` (Reapply "feat(prod): add hapihubNext (v11) release on hapihub-next.localfirsthealth.com")
**Related RCAs:**
- [`docs/rcas/RCA-2026-04-22-HAPIHUB-0014-MIGRATION-BLOCKING-INDEX-BUILD.md`](rcas/RCA-2026-04-22-HAPIHUB-0014-MIGRATION-BLOCKING-INDEX-BUILD.md)
- [`docs/rcas/RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md`](rcas/RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md) and siblings

---

## Executive summary

Deployed **hapihub v11.2.20** on a new temporary domain (`hapihub-next.localfirsthealth.com`) alongside the existing hapihub v10.11.15 release in production, and bumped the **mycure frontend to v10.6.5** pointed at the new backend. The existing canonical URL `hapihub.localfirsthealth.com` (used by mycurev8) was **not touched** — it continues to serve v10. This is the reversible, additive half of a two-phase cutover; Phase B (canonical URL swap) is pending (see `docs/MYCURE-V11-CUTOVER-PENDING.md`).

To unblock the deploy, we also **archived and deduplicated four Postgres history tables** (≈1.16 M rows deleted from live tables, full copies preserved in archive tables).

---

## Target architecture

```
                       ┌───────────────────────────┐
  mycurev8 (v8.x)  ──▶ │  hapihub.localfirsthealth │ ───▶ hapihub v10.11.15 (MongoDB + Postgres)
  (unchanged)          │       .com (canonical)    │
                       └───────────────────────────┘

                       ┌────────────────────────────────┐
  mycure v10.6.5  ──▶  │  hapihub-next.localfirsthealth │ ───▶ hapihub v11.2.20 (Postgres-only)
  (new frontend)       │       .com (temporary)         │
                       └────────────────────────────────┘
```

Two hapihub Helm releases, same Postgres primary, same namespace.

---

## Timeline (UTC+8)

| Time | Event |
|------|-------|
| Before today | Prod ran hapihub v10.11.15 as the only backend. Postgres had been populated from MongoDB by a live migration script. |
| ~20:00 | Decision: move canonical behavior unchanged; stand up v11 as a second release on a temp hostname. |
| ~20:30 | Branch `feat/hapihub-legacy-rehearsal` created; skeleton ArgoCD template added (commit `c71d832`), renamed to `hapihub-next` (`065613b`). |
| ~21:00 | Prod values file edited: new `hapihubNext:` block added, `mycure:` bumped to 10.6.5 + API URL repointed (commit `4a24f07`). |
| ~21:30 | First merge attempt. Merged to main as fast-forward, pushed. |
| ~21:35 | ArgoCD materialized `mycure-production-hapihub-next` app. First hapihub-next pod started, hit Drizzle migration `0010_history_pk_swap` pre-flight check → crashed with "personal_details_history has 76684 duplicate id(s)". |
| ~21:40 | Immediate revert (`958c8f4`) pushed. mycure rolled back to `1.0.0-offline` with canonical API URL. `hapihub-next` resources pruned. |
| ~21:45–22:30 | Investigation: read `0010_history_pk_swap.sql` docstring, counted duplicates across all 4 history tables (1.16 M total), confirmed which features read these tables (only RIS/LIS and PME amendment-trail views), decided on archive-then-dedupe approach. |
| ~22:45 | Phase 1 executed on prod Postgres: 4 archive tables created, 4 dedupes run. All rows counted and verified. |
| ~22:50 | Final dedupe sweep: 0 rows deleted (no new duplicates had accumulated since Phase 1). |
| ~22:55 | Revert reverted (`20d32a3`), pushed. |
| ~23:00 | ArgoCD re-materialized `hapihub-next`. First pod Running + Ready in ~25 s — migrations applied cleanly. |
| ~23:00–23:10 | `pg-concurrent-migrator` built the 6 stopgap indexes (and the 5 FTS indexes from `0012`/`0013`). Some hapihub-next pod restarts (1-3 each) from replica race on `CREATE INDEX CONCURRENTLY` — all indexes eventually valid. |
| ~23:10 | All 4 ArgoCD apps Synced + Healthy. mycure v10.6.5 Running + Ready on `mycure.localfirsthealth.com`. |

---

## What was changed

### Postgres (`mycure-production` namespace)

**Archive tables created** (4 tables, ≈2 GB total):
```sql
CREATE TABLE personal_details_history_archive_20260422       AS TABLE personal_details_history;
CREATE TABLE diagnostic_order_tests_history_archive_20260422 AS TABLE diagnostic_order_tests_history;
CREATE TABLE inventory_stocks_history_archive_20260422       AS TABLE inventory_stocks_history;
CREATE TABLE medical_records_history_archive_20260422        AS TABLE medical_records_history;
```

**Live tables deduplicated** (per-table `DELETE ... WHERE rn > 1` using `ROW_NUMBER() OVER (PARTITION BY id ORDER BY _h_created_at DESC NULLS LAST)`):

| Table | Before | Deleted | After |
|---|---|---|---|
| `personal_details_history` | 271,032 | 105,965 (39%) | 165,067 |
| `diagnostic_order_tests_history` | 11,103 | 3,032 (27%) | 8,071 |
| `inventory_stocks_history` | 1,033,427 | 1,019,020 (99%) | 14,407 |
| `medical_records_history` | 752,473 | 36,583 (5%) | 715,890 |
| **Total** | 2,068,035 | **1,164,600** | 903,435 |

Deleted rows were **older audit trail entries**. For each source record, only the latest audit entry (by `_h_created_at`) was retained. Archive tables contain the full pre-dedupe state.

**Important caveat on the deleted data:** per the amendment-trail query logic in `pg-service.ts` (commit `1e786954`), the new app queries history using `WHERE _record = <source_id>`. Pre-cutover rows stored source IDs in `id`, not `_record`. So the deleted rows were **already effectively invisible to the v11 app** — dedupe brought the DB into schema compliance for data the app wouldn't have read anyway. The archive preserves them for compliance / direct-SQL queries.

### Git repo (`mycure-infra`)

Four commits on `main`:

```
20d32a3 Reapply "feat(prod): add hapihubNext (v11) release on hapihub-next.localfirsthealth.com"
958c8f4 Revert   "feat(prod): add hapihubNext (v11) release ..."
4a24f07 feat(prod): add hapihubNext (v11) release on hapihub-next.localfirsthealth.com
065613b refactor(argocd): rename hapihub-legacy template to hapihub-next
c71d832 feat(argocd): add hapihub-legacy app template (inert skeleton)
```

The revert/reapply pair is the audit trail of the first failed attempt.

Files touched:
- `argocd/applications/templates/hapihub-next.yaml` — new ArgoCD Application template gated on `(.Values.hapihubNext | default dict).enabled`. Deploys the existing `charts/hapihub` chart with `releaseName: hapihub-next`.
- `values/deployments/mycure-production.yaml`:
  - **NEW `hapihubNext:` block** (≈150 lines). Mirrors existing `hapihub:` with four deliberate differences: `image.tag: "11.2.20"`, hostname `hapihub-next.localfirsthealth.com` (only), no `additionalSectionNames`, `mongodb.enabled: false` (v11 is Postgres-only).
  - **`mycure:` block bumped**: `image.tag: "1.0.0-offline"` → `"10.6.5"`, `config.API_URL` / `HAPIHUB_URL` → `hapihub-next.localfirsthealth.com`.

### Kubernetes (`mycure-production` namespace)

Resources created by ArgoCD as a result of the commit:
- `Deployment/hapihub-next` (3 pods, image `ghcr.io/mycurelabs/hapihub:11.2.20`)
- `Service/hapihub-next`
- `HTTPRoute/hapihub-next` → hostname `hapihub-next.localfirsthealth.com`
- `ConfigMap/hapihub-next`
- `Secret/hapihub-next` (synced by ExternalSecret from GCP Secret Manager)
- `HorizontalPodAutoscaler/hapihub-next` (min 3 / max 5)

Resources rolled (not created):
- `Deployment/mycure` — rolled from tag `1.0.0-offline` to `10.6.5`, env vars `API_URL` / `HAPIHUB_URL` repointed.

### Drizzle migrations applied

`drizzle.__drizzle_migrations` table grew from **8 rows to 13 rows** (5 new migrations). In order:

| ID | File | What it did on prod |
|---|---|---|
| 9 | `0009_pg_changelog.sql` | Added `_pg_changelog_capture()` function + triggers for CDC. |
| 10 | `0010_history_pk_swap.sql` | Swapped PK on the four `*_history` tables from `_record` to `id`. **Only succeeded because we had pre-deduped the live tables.** |
| 11 | `0011_bright_blazing_skull.sql` | Small schema change (name-only placeholder; contents not audited here). |
| 12 | `0012_patient_search_indexes.sql` | Added 5 GIN tsvector FTS indexes for patient search (firstname, lastname, email, mobile_no, external_id). Built non-concurrently — took `ACCESS EXCLUSIVE` on `personal_details` and `medical_patients` for the duration of the build. No user-visible outage because these tables are small on prod. |
| 13 | `0013_patient_search_middle_name.sql` | Added `personal_details_middlename_fts` GIN index. Same pattern as 0012. |
| 14 | `0014_preprod_missing_indexes.sql` | **No-op stub** (per hapihub team's fix after our [2026-04-22 RCA](rcas/RCA-2026-04-22-HAPIHUB-0014-MIGRATION-BLOCKING-INDEX-BUILD.md)). The actual index creation is done out-of-transaction by `pg-concurrent-migrator.ts` — see below. |

### Indexes created by `pg-concurrent-migrator`

Runs after migrations, outside Drizzle's transaction envelope, using `CREATE INDEX CONCURRENTLY IF NOT EXISTS`. Non-blocking for reads and writes on prod.

| Index | Table | Size | Status |
|---|---|---|---|
| `idx_queue_items_queue_created_at` | `queue_items` | 51 MB | ✅ Valid |
| `idx_medical_records_patient_created_at` | `medical_records` | 169 MB | ✅ Valid |
| `idx_medical_patients_facility_created_at` | `medical_patients` | 25 MB | ✅ Valid |
| `idx_personal_details_facility_created_at` | `personal_details` | 26 MB | ✅ Valid |
| `idx_insurance_coverages_contract` | `insurance_coverages` | 392 KB | ✅ Valid |
| `idx_notifications_viewers_gin` | `notifications` (GIN, `jsonb_path_ops`) | 3.8 MB | ✅ Valid |

All six were originally ad-hoc DDL applied to preprod on 2026-04-19 and 2026-04-20 (see the preprod slowness RCAs). They're now codified in hapihub's migration pipeline and automatically apply on any fresh DB. Prod gained them as a side effect of this deploy.

---

## Current state verification

```
$ kubectl -n argocd get app | grep mycure-production
mycure-production-hapihub             Synced    Healthy
mycure-production-hapihub-next        Synced    Healthy
mycure-production-mycure              Synced    Healthy
mycure-production-mycurev8            Synced    Healthy
  (+ all other mycure-production-* apps Synced Healthy)

$ kubectl -n mycure-production get pods -l 'app.kubernetes.io/name in (hapihub,mycure)'
hapihub-5f85b78d5-*             (5 pods, 10.11.15, all Ready)
hapihub-next-846d8b78bc-*       (3 pods, 11.2.20, all Ready)
mycure-86bd8dc745-*             (1 pod, 10.6.5, Ready)
```

`hapihub.localfirsthealth.com` → v10 (unchanged).
`hapihub-next.localfirsthealth.com` → v11 (new).
`mycure.localfirsthealth.com` → v10.6.5 calling the new URL.
`mycurev8.localfirsthealth.com` → unchanged, calling canonical v10.

No user-visible break occurred. mycurev8 users saw zero change. mycure users got upgraded to 10.6.5 within seconds of the rollout (rolling update kept a Ready pod at all times).

---

## Gotchas encountered during execution

### 1. First deploy attempt failed at migration 0010

The migration is intentionally designed to fail-fast if any of the four `*_history` tables have duplicate `id` values. It does, because the prod data inherited from MongoDB had duplicate IDs (about 1.16 M rows' worth). This was not documented anywhere we could pre-check — we discovered it only when the pod crash-looped.

**Recovery**: immediate `git revert` of `4a24f07`. ArgoCD pruned `hapihub-next` resources and rolled `mycure` back to `1.0.0-offline`. mycurev8 users unaffected throughout.

**Prevention for future similar deploys**: before pushing a hapihub major-migration deploy, read the migration files in `drizzle-pg/` for any explicit `RAISE EXCEPTION` pre-flight checks and run them manually against prod as a dry-run.

### 2. Compliance / audit-trail consideration for dedupe

The 1.16 M deleted rows are audit trail entries. For a healthcare system this is regulatorily sensitive. We took the **archive-then-dedupe** path (option B) — the archive tables preserve the full pre-dedupe data in-DB, queryable via direct SQL, ready for cold-storage export. The live tables only have the most recent audit entry per source record.

Important nuance discovered during investigation: because of the `id` / `_record` column semantic flip in hapihub commit `1e786954`, **pre-cutover amendments stored the source ID in `id` but the new app queries using `_record`** — meaning the deleted rows were effectively invisible to the v11 app anyway. The dedupe is about schema hygiene, not about deleting data users would otherwise see.

The two user-facing features that read history tables (`useOrderTestAmendments` in RIS/LIS workspaces, `fromRawMedicalRecordAmendment` in PME report workspace) effectively **reset at cutover** — pre-cutover amendments won't appear in either UI after the upgrade. This is a property of the upgrade, not of the dedupe.

### 3. `pg-concurrent-migrator` race on multi-replica startup

All three `hapihub-next` replicas started roughly in parallel and each invoked `pg-concurrent-migrator`, which runs `CREATE INDEX CONCURRENTLY IF NOT EXISTS` for each of the 6 stopgap indexes. Two replicas raced on the same index name, and one `CREATE INDEX` errored (left an `indisvalid = false` entry), triggering a pod restart. On retry the migrator runs `DROP INDEX CONCURRENTLY` then `CREATE INDEX CONCURRENTLY` — which eventually converges.

Visible symptom: `hapihub-next` pods show 1–3 restarts (cosmetic). All indexes ended up valid.

**Recommendation to hapihub team**: wrap `pg-concurrent-migrator` in a `pg_advisory_lock` so only one replica at a time attempts index builds. Noted as a followup in `docs/MYCURE-V11-CUTOVER-PENDING.md`.

---

## Rollback options still available

| Operation | What it does | Data impact |
|---|---|---|
| `git revert 20d32a3` | Removes `hapihubNext:` block, rolls `mycure` back to `1.0.0-offline` + canonical URL. | None on v11 side. Any writes mycure v10.6.5 → v11 → Postgres remain in Postgres (and presumably flow back to Mongo via the migration sync script). |
| `DROP INDEX CONCURRENTLY` on any of the 6 stopgap indexes | Restores seq-scan behavior on that query path. | None. |
| `DROP TABLE *_history_archive_20260422` | Reclaims ~2 GB of PVC disk. | **Loses the audit-trail archive** — only do this after cold-storage export is verified. |
| Restore deleted rows from archive | `INSERT INTO <table> SELECT * FROM <table>_archive_20260422 WHERE id IN (...)` (or similar scoped query) | Brings back deleted audit entries. Would violate the `id` PK constraint — only feasible if you first drop-and-reseed the `id` PK or restore to a differently-named table. |

`hapihub.localfirsthealth.com` → v10 never changed backend. mycurev8 users never noticed anything. This Phase A has low blast radius — even a full revert is a few-minute operation.

---

## What lives where

| Component | Location |
|---|---|
| This doc | `docs/MYCURE-V11-CUTOVER-PHASE-A-2026-04-22.md` |
| Pending items for Phase B + cold storage export | `docs/MYCURE-V11-CUTOVER-PENDING.md` |
| Related RCAs | `docs/rcas/RCA-2026-04-{19,22}-*.md` |
| ArgoCD template for the sibling release | `argocd/applications/templates/hapihub-next.yaml` |
| The `hapihubNext:` values block | `values/deployments/mycure-production.yaml` lines ~252–408 |
| Archive tables | prod Postgres, `public.*_history_archive_20260422` (4 tables) |
