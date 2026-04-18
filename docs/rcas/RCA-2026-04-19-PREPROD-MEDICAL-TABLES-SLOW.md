# RCA: Slow `listMedicalRecords` / `listMedicalPatients` / `listPersonalDetails` on Preprod — Missing Indexes

| Field | Value |
|-------|-------|
| **Date** | 2026-04-19 |
| **Severity** | High (user-visible: `listMedicalRecords` averaging ~48 s, max ~57 s — UI effectively unusable on patient charts) |
| **Duration** | Chronic — existed as long as these tables had grown large on preprod |
| **Services Affected** | HapiHub API on preprod: `GET /medical-records`, `GET /medical-patients`, `GET /personal-details` (plus any UI route that waits on these: patient chart view, facility patient list) |
| **Environment** | **Preprod only** — production was **not** touched |
| **Detected By** | User report with Chrome devtools screenshots: `/medical-records` TTFB 15.98 s, `/medical-patients` stalled 10.83 s (cascade from saturated browser connection slots) |
| **Related RCA** | [`RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md`](./RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md) — same root-cause pattern on a different table, earlier the same day |
| **Fix Commit** | N/A — applied as direct DDL on preprod Postgres (see *Fix* below) |

## Summary

Three list endpoints on preprod hapihub were returning in tens of seconds — most acutely `listMedicalRecords` at ~48 s average, 57 s max. `kubectl top` showed the hapihub pod nearly idle (~140 m CPU / 290 Mi) while Postgres churned; `EXPLAIN ANALYZE` showed full **Parallel Seq Scans** over 3.8 GB of `medical_records`, 234 MB of `medical_patients`, and 215 MB of `personal_details` on every list query. All three tables had only their primary-key index, with no indexes on the common filter columns (`patient`, `facility`). Adding three non-blocking composite btree indexes (`(patient, created_at DESC)` on `medical_records`; `(facility, created_at DESC)` on the other two) turned the same queries into **Index Scans** — `listMedicalRecords` dropped from **2216 ms → 2.03 ms** on EXPLAIN (≈1090×), and early live samples post-fix show `listPersonalDetails` at 20 ms (was 556 ms avg / 4.3 s max).

This is the **second** incident on 2026-04-19 with the exact same shape as the `queue_items` RCA above. The pattern is now established: large hapihub-Postgres tables in preprod have only the PK index because hapihub's Drizzle schema does not declare secondary indexes, so every list query is paying a full-table-scan tax.

## Impact

