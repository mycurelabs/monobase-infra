# RCA: Hapihub Post-Cutover — Systematic Scan Reveals Remaining Index Gaps + Hot ORM Paths

| Field | Value |
|-------|-------|
| **Date** | 2026-04-23 |
| **Severity** | Medium (no outage, continued elevated latencies on several user-facing endpoints in prod v11) |
| **Status** | Open — infra can apply stopgap indexes on preprod/prod; permanent fix requires hapihub-side migrations + code |
| **Scope** | Production `mycure-production` running hapihub `11.2.20` on `hapihub-next.localfirsthealth.com`; also preprod for validation |
| **Detected by** | Systematic scan of `pg_stat_user_tables` + cross-reference with hapihub operation latencies (2-hour log window on both envs) |
| **Related RCAs** | [`RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md`](./RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md), [`RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md`](./RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md), [`RCA-2026-04-19-PREPROD-NOTIFICATIONS-LIST-SLOW.md`](./RCA-2026-04-19-PREPROD-NOTIFICATIONS-LIST-SLOW.md), [`RCA-2026-04-19-PREPROD-BILLING-INVOICES-N-PLUS-1.md`](./RCA-2026-04-19-PREPROD-BILLING-INVOICES-N-PLUS-1.md), [`RCA-2026-04-22-HAPIHUB-0014-MIGRATION-BLOCKING-INDEX-BUILD.md`](./RCA-2026-04-22-HAPIHUB-0014-MIGRATION-BLOCKING-INDEX-BUILD.md) |
| **Cutover context** | See [`docs/MYCURE-V11-CUTOVER-PHASE-A-2026-04-22.md`](../MYCURE-V11-CUTOVER-PHASE-A-2026-04-22.md) |

---

## Why this document exists

Hapihub v11.2.20 went live in prod on 2026-04-22 alongside the existing v10 release. mycure v10.6.5 is now calling v11 at `hapihub-next.localfirsthealth.com`; mycurev8 still calls v10 at the canonical URL.

The six indexes the hapihub team codified in `0014_preprod_missing_indexes.sql` (applied via `pg-concurrent-migrator.ts`) are in place on prod and being used. But a systematic scan of `pg_stat_user_tables` + 2 hours of real v11 traffic reveals **additional index gaps** and **several endpoint latencies that no index can fix** (ORM-side work).

This document is structured as a handoff to the hapihub team — it separates what infra can apply as stopgaps from what needs hapihub code / migration changes to be durable.

---

## Summary

1. **Highest-impact finding**: the four `*_history` audit-trail tables (`personal_details_history`, `medical_records_history`, `diagnostic_order_tests_history`, `inventory_stocks_history`) have **no index on the `_record` column**, which is what v11's pg-service queries by for amendment-trail retrieval (`WHERE _record = <source_id>`). Result: **every amendment-trail query is a full table seq-scan** of tables up to 648 MB. On prod, `personal_details_history` has taken 4,893 seq scans since stats reset vs. zero idx scans. This is user-visible on the RIS/LIS test amendment view and the PME report amendment view.
2. **Secondary filter gaps**: high-volume queries on `queue_items(subject, trail)`, `medical_patients(account)`, and `personal_details(account)` are not covered by existing indexes. Need verification of exact filter shape before indexing.
3. **ORM-side latencies on small tables**: `listDiagnosticTests` (4.5 s avg on a 6 MB table), `listServiceServices` (3.3 s on 6 MB), `retrieveDiagnosticTest` (2.1 s for a single-row retrieve) cannot be fixed by any index — the DB is fine, hapihub's request handling is slow for reasons that need profiling.
4. **Observability gap**: `pg_stat_statements` is not installed on any env. All performance investigation today relies on ad-hoc log parsing. Installing this extension makes future investigations minutes instead of hours.
5. **Minor**: `pg-concurrent-migrator.ts` has a multi-replica race condition that caused 1–3 pod restarts during the v11 rollout. Cosmetic but worth fixing with a `pg_advisory_lock`.

---

## Methodology

All data below is from read-only queries against prod + preprod Postgres and `kubectl logs` on hapihub pods. No prod state was modified.

### Data sources used

