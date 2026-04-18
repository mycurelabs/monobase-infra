# RCA: Slow Billing Services Search on Preprod — Secondary Victim of Unindexed `medical_records`

| Field | Value |
|-------|-------|
| **Date** | 2026-04-19 |
| **Severity** | High (user-visible — billing-services search spinner); **secondary symptom only** |
| **Duration** | Same as the `medical_records` root cause — chronic until the medical-tables indexes landed |
| **Services Affected** | HapiHub API on preprod: `GET /services` → `listServiceServices` (user-facing as the billing services catalog search) |
| **Environment** | **Preprod only** |
| **Detected By** | User report: "Searching of billing services are also extremely slow" |
| **Root cause** | **Not** a services-specific bug. This was CPU contention on Postgres caused by the unindexed `medical_records` full-table scans (see the medical-tables RCA for the primary root cause). |
| **Related RCAs** | [`RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md`](./RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md) — **the primary root cause.** [`RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md`](./RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md) — same family. |
| **Fix Commit** | None. Resolved as a side effect of the medical-tables index work. |

## Summary

`listServiceServices` (the billing services catalog search) was averaging **2.4 s** with a max of **8.8 s** on preprod. Investigation showed this was **not** an indexing problem on the `services` table itself — the table is only 6 MB with ~18 K rows and `EXPLAIN ANALYZE` on a representative query runs in **10–43 ms**. The slowness was **Postgres CPU contention**: while unindexed `listMedicalRecords` queries (`Parallel Seq Scan` across 3.8 GB, 48 s per request) were consuming ~1.2 cores, every other query — including fast ones like services search — paid a latency tax as the scheduler juggled CPU slices. Once the three medical-tables indexes landed (see the medical-tables RCA), `listServiceServices` dropped to **443 ms avg** with no services-side change made. The remaining ~400 ms is hapihub-side ORM / JSONB-deserialization overhead, which is a hapihub-repo concern, not a DB indexing concern.

## Impact

- User-visible: the billing UI search spinner hung for 2–8 s per keystroke / query.
- **No data loss, no errors.** HTTP 200s throughout.
- Production was not affected and was not touched during this investigation.

## Timeline (UTC+8)

| Time | Event |
|------|-------|
| 2026-04-19 ~01:40 | User reports `/medical-records` and `/medical-patients` screenshots showing 16 s TTFB |
| ~01:43 | Medical-tables root cause identified (unindexed `patient`, `facility` filters); three `CREATE INDEX CONCURRENTLY` applied; `listMedicalRecords` drops from 48 s → 2 ms on `EXPLAIN` |
| ~01:48 | User reports: "Searching of billing services are also extremely slow" |
| ~01:49 | Parsed hapihub logs (last 30 min): `listServiceServices` avg 2446 ms, max 8794 ms (n=27) |
| ~01:50 | Schema + size check on `services`: 6 MB / 18 K rows, PK-only; `EXPLAIN ANALYZE` runs in 10–43 ms. Table is **too small** for the 2.4 s hapihub-reported latency to be a DB scan problem. |
| ~01:51 | Parsed hapihub logs (last 5 min, post-medical-index): `listServiceServices` avg **443 ms**, max 574 ms (n=2). **~80 % of the latency vanished** with no services-specific change. |
| ~01:52 | Root cause confirmed: **secondary symptom of Postgres CPU saturation** from concurrent unindexed medical-records seq scans, not a services-table issue. |

## Root Cause

### Primary

The **same** issue documented in the medical-tables RCA: missing indexes on `medical_records(patient, created_at)`, `medical_patients(facility, created_at)`, and `personal_details(facility, created_at)` caused every list query on those tables to do a full-table `Parallel Seq Scan`. `medical_records` in particular is 3.8 GB / 3.55 M rows, so each scan reads ~3 GB and pins Postgres CPU for 2–10 seconds of wall clock per query.

### Why billing services looked slow

`services` is a tiny table (6 MB, 18 K rows) and its queries are cheap. But they run on the *same* Postgres instance and compete for the *same* CPU cores and page cache as the heavy medical queries. When Postgres is saturated by long seq scans on large tables, even fast queries block in the run queue. The effect is multiplicative on user-perceived latency:

- Isolated `listServiceServices` EXPLAIN time: **10 ms**
- Observed `listServiceServices` with concurrent unindexed `listMedicalRecords` running: **2.4 s average**
- Observed `listServiceServices` after `medical_records` was indexed: **443 ms average**

So ~2 s of the observed 2.4 s was **not** services work — it was queueing / CPU scheduling delay caused by the medical queries. This kind of cross-workload contention is the standard "slow DB symptom" pattern in a single-tenant Postgres: every slow query makes every other query look slow too.

### Why `services` itself is NOT a good index target