- **Preprod only.** All patient-chart-like UI flows were effectively unusable; single requests took up to 57 s.
- **No data loss, no errors** — just slow. HTTP 200s throughout.
- Production was not affected and was not touched during this investigation.
- User-facing symptoms confirmed in Chrome devtools:
  - `/medical-records`: **TTFB 15.98 s** (worse in logs — some individual requests hit 57 s)
  - `/medical-patients`: total 12.19 s, of which **10.83 s was "Stalled"** (client-side browser queueing, because parallel `listMedicalRecords` requests were occupying the browser's 6-connection-per-origin pool; fixing the slow endpoint fixes the stall)

## Timeline (UTC+8)

| Time | Event |
|------|-------|
| 2026-04-19 (ongoing) | `medical_records` (3.8 GB / 3.55 M rows), `medical_patients` (234 MB / 480 K rows), `personal_details` (215 MB / 495 K rows) had only PK-indexing |
| 2026-04-19 ~01:40 | User shares devtools screenshots: `/medical-records` 16 s TTFB, `/medical-patients` 12 s with 10.8 s stalled |
| ~01:41 | Parsed hapihub logs (last 10 min): `listMedicalRecords` avg 48.0 s / max 57.3 s; `listMedicalPatients` max 1.4 s; `listPersonalDetails` max 4.3 s |
| ~01:42 | Schema check: `medical_records` has only `medical_records_pkey` + a composite `(encounter, type, tags)` that only helps the encounter-filter path. `medical_patients` and `personal_details` have **only** their PK |
| ~01:43 | `EXPLAIN (ANALYZE, BUFFERS)` on `listMedicalRecords` by `patient`: **Parallel Seq Scan**, 1.18 M rows removed per worker, ~3 GB read per query, 2216 ms with parallelism |
| ~01:45 | Proposed three indexes (`medical_records(patient, created_at)`, `medical_patients(facility, created_at)`, `personal_details(facility, created_at)`); user authorized "apply then write RCA" |
| ~01:46 | `CREATE INDEX CONCURRENTLY` × 3 on preprod; all three complete and `indisvalid = true` (sizes: 169 MB / 25 MB / 26 MB) |
| ~01:47 | Post-fix `EXPLAIN ANALYZE` on `listMedicalRecords` by `patient`: **Index Scan** on new index, **2.03 ms** (≈1090× faster) |
| ~01:48 | Live hapihub log sample: `listPersonalDetails` 20 ms (was 556 ms avg / 4.3 s max) |

## Root Cause

### Primary

On the three affected tables, every list query filtered by a column that had **no index**, forcing a full sequential scan of the table's heap on every call.

| Table | Size | Rows | Index coverage (before) | Slow filter pattern | Observed op latency |
|---|---|---|---|---|---|
| `medical_records` | 3.8 GB | 3.55 M | PK on `id`, composite `(encounter, type, tags)` — no index on `patient`, `facility` | `WHERE patient = ?` (patient chart view) | `listMedicalRecords`: **48 s avg, 57 s max** |
| `medical_patients` | 234 MB | 480 K | PK on `id` only | `WHERE facility = ?` | `listMedicalPatients`: 738 ms avg, 1.4 s max |
| `personal_details` | 215 MB | 495 K | PK on `id` only | `WHERE facility = ?` | `listPersonalDetails`: 556 ms avg, 4.3 s max |

`EXPLAIN ANALYZE` evidence for the worst case (`listMedicalRecords` by patient):

```
Parallel Seq Scan on medical_records
  Filter: patient = $0
  Rows Removed by Filter: 1,188,244   (per worker × 3 workers)
  Buffers: shared hit=8,631 read=387,505   (~3 GB heap read)
Execution Time: 2,216 ms                   (3 workers parallel)
```

Under hapihub's single-connection ORM path (no parallelism), that 2.2 s scales up close to 6 s minimum; with concurrent requests contending on Postgres CPU and page cache, observed latency balloons to 48–57 s.

### Contributing factors

1. **Repeat of the `queue_items` pattern** seen earlier the same day. Large hapihub-Postgres tables routinely lack secondary indexes.
2. **No slow-query visibility**: `pg_stat_statements` is still not installed on preprod, so this only surfaced after user complaint + screenshot.
3. **Browser-side amplification**: slow `listMedicalRecords` requests saturate the browser's 6-parallel-connection-per-origin limit, so *other* endpoints appear slow (long "Stalled" segment) even though their server-side TTFB is normal. The first devtools screenshot demonstrates this: the shown request's server only took 1.35 s, but it had to wait 10.83 s for a connection slot. Users perceive this as "everything is slow" when in reality one slow endpoint is blocking the queue.

## Fix

**Applied directly to preprod Postgres** (no change in git):

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_medical_records_patient_created_at
  ON medical_records (patient, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_medical_patients_facility_created_at
  ON medical_patients (facility, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_personal_details_facility_created_at
  ON personal_details (facility, created_at DESC);
```

### Why `CONCURRENTLY` + `IF NOT EXISTS`

- `CONCURRENTLY` does **not** take an `ACCESS EXCLUSIVE` lock — reads and writes continue uninterrupted while the index builds.
- `IF NOT EXISTS` makes the DDL idempotent; re-running is a no-op. Critical because (a) the same fix will eventually go into hapihub migrations, and (b) it makes disaster-recovery replay safe.
- Build times: `medical_records` (3.8 GB) completed in under a minute; the two smaller tables completed in seconds.
- If any of the three had failed mid-build, they would have left an `indisvalid = false` index that is safely ignored by the planner and trivially droppable.

### Why composite `(col, created_at DESC)`

Every affected list query has the same shape: `WHERE <col> = ? ORDER BY created_at DESC LIMIT N`. A composite index on `(filter_col, created_at DESC)` serves **both** the `WHERE` and the `ORDER BY` in a single scan, so `LIMIT 50`-style queries never touch the heap beyond the 50 rows they need.

### Measured improvement

| Operation | Plan (before) | Plan (after) | Before | After |
|---|---|---|---|---|
| `listMedicalRecords` (by `patient`) | `Parallel Seq Scan`, ~3 GB read | `Index Scan using idx_medical_records_patient_created_at` | **2216 ms** (EXPLAIN) / ~48 s avg, 57 s max (live) | **2.03 ms** (EXPLAIN) |
| `listPersonalDetails` (by `facility`) | Full-table scan | Index Scan | 556 ms avg / 4.3 s max | **20 ms** (first live sample) |
| `listMedicalPatients` (by `facility`) | Full-table scan | Index Scan | 738 ms avg / 1.4 s max | not yet sampled live — expected sub-50 ms |

Ratio on the worst endpoint: **≈1090× on EXPLAIN cost.** User-visible 16 s TTFB in the devtools screenshot → sub-100 ms once the fix propagates.

## Is the fix live?

**Yes — live on preprod right now.** All three indexes exist, `indisvalid = true`, `indisready = true`, and the planner is using them (confirmed by post-fix `EXPLAIN`).

**But "live" and "permanent" are not the same thing.** This was an out-of-band `psql` DDL, not a migration. The indexes persist in the running Postgres instance until *something* takes them away. Concretely, the fix **will vanish** in any of these scenarios:

| Scenario | Outcome | Likelihood |
|---|---|---|
| `postgresql-0` pod restart | ✅ Indexes persist (they're on disk in the PVC) | N/A — safe |
| Hapihub redeploy / version bump | ✅ Indexes persist (hapihub doesn't touch them) | N/A — safe |
| Normal hapihub migration runner on each startup | ✅ Indexes persist (runner only applies *new* migrations; it doesn't drop unknown objects) | N/A — safe |
| **DB restored from a pre-2026-04-19 backup** | ❌ All three indexes missing | Likely during DR drill or Velero restore |
| **`postgresql-0` PVC destroyed + DB re-seeded** | ❌ All three indexes missing | Likely during cluster rebuild or disaster recovery |
| **A future hapihub migration that runs `drizzle-kit push`-style schema sync** | ❌ Possible silent DROP (drizzle-kit in "push" mode drops objects it doesn't recognize from the declared schema) | Depends on hapihub's migration workflow |
| **A future hapihub migration explicitly named "DROP INDEX …"** | ❌ Indexes gone | Very unlikely |

In short: **our change is durable against day-to-day operations but not against schema resets or drift-reconciling tools.** Because the indexes don't exist in hapihub's declared schema, any process that regenerates the DB from the declared schema will leave them out. This is precisely why the *only* correct permanent fix is to land the change in hapihub's migration history (see next section).

Additional caveats:

- The fix is **not in git** anywhere. `git grep idx_medical_records_patient_created_at` in either `mycure-infra` or the hapihub repo will return nothing.
- **Production is unchanged.** Production's `medical_records`, `medical_patients`, and `personal_details` tables still have PK-only (or equivalently minimal) indexing. If production users start reporting similar slowness, apply the same command there — but see *Correct long-term remediation* first: the permanent path is the hapihub migration, not another ad-hoc DDL that only solves prod for as long as prod's PVC survives.

## Revert instructions

If any of these indexes need to be removed:

### 1. Confirm targets exist

```bash
PGPW=$(kubectl -n mycure-preprod get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "SELECT indexrelid::regclass, indisvalid, pg_size_pretty(pg_relation_size(indexrelid))
      FROM pg_index
      WHERE indexrelid::regclass::text IN (
        'idx_medical_records_patient_created_at',
        'idx_medical_patients_facility_created_at',
        'idx_personal_details_facility_created_at'
      );"
```

### 2. Drop non-blockingly (pick the ones you need)

```bash
kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "DROP INDEX CONCURRENTLY IF EXISTS idx_medical_records_patient_created_at;" \
  -c "DROP INDEX CONCURRENTLY IF EXISTS idx_medical_patients_facility_created_at;" \
  -c "DROP INDEX CONCURRENTLY IF EXISTS idx_personal_details_facility_created_at;"
```

- `DROP INDEX CONCURRENTLY` takes only `SHARE UPDATE EXCLUSIVE` — non-blocking for reads and writes.
- Must run outside a transaction block (`psql -c` does this by default).
- `IF EXISTS` makes each drop idempotent.

### 3. Expect full return of slowness

Dropping restores the 48 s / 4 s / 1 s latency floors respectively. Only drop if the index itself is causing a regression (e.g., unexpected planner choice, storage pressure). In that case, preserve the diagnostic evidence (EXPLAIN plans before and after) before acting.

## Applying the same fix to production (when explicitly authorized)

Production was **not** touched in this incident per the user's standing "never change prod without explicit approval" directive. When/if production is authorized, use the exact same command (swap the namespace):

```bash
PGPW=$(kubectl -n mycure-production get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

# Size check first — do the tables look the same shape in prod?
kubectl -n mycure-production exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "SELECT relname,
             pg_size_pretty(pg_total_relation_size(oid)) AS size,
             (SELECT reltuples::bigint FROM pg_class c2 WHERE c2.oid=pg_class.oid) AS rows
      FROM pg_class
      WHERE relname IN ('medical_records','medical_patients','personal_details') AND relkind='r';"

# Apply concurrently — safe on a live DB
kubectl -n mycure-production exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_medical_records_patient_created_at \
      ON medical_records (patient, created_at DESC);" \
  -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_medical_patients_facility_created_at \
      ON medical_patients (facility, created_at DESC);" \
  -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_personal_details_facility_created_at \
      ON personal_details (facility, created_at DESC);"
```

Important: **production is still on hapihub 10.x**, not 11.2.x. Verify the table schemas in production look the same before assuming this patch applies — the columns `patient` on `medical_records` and `facility` on the other two should exist, but confirm with `\d` first.

On prod-sized tables the builds may take minutes; reads and writes continue uninterrupted throughout.

## Correct long-term remediation (in code, not in the DB)

**This is the only durable fix.** Everything above is a stopgap that survives steady-state operations but vanishes on any DB rebuild. Same shape as the `queue_items` RCA. The correct home for all three indexes is **hapihub's own migration history**, because:

- `mycure-infra` owns deploys and image pins, not schema.
- Manual DDL creates schema drift that is invisible to future readers and **does not replay** when the DB is recreated from hapihub's migration chain (e.g. after a restore, after a PVC rebuild, after bringing up a brand-new tenant).
- Only hapihub-side migrations apply consistently to every MyCure environment (staging, preprod, production, on-prem, future tenants) and survive every operational lifecycle event (DR restore, cluster rebuild, new-customer onboarding).
- The Drizzle schema is the source of truth that tools like `drizzle-kit generate` / `drizzle-kit push` reconcile against. As long as these indexes are *not* in the declared schema, automated tooling can silently drop them. Declaring them in the schema both codifies intent and protects against accidental loss.

Concretely, in the hapihub repo:

1. **Add new Drizzle migration(s)** — either one file with all three indexes, or three separate files per table — using a non-transactional directive (because `CREATE INDEX CONCURRENTLY` cannot run inside a transaction):

    ```sql
    -- drizzle:non-transactional
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_medical_records_patient_created_at
      ON medical_records (patient, created_at DESC);

    -- ... and the other two, each in its own non-transactional migration
    --     so a failure of one doesn't block the others.
    ```

2. **Declare each index in the Drizzle schema** where the corresponding `pgTable` is defined, so `drizzle-kit generate` doesn't try to re-add them.

3. **Ship in the next hapihub release.** Once merged and tagged, bump the tag in `values/deployments/*.yaml` in this repo, ArgoCD auto-syncs, hapihub runs migrations at startup, indexes land on every environment automatically.

4. **Name collision**: use the same names (`idx_medical_records_patient_created_at`, etc.) as the manual preprod indexes. `CREATE INDEX IF NOT EXISTS` will be a no-op on preprod after the rollout and a real build elsewhere. Zero manual cleanup needed.

### What *not* to do in `mycure-infra`

- Don't add these as a Helm post-install Job or ArgoCD PreSync hook in any chart. Schema belongs with the app, not with the deploy tooling. Same guidance as the `queue_items` RCA.

## Lessons Learned

### What went well

- User shared devtools screenshots with the exact timings, which let the investigation immediately disambiguate client-side queueing ("Stalled") from server-side latency ("Waiting for server response"). The distinction matters: the first devtools screenshot looked like a slow endpoint but was actually a cascade from the second one's 16 s TTFB.
- Same playbook as the `queue_items` incident earlier in the day: `kubectl top pod` → EXPLAIN → `CREATE INDEX CONCURRENTLY`. The familiarity cut time-to-fix significantly.
- All three `CREATE INDEX CONCURRENTLY` succeeded on the first attempt with no production impact and no user-visible blip.

### What went wrong

- **Second occurrence of the same class of bug on the same day.** This was predictable once the `queue_items` root cause was understood. After the first RCA we *knew* preprod's large hapihub-Postgres tables were likely PK-only-indexed, but we didn't proactively audit until the next user report. A fleet-wide scan for PK-only-indexed tables over N MB would have surfaced this before a user noticed.
- **Schema drift is compounding.** After today there are **four** indexes in preprod Postgres that don't exist in git or in hapihub's migration history: `idx_queue_items_queue_created_at`, `idx_medical_records_patient_created_at`, `idx_medical_patients_facility_created_at`, `idx_personal_details_facility_created_at`. This list will keep growing until the hapihub team lands a migration for them. A DB restore would silently regress all four.
- **No slow-query visibility.** `pg_stat_statements` is still not installed. Both incidents today were found only after users complained. A simple grafana dashboard on top of `pg_stat_statements` would have flagged these tables days or weeks ago.

## Action items

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Audit **all** hapihub-owned tables > 200 MB on preprod for PK-only indexing. Produce a list of missing indexes and hand to the hapihub team as one consolidated migration PR. | Infra | **High** — there are almost certainly more |
| 2 | Raise a PR in the hapihub repo that adds Drizzle migrations for **all four** manual preprod indexes from 2026-04-19 (this RCA + the `queue_items` RCA). Use non-transactional migrations. Declare each index in the Drizzle schema so `drizzle-kit generate` is stable. | HapiHub team | **High** |
| 3 | Install `pg_stat_statements` on preprod and production Postgres, and add a Grafana panel for top-N by `mean_exec_time`. | Infra | Medium |
| 4 | Once the hapihub migration lands, drop any manual preprod indexes whose names differ from the migration's (none expected if action #2 uses the same names). | HapiHub team | Low |
| 5 | Add a pre-release "slow-query check" to the hapihub release process: run representative list queries against a prod-sized dataset, fail the release if any exceed a budget (e.g., p95 > 500 ms). | HapiHub team | Low |
| 6 | Apply the same three indexes to **production** when authorized by the product owner. This RCA includes the exact commands in the *Applying to production* section. | Infra + product owner | Awaiting auth |