1. `pg_stat_user_tables` — aggregate seq_scan / idx_scan / seq_tup_read counts per table, since the last stats reset.
2. `pg_stat_user_indexes` — per-index `idx_scan` counts to verify which indexes are actually being used.
3. Hapihub pod logs (`"msg":"request completed"` lines) over the last 2 hours, grouped by `operationId`, aggregated to avg/max latency.
4. Spot `pg_stat_activity` samples to catch in-flight slow queries earlier in the week.
5. Postgres slow-query log (preprod only — `log_min_duration_statement = '200ms'` was enabled on 2026-04-21 and remains on).

### What we don't have

`pg_stat_statements` is **not installed** on any environment. This means we don't have per-query aggregate stats (mean_exec_time, total_exec_time per query fingerprint). Everything below is inferred from either table-level seq_scan rates or from hapihub's higher-level operation-id timings. Installing the extension would make this kind of scan a 2-line query instead of a 30-minute manual exercise.

---

## Finding 1 — Missing `_record` indexes on all four `*_history` tables

### Evidence

From prod `pg_stat_user_tables`:

| Table | Size | Rows | seq_scan | idx_scan | pct_seq | avg rows per seq-scan |
|---|---|---|---|---|---|---|
| `personal_details_history` | 124 MB | 165,069 | **4,893** | **0** | 100% | 2,372 |
| `medical_records_history` | 648 MB | 712,602 | 17 | **0** | 100% | 648,932 |
| `diagnostic_order_tests_history` | 13 MB | 8,071 | 17 | **0** | 100% | 9,261 (full table) |
| `inventory_stocks_history` | 425 MB | 14,123 | 43 | **0** | 100% | 427,450 (full table) |

Identical shape on preprod.

All four tables show **idx_scan = 0** since stats reset. Every amendment-trail query on prod is a full seq-scan of the entire history table.

### Why