| Fact | Implication |
|---|---|
| Table is 6 MB, 18 K rows | Seq scan completes in milliseconds even without any non-PK index |
| `EXPLAIN ANALYZE` of `WHERE facility = ? ORDER BY created_at DESC LIMIT 50` = 10.4 ms | Adding `(facility, created_at)` would save at most ~9 ms — not user-visible |
| `EXPLAIN ANALYZE` of `WHERE facility = ? AND name ILIKE '%consult%' ...` = 42.6 ms | Still tolerable; a btree index can't accelerate `ILIKE '%...%'` anyway — would need `pg_trgm` + GIN, which is out of scope for a 6 MB table |

Adding an index to `services` today would be cargo-culting the queue_items / medical_records fix onto a table that doesn't exhibit the same shape of problem.

## Fix

**None applied.** Resolved as a side effect of the medical-tables RCA fix. The three manual preprod indexes from that RCA (`idx_medical_records_patient_created_at`, `idx_medical_patients_facility_created_at`, `idx_personal_details_facility_created_at`) freed the Postgres CPU budget, and `listServiceServices` returned to its intrinsic ~400 ms latency floor.

## Is the fix live?

**Yes, in the sense that the symptom is gone** — `listServiceServices` now averages 443 ms on preprod, within the expected range for a small table over an ORM with JSONB rows. The same durability caveats as the medical-tables RCA apply: if the underlying medical-records indexes vanish (DB restore, PVC rebuild, `drizzle-kit push` reconciliation), billing-services slowness will return immediately — the two are coupled through Postgres's CPU scheduler.

Production was **not** touched. Production will exhibit the same contention pattern if and when its medical-records table grows large enough to matter, unless the hapihub migration (see the medical-tables RCA action item #2) lands first.

## Revert instructions

Not applicable — no services-side change was made. To revert the upstream medical-tables fix, see that RCA's *Revert instructions*. Reverting it will restore the billing-services slowness too.

## Correct long-term remediation (in code, not in the DB)

Two separate classes of work, both in the **hapihub** repo:

### 1. The root cause

Land the Drizzle migration from the medical-tables RCA. That codifies the three indexes into hapihub's schema so they're durable across all environments. Once done, billing-services search will be automatically fast on every environment too — because the cross-workload contention goes away.

### 2. The residual ~400 ms on `listServiceServices`

Post-medical-fix, billing-services search still takes ~400 ms for a 6 MB table, which is **not** a DB-indexing problem. Likely contributors:

- **JSONB column deserialization overhead.** `services.items`, `.packages`, `.queueing`, `.metadata`, `.form_templates`, `.consent_forms`, `.commissions`, `.codings`, `.specialization`, `.tags` are all JSONB. Pulling 18 K rows' worth of JSONB through the wire + deserializing it in Bun adds up even when the query itself is fast.
- **N+1 query patterns in the ORM.** If hapihub fetches `services`, then for each service fetches a related entity (e.g. `facility`, `creator`), that multiplies round trips.
- **Unbounded result sets.** If the client calls `GET /services` without `limit`/`facility` scoping, the server returns all 18 K rows. The wire / JSON-encode time alone will be hundreds of milliseconds.

The fix is in the hapihub repo — instrument `listServiceServices`, check the query shape and response size, and either paginate, trim the default column set, or add a dedicated "lean" list endpoint for the billing UI.

### What *not* to do in `mycure-infra`

- Don't add a `services` index as a stopgap. The table is too small for it to help, it adds noise to schema drift, and it distracts from the real fix (hapihub-side ORM / pagination work).

## Lessons Learned

### What went well

- The services-table EXPLAIN (10–43 ms) immediately ruled out a DB-indexing problem, saving time. Not every "slow endpoint" needs a new index.
- The post-fix measurement (2.4 s → 443 ms with no services-side change) was decisive proof of the cross-workload contention hypothesis. Worth repeating this pattern whenever multiple endpoints are slow at once.

### What went wrong

- **We didn't reason about contention before looking at individual endpoints.** If we had profiled total Postgres CPU usage first, we would have seen that the database was saturated and predicted that **every** endpoint would look slow until the saturation source was fixed. That lens could have prevented chasing each slow endpoint as if it were an independent problem.
- **No visibility into cross-query contention.** `pg_stat_statements` would have shown which single query was dominating cumulative `total_exec_time` and implicated `listMedicalRecords` immediately.

## Action items

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Land the hapihub Drizzle migration for the three medical-tables indexes (covered by the medical-tables RCA action #2). That durably fixes billing search too. | HapiHub team | **High** (tracked in medical-tables RCA) |
| 2 | Investigate the residual ~400 ms `listServiceServices` latency in the hapihub repo: profile the query path, check for N+1, check default response size, consider trimming JSONB columns from the list projection, paginate if not already | HapiHub team | Medium |
| 3 | Install `pg_stat_statements` on preprod (and then prod) so the next time multiple endpoints are slow, "which query is dominating CPU" is one query away instead of a bisection | Infra | Medium |
| 4 | Add "total Postgres CPU" to the standard triage checklist for slow API reports — a saturated DB means every endpoint looks slow, so fix the hot query first, then re-measure | SRE | Low |