From commit `1e786954` in hapihub (referenced in `0010_history_pk_swap.sql`'s docstring): the convention flipped so that `id` is a unique audit-entry ID and `_record` is the non-unique source-record pointer. `pg-service.ts:657-660` comment confirms v11 queries history via `_record = <source_id>`.

The PK was swapped from `_record` to `id` in migration `0010`. After the swap, **neither column is indexed except via the PK** — which is now on `id`, not `_record`. So queries by `_record` (the new query convention) get no index coverage.

### User-visible impact

Two features read these tables:

1. `useOrderTestAmendments` in `apps/mycure/src/pages/ris/OrderWorkspace.vue` and `apps/mycure/src/pages/lis/OrderWorkspace.vue` — shows amendment trail for a diagnostic test order. Reads `diagnostic_order_tests_history`.
2. `fromRawMedicalRecordAmendment` in `apps/mycure/src/composables/diagnostics.pme.ts` — shows amendment history for PME reports. Reads `medical_records_history`.

A third internal consumer:
3. `services/hapihub/src/services/inventory/variant-reports.ts` uses `$history: true, $findone: true, $limit: 1` on `inventory_stocks` to resolve "what was the stock at the time of this transaction." With no index on `_record`, this seq-scans the entire `inventory_stocks_history` table per variant-report call.

### Recommended fix (hapihub side — Drizzle migration)

Add a new migration that declares btree indexes on `_record` for all four history tables. Non-transactional (run via `pg-concurrent-migrator.ts`) so the build is `CREATE INDEX CONCURRENTLY`, non-blocking. Pattern is exactly the same as the 0014 stub + pg-concurrent-migrator flow:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_personal_details_history_record
  ON personal_details_history (_record);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_medical_records_history_record
  ON medical_records_history (_record);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_diagnostic_order_tests_history_record
  ON diagnostic_order_tests_history (_record);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_inventory_stocks_history_record
  ON inventory_stocks_history (_record);
```

Also declare each index in the Drizzle schema where the history tables are defined (`src/utils/drizzle/schema-builder.ts` or wherever the `*_history` table definitions live). Pattern from the 0014 fix:

```ts
export const personalDetailsHistory = pgTable('personal_details_history', {
  // ...existing columns
}, (t) => ({
  recordIdx: index('idx_personal_details_history_record').on(t._record),
}))
```

### Expected impact

| Endpoint | Pre-index | Post-index expected |
|---|---|---|
| RIS/LIS amendment view on a diagnostic test order | tens of ms on v10 today; current v11 queries seq-scan 13 MB / 8K rows | single-digit ms |
| PME amendment view on a report | current v11 queries seq-scan 648 MB / 712K rows | single-digit ms |
| `variant-reports.ts` per-transaction lookup | seq-scans 425 MB / 14K rows per call | single-digit ms; eliminates one of the N+1 costs on inventory reports |

Postgres CPU also drops — those 4,893 seq scans on `personal_details_history` alone represent real IO load.

### Infra-side mitigation (in parallel)

Infra can apply the same four `CREATE INDEX CONCURRENTLY` commands directly on preprod (and prod, with authorization) as a stopgap while the hapihub migration is being written. This is the same pattern as the six earlier stopgap indexes that the team eventually codified. Durability caveat: stopgap DDL survives pod restarts but not DB restores — the migration is the permanent fix.

---

## Finding 2 — Secondary filter shapes not covered by current indexes

### Evidence

Prod `pg_stat_user_tables` rows with high absolute `seq_scan` despite an existing non-PK index:

| Table | Non-PK indexes today | seq_scan | idx_scan | Notes |
|---|---|---|---|---|
| `queue_items` | `(queue, created_at DESC)` | 2,883 | 945,037 | Many ops DO use the index, but 2,883 queries seq-scan 447K rows each. |
| `medical_patients` | `(facility, created_at DESC)` + FTS on `external_id` | 1,826 | 484,079 | Similar — hot filter shape isn't covered. |
| `personal_details` | `(facility, created_at DESC)` + 5 FTS indexes | 14,558 | 1,231,749 | Very high absolute seq_scan count. |
| `diagnostic_order_tests` | None (only PK) | 3,335 | 145,036 | 2.2% seq but each reads 144K rows — the whole table. |

### Observed query patterns (from earlier `pg_stat_activity` samples on preprod)

```sql
-- queue_items (seen in slow-query log, ~777ms and ~1189ms samples)
SELECT ... FROM queue_items WHERE subject = $1 AND trail = $2 ORDER BY created_at DESC LIMIT $3;

SELECT ... FROM queue_items WHERE subject = $1 AND trail = $2
  AND "order" IS NOT NULL
  AND finished_at IS NULL
  AND rejected_at IS NULL
  AND (deferred_at IS NULL OR requeue_deferred_at IS NOT NULL)
LIMIT $3;

-- medical_patients (seen in slow-query log)
SELECT ... FROM medical_patients WHERE account = $1;

-- billing_payments
SELECT ... FROM billing_payments WHERE item_invoice = $1;
```

### Recommended indexes (after hapihub team verifies exact filter shapes)

```sql
-- queue_items
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_queue_items_subject_trail
  ON queue_items (subject, trail);

-- medical_patients (hot query: WHERE account = $1, from billing/login flows)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_medical_patients_account
  ON medical_patients (account);

-- personal_details (similar account filter)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_personal_details_account
  ON personal_details (account);

-- billing_payments (seen at 523–1553 ms tail in earlier investigation)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_billing_payments_item_invoice
  ON billing_payments (item_invoice);

-- diagnostic_order_tests (hot table, no non-PK indexes at all)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_diagnostic_order_tests_order
  ON diagnostic_order_tests (order);
-- Filter column TBD — may be facility or patient; hapihub team should confirm from handler source.
```

### Recommended hapihub-side work

For each of the above, the hapihub team should:

1. **Identify the actual query** emitted by the relevant service (e.g., `services/queue/items.ts`, `services/person/details.ts`). Confirm the filter shape.
2. **Run `EXPLAIN ANALYZE`** on a representative query against preprod to confirm the index will be used.
3. **Add the index to the Drizzle schema + a new non-transactional migration** (same pattern as the 0014 stub + pg-concurrent-migrator).
4. **Ship in the next hapihub patch release**.

---

## Finding 3 — ORM-side latencies (no index will fix these)

### Evidence

Prod v11 endpoints with high latency on **small tables** where DB scan is cheap:

| Endpoint | n | avg | max | Table size | Observation |
|---|---|---|---|---|---|
| `listDiagnosticTests` | 86 | 4.5 s | 6.5 s | `diagnostic_tests` = 6 MB | DB seq-scan of 6 MB is ms-scale. Gap is hapihub-side. |
| `listServiceServices` | 29 | 3.3 s | 7.4 s | `services` = 6 MB | Same pattern. |
| `listMedicineMedicines` | 5 | 1.5 s | 3.4 s | `medicines` = 5 MB | Same pattern. |
| `retrieveDiagnosticTest` | 130 | 2.1 s | 3.8 s | Single-row PK lookup | 2 s for a PK lookup is unexplainable by DB alone. |

### Hypotheses (each needs hapihub-side profiling to confirm)

1. **ORM row-hydration overhead.** Drizzle materializing wide rows with many JSONB columns into JS objects. On tables like `services` that have 10+ JSONB columns, each row carries significant parse cost.
2. **Eager `$populate` chains.** If the handler populates multiple related entities per row (e.g. `retrieveDiagnosticTest` fetching `order`, `patient`, `facility`, `createdBy` in separate queries), N+1 accumulates even at single-row retrieve.
3. **JSON.stringify of large response payloads.** For `listServiceServices` returning 1,000+ rows with heavy JSONB, Bun's encoder spends hundreds of ms.
4. **Connection pool contention.** Earlier investigation showed slow queries on other endpoints blocking connection slots. If a slow `listNotificationNotifications` (5s pre-GIN-index) had been holding a pool connection, other endpoints queued behind it. Post-GIN-index this is better, but the pattern may still manifest on other slow ops.

### Recommended hapihub-side investigation

1. **Add operation-level tracing**: wrap each handler with a span that captures (a) time in DB, (b) time in ORM hydration, (c) time in response serialization. Output to structured logs.
2. **Pick one hot endpoint** (e.g., `retrieveDiagnosticTest`) and profile end-to-end on preprod with a prod-sized dataset. Identify where the 2 s goes.
3. **Batch the N+1**: for any handler that does per-row lookups, replace with a single `WHERE <col> = ANY($1::text[])` + client-side mapping. Same pattern as the `insurance_coverages.contract` fix.
4. **Trim JSONB from list projections**: consider serving a "lean" shape from list endpoints (only scalar columns + summarized JSONB) and reserving the full JSONB for detail retrieves.

No index will help any of these. This is hapihub code work.

---

## Finding 4 — 25-second `patchBillingInvoiceLegacy` outlier

### Evidence

From prod v11 last 2h:

```
patchBillingInvoiceLegacy   n=1   avg=25319ms   max=25319ms
```

A single request took **25.3 seconds**. No other billing-legacy endpoint ran in that window at comparable latency.

### Recommended investigation

- Extract the `req_id` from the hapihub log line and trace the request end-to-end.
- Likely either a very large write transaction (`billing_legacy_invoices` has related `billing_items` that fan out), an external-service call blocking (Stripe?), or the N+1-on-write equivalent of the read-side billing N+1 already documented.
- Worst case, add a slow-request alert at 10 s for all billing operations so you catch these in real time.

---

## Finding 5 — `pg-concurrent-migrator` replica race

### Evidence

During the v11 rollout on 2026-04-22, all three `hapihub-next` replicas started simultaneously. Each invoked `pg-concurrent-migrator.ts` and each attempted `CREATE INDEX CONCURRENTLY IF NOT EXISTS <name>` on the same six indexes in parallel. Two pods raced on `idx_medical_records_patient_created_at`, one failed (leaving `indisvalid = false`), the failing pod restarted. Similar races on other indexes. Final pod restart counts: 1, 2, 3.

All indexes ended up valid. No user impact. Cosmetically, pod logs look like something went wrong.

### Recommended fix

Wrap the migrator's index loop in a Postgres advisory lock:

```ts
// services/hapihub/src/utils/drizzle/pg-concurrent-migrator.ts
const LOCK_KEY = 0x484150494855420n;  // "HAPIHUB" as bigint — any fixed value
await db.execute(sql`SELECT pg_advisory_lock(${LOCK_KEY})`);
try {
  for (const idx of indexes) {
    await buildIndex(idx);
  }
} finally {
  await db.execute(sql`SELECT pg_advisory_unlock(${LOCK_KEY})`);
}
```

Only one replica at a time holds the lock; others block until it's released, then find the indexes already built and skip via `IF NOT EXISTS`.

Priority: low (cosmetic), but worth fixing before the next multi-replica deploy so operators don't mistake restart noise for a real issue.

---

## Finding 6 — Observability debt: install `pg_stat_statements`

Every performance investigation in this RCA series — and the preceding ones — relied on ad-hoc log parsing + table-level seq_scan counts. That works but is slow.

Installing `pg_stat_statements` on Postgres makes "which queries are slow?" a 2-line query:

```sql
SELECT query, calls, mean_exec_time, total_exec_time, rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

### Install cost

1. Add `pg_stat_statements` to `shared_preload_libraries` in Postgres config. On the Bitnami chart, this is `primary.configuration` or `primary.extendedConfiguration`.
2. **Postgres pod restart** — the library is loaded at Postgres startup, not runtime. Brief DB outage during restart (seconds on preprod, may be longer on prod due to shared_buffers warmup).
3. Once restarted: `CREATE EXTENSION pg_stat_statements IN DATABASE hapihub`.

### Priority

- Preprod: **should be done this week**. Zero user impact, pure upside.
- Prod: **next scheduled maintenance window**. Brief outage acceptable given the long-term value.

Ownership: infra for the Bitnami values change + extension creation. No hapihub code needed.

---

## Infra commitments

Things the mono-infra side will do, parallel to hapihub team's work:

| # | Action | Owner | ETA |
|---|---|---|---|
| 1 | Apply Tier-1 stopgap indexes (4 `*_history(_record)` indexes) on preprod, validate with EXPLAIN. | Infra | Today, non-blocking |
| 2 | If validation on preprod looks good, apply same 4 on prod via `CREATE INDEX CONCURRENTLY`. | Infra | With explicit authorization |
| 3 | Install `pg_stat_statements` on preprod Postgres. | Infra | This week |
| 4 | Run `pg_stat_activity` sampling on prod to confirm Tier-2 filter shapes before recommending the Tier-2 indexes. | Infra | This week |
| 5 | Plan `pg_stat_statements` install on prod for next maintenance window. | Infra | Next window |

---

## Asks of the hapihub team

Ordered by urgency / impact.

### High priority

1. **Add a non-transactional migration (pattern of `0014` + `pg-concurrent-migrator.ts`) that creates btree indexes on all four `*_history(_record)` columns.** Declare the indexes in the Drizzle schema. Ship in the next patch release (e.g., `11.2.21`). This is the permanent fix for Finding 1.
2. **Investigate and profile the ORM-side latencies in Finding 3.** Specifically `listDiagnosticTests`, `listServiceServices`, `retrieveDiagnosticTest`. Add operation-level tracing to split DB time vs ORM time vs serialization time. No one-size fix — needs profiling to choose remediations.
3. **Trace the `patchBillingInvoiceLegacy` 25-second case (Finding 4)**. Use the `req_id` `RB2026-04-22_patchBillingInvoiceLegacy_25319ms` from the log (infra can provide exact req_id if needed). Identify whether this is a write-side N+1, external-service call, or something else.

### Medium priority

4. **Verify the Tier-2 filter shapes from Finding 2** by reading handler source in `services/queue`, `services/person`, `services/billing`, `services/diagnostic`. Confirm which columns are filtered. Add matching indexes to the next migration.
5. **Batch the `insurance_coverages.contract` N+1 in the billing-invoice handler.** The index helps each call but the pattern still makes many round trips. Pattern: single `WHERE contract = ANY($1::text[])` + client-side mapping. Documented in `RCA-2026-04-19-PREPROD-BILLING-INVOICES-N-PLUS-1.md` action item #2.

### Low priority (cosmetic)

6. **Add a `pg_advisory_lock` in `pg-concurrent-migrator.ts`** to serialize index builds across replicas. Finding 5.

---

## Appendix — full pg_stat_user_tables scan output

For reference, run this against either environment:

```sql
SELECT relname AS tbl,
       pg_size_pretty(pg_relation_size(relid)) AS size,
       n_live_tup AS rows,
       seq_scan, idx_scan,
       CASE WHEN seq_scan+idx_scan=0 THEN 0
            ELSE round(100.0*seq_scan/(seq_scan+idx_scan),1) END AS pct_seq,
       CASE WHEN seq_scan=0 THEN 0
            ELSE (seq_tup_read/seq_scan)::bigint END AS avg_rows_per_seqscan
FROM pg_stat_user_tables
WHERE pg_relation_size(relid) > 10*1024*1024
  AND seq_scan > 10
ORDER BY seq_scan * pg_relation_size(relid) DESC
LIMIT 15;
```

Results captured on 2026-04-23:

### Production (`mycure-production`)

| tbl | size | rows | seq_scan | idx_scan | pct_seq | avg rows per seq-scan |
|---|---|---|---|---|---|---|
| `personal_details` | 189 MB | 494,766 | 14,558 | 1,231,749 | 1.2% | 159,085 |
| `queue_items` | 530 MB | 944,304 | 2,883 | 945,037 | 0.3% | 447,279 |
| `personal_details_history` | 124 MB | 165,069 | 4,893 | 0 | 100.0% | 2,372 |
| `diagnostic_order_tests` | 124 MB | 144,721 | 3,335 | 145,036 | 2.2% | 144,285 |
| `medical_patients` | 183 MB | 478,838 | 1,826 | 484,079 | 0.4% | 211,407 |
| `billing_items` | 1504 MB | 2,159,514 | 50 | 2,182,170 | 0.0% | 691,385 |
| `medical_records` | 3095 MB | 3,309,661 | 24 | 3,570,464 | 0.0% | 2,079,392 |
| `billing_payments` | 466 MB | 1,560,589 | 109 | 1,563,428 | 0.0% | 774,380 |
| `notifications` | 98 MB | 61,021 | 214 | 62,477 | 0.3% | 60,683 |
| `inventory_stocks_history` | 425 MB | 14,123 | 43 | 0 | 100.0% | 427,450 |
| `medical_encounters` | 1069 MB | 1,321,398 | 13 | 1,361,570 | 0.0% | 519,919 |
| `medical_records_history` | 648 MB | 712,602 | 17 | 0 | 100.0% | 648,932 |
| `billing_invoices` | 653 MB | 1,465,602 | 14 | 1,474,697 | 0.0% | 631,884 |
| `fixtures` | 16 MB | 56,792 | 479 | 57,095 | 0.8% | 52,813 |
| `services_performeds` | 317 MB | 1,811,746 | 14 | 1,811,913 | 0.0% | 905,806 |

### Preprod (`mycure-preprod`) — same shape, lower absolute counts

| tbl | size | rows | seq_scan | idx_scan | pct_seq | avg rows per seq-scan |
|---|---|---|---|---|---|---|
| `queue_items` | 530 MB | 944,072 | 398 | 237 | 62.7% | 360,525 |
| `medical_patients` | 183 MB | 479,833 | 877 | 440 | 66.6% | 209,003 |
| `medical_records` | 3095 MB | 3,554,807 | 13 | 27 | 32.5% | 1,645,233 |
| `billing_items` | 1504 MB | 2,156,736 | 26 | 85 | 23.4% | 914,091 |
| `diagnostic_order_tests` | 124 MB | 144,719 | 288 | 0 | 100.0% | 143,714 |
| `billing_invoices` | 653 MB | 1,473,483 | 52 | 0 | 100.0% | 765,552 |
| `medical_records_history` | 524 MB | 715,173 | 29 | 0 | 100.0% | 324,701 |
| `inventory_stocks_history` | 347 MB | 14,750 | 12 | 0 | 100.0% | 434,196 |
| `personal_details` | 187 MB | 494,766 | 19 | 6,345 | 0.3% | 240,963 |
| `personal_details_history` | 124 MB | 165,069 | 19 | 0 | 100.0% | 186,731 |
| `notifications` | 98 MB | 61,027 | 24 | 2,244 | 1.1% | 58,467 |
| `fixtures` | 16 MB | 56,792 | 28 | 0 | 100.0% | 42,887 |
| `insurance_contracts` | 11 MB | 39,803 | 22 | 0 | 100.0% | 20,050 |
| `diagnostic_order_tests_history` | 13 MB | 8,071 | 17 | 0 | 100.0% | 9,261 |
