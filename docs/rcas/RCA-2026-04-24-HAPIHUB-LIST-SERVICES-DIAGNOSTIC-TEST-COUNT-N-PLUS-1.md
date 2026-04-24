# RCA: `GET /services` with `$expand=queueing.meta.testPackage.tests` Fires N+1 `count(*) FROM diagnostic_order_tests WHERE test = $1` on Unindexed Column

| Field | Value |
|-------|-------|
| **Date** | 2026-04-24 |
| **Severity** | High (user-visible — `listServiceServices` endpoint averaging 2–3 s on preprod, up to 7+ s on prod v11) |
| **Status** | Open — awaiting hapihub-side fix (index + N+1 refactor). Infra can apply a `CREATE INDEX CONCURRENTLY` stopgap on request. |
| **Services Affected** | HapiHub API `GET /services` (mycure UI) — particularly any page that loads services with the `queueing.meta.testPackage.tests` expand chain. |
| **Environments observed** | preprod (10.6.8 / 11.2.21) — confirmed N+1 from slow-query log + pg_stat_activity. Prod v11 (11.2.21 on `hapihub-next.localfirsthealth.com`) has the same pattern with larger absolute numbers. |
| **Detected by** | User report of a slow specific URL (`/services?facility=…&type=pe&$expand=…`). Infra traced via preprod Postgres slow-query log (`log_min_duration_statement=200ms`) + `EXPLAIN ANALYZE` of the fanout query. |
| **Related RCAs** | [`RCA-2026-04-23-HAPIHUB-POST-CUTOVER-INDEX-GAPS.md`](./RCA-2026-04-23-HAPIHUB-POST-CUTOVER-INDEX-GAPS.md) — this is a concrete instance of Finding 2 in that scan (`diagnostic_order_tests` had no non-PK indexes). [`RCA-2026-04-19-PREPROD-BILLING-INVOICES-N-PLUS-1.md`](./RCA-2026-04-19-PREPROD-BILLING-INVOICES-N-PLUS-1.md) — same architectural pattern. |
| **Fix Commit** | N/A — awaiting change in hapihub repo |

---

## Summary

The exact URL reported by the user:

```
GET /api/services?facility=5bfbd955def0d210c790994d
    &type=pe
    &$expand=coverages,items,commissions.provider,queueing.queue,queueing.queues,
             queueing.meta.testPackage,queueing.meta.testPackage.tests,
             formTemplates,consentForms
    &$search[text]=
    &$limit=%2310          ← URL-encoded literal "#10", not a valid integer
    &$skip=%230            ← URL-encoded literal "#0"
```

**What's happening server-side:**

1. The bare filter query — `WHERE facility = $1 AND type = 'pe'` — is fast. `EXPLAIN ANALYZE` on preprod shows **10.96 ms** (seq scan of a 6 MB / 18 K row table, returning 13 rows).
2. The **`$expand` chain** then runs a set of side-loading queries per returned row.
3. Specifically, the `queueing.meta.testPackage.tests` nested expansion triggers — per **test** in each returned service's test package — a repeated query shape:

    ```sql
    SELECT count(*) FROM diagnostic_order_tests WHERE test = $1
    ```

4. The `diagnostic_order_tests` table (145 K rows / 124 MB) **has no non-PK indexes**. Every `count(*)` call is a full sequential scan, costing **~194 ms per call** (reads ~130 MB of buffers).
5. The preprod postgres slow-query log shows **651 such queries in the last 30 minutes, totaling 309 seconds of DB time, avg 475 ms / call** (contention-elevated). This correlates with the user's reported slow page loads at ~2–3 s per request.

**Combined effect**: a single page view of the services list with this expand chain can easily trigger 10+ of these count queries. At 195–475 ms each, you get the 2–7 s end-to-end latency the user is seeing.

**Compounding factor**: the `$limit=#10` parameter is an invalid integer (URL-encoded `%23` = `#`). hapihub appears to fall through to "no limit" behavior — returning all 13 matching rows from the bare filter rather than paginating. More rows → more expansion fanout. Worth hardening the `$limit`/`$skip` parser to reject non-integer values with a 400.

---

## Impact

- **User-visible**: slow list in any UI that opens a services catalog with the full expand chain (likely the billing or encounter workspace service picker). Reported at 2–3 s on preprod for ~13 matching services; proportionally worse on prod v11 where the absolute seq scan cost is bigger.
- **Postgres CPU + IO**: every page view reads ~130 MB of buffers per count query. Across multiple users in a working-hours window this is a measurable chunk of database load.
- **No data correctness issue.** Just latency and wasted CPU.

---

## Evidence

### User URL (normalized)

```
facility = 5bfbd955def0d210c790994d
type     = pe
$expand  = coverages, items, commissions.provider,
           queueing.queue, queueing.queues,
           queueing.meta.testPackage, queueing.meta.testPackage.tests,
           formTemplates, consentForms
$limit   = #10  (invalid)
$skip    = #0   (invalid)
```

### Live hapihub latencies on preprod (preprod is `11.2.21`, last 30 min, mid-traffic)

```
operationId=listServiceServices   duration=3186ms
operationId=listServiceServices   duration=2756ms
operationId=listServiceServices   duration=2455ms
operationId=listServiceServices   duration=2464ms
operationId=listServiceServices   duration=1218ms
```

Average around 2–3 s. Same shape we've previously documented for this endpoint.

### Bare DB query for the user's filter (fast, NOT the problem)

```sql
EXPLAIN (ANALYZE, BUFFERS)
  SELECT * FROM services
  WHERE facility = '5bfbd955def0d210c790994d' AND type = 'pe';
```

```
Seq Scan on services  (cost=0.00..888.60 rows=5 width=626)
                       (actual time=3.324..10.839 rows=13 loops=1)
   Filter: ((facility = '5bfbd955def0d210c790994d'::text) AND (type = 'pe'::text))
   Rows Removed by Filter: 17960
   Buffers: shared read=619
 Execution Time: 10.963 ms
```

13 rows returned, 11 ms. **Not the issue.**

### The N+1 query that IS the issue

From preprod postgres log (`log_min_duration_statement=200ms`):

```
duration: 475.XXX ms  execute <unnamed>:
  select count(*) from "diagnostic_order_tests" where "diagnostic_order_tests"."test" = $1
```

Appearing **651 times in the last 30 minutes**.

### Cost per call (EXPLAIN ANALYZE on preprod)

```sql
EXPLAIN (ANALYZE, BUFFERS)
  SELECT count(*) FROM diagnostic_order_tests
  WHERE test = (SELECT test FROM diagnostic_order_tests
                WHERE test IS NOT NULL LIMIT 1);
```

```
Seq Scan on diagnostic_order_tests
    (cost=0.00..17728.99 rows=154 width=0)
    (actual time=0.056..193.374 rows=3563 loops=1)
   Filter: (test = $0)
   Rows Removed by Filter: 141172
   Buffers: shared hit=7399 read=8522
 Execution Time: 194.117 ms
```

Per call: **~194 ms**, reading 15,921 buffers (~130 MB). At prod scale the absolute cost is similar or higher (same row count order-of-magnitude; cache hit ratio may vary).

### Current indexes on `diagnostic_order_tests`

Only the primary key:

```
diagnostic_order_tests_pkey | PRIMARY KEY btree (id)
```

No index on `test`, or on any other column.

---

## Root Cause

### Primary — missing index

`diagnostic_order_tests` has no index on the `test` column. Every `WHERE test = $1` query does a full seq scan of 145 K rows (124 MB). Called once, it's ~200 ms; called N times per page view, it compounds into seconds.

### Upstream — N+1 in the expand handler

The `$expand=queueing.meta.testPackage.tests` nested expansion is firing one `count(*) FROM diagnostic_order_tests` **per test** in the expanded test packages. Per-row count queries inside a nested expansion are the classic N+1 signature.

We don't know from the DB side alone whether each count is:
- "How many times has this test been ordered?" — a per-test-catalog-entry count
- "How many diagnostic orders reference this test right now?" — a liveness check
- A subtle enrichment ("test is recently used / recently popular")

Whichever semantic it is, doing it once per test per request is not right for a services-list endpoint where the counts are probably not even displayed prominently.

### Secondary — `$limit` parser accepts invalid values

The client sent `$limit=%2310` (decoded: `$limit=#10`). Either:
- mycure built the URL incorrectly (placeholder template that wasn't substituted), or
- hapihub's parser doesn't reject non-integer values and falls through to "no limit".

Either way, **with a valid `$limit=10`, the returned row count would be capped at 10 regardless of how many services match**, reducing the fanout. The bare filter returned 13 rows; with pagination enforced, that would be 10 rows × their expansions. Not a massive difference here (13 vs 10) but the same class of bug could return hundreds of rows if the filter is less selective.

---

## Fix

### Immediate (DB-side stopgap — same pattern as 6 earlier stopgap indexes)

Non-transactional `CREATE INDEX CONCURRENTLY`:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_diagnostic_order_tests_test
  ON diagnostic_order_tests (test);
```

**Expected impact per call**: 194 ms (seq scan of 141 K rows, 15,921 buffers) → **< 1 ms** (index scan, handful of buffers). About a **200×** per-call speedup.

**User-visible effect on the reported URL**: `listServiceServices` drops from ~2–3 s to the low hundreds of ms (the remaining cost is ORM hydration + JSONB serialization + the other 8 expansions, not related to this index).

Same safety characteristics as the other preprod stopgap indexes: `CONCURRENTLY` takes only `SHARE UPDATE EXCLUSIVE` on the target table, non-blocking for reads and writes, completes in seconds on a 124 MB table.

### Permanent (hapihub code)

Two things to do in the hapihub repo. Both needed.

#### 1. Codify the index in a Drizzle migration

Add it to the next non-transactional migration (same pattern the team already used for the six indexes from the 2026-04-22 cutover). Declare in the Drizzle schema where `diagnostic_order_tests` is defined:

```ts
export const diagnosticOrderTests = pgTable('diagnostic_order_tests', {
  // ...existing columns
}, (t) => ({
  testIdx: index('idx_diagnostic_order_tests_test').on(t.test),
}))
```

Plus the matching migration file (non-transactional, `CREATE INDEX CONCURRENTLY`). Ship in the next hapihub patch (e.g. `11.2.22`).

This is listed as a Finding 2 item in [`RCA-2026-04-23-HAPIHUB-POST-CUTOVER-INDEX-GAPS.md`](./RCA-2026-04-23-HAPIHUB-POST-CUTOVER-INDEX-GAPS.md) already — this RCA provides the specific query shape to confirm `test` is the column.

#### 2. Fix the N+1 in the expand handler

Even after the index, N round trips at ~1 ms each still totals N ms plus connection pool overhead — and the pattern is architecturally wrong. Find the code path behind `$expand=queueing.meta.testPackage.tests` that does `count(*) FROM diagnostic_order_tests WHERE test = $1`, and either:

**Option A — Batch the counts**

Replace N individual queries with one:

```sql
SELECT test, count(*)
FROM diagnostic_order_tests
WHERE test = ANY($1::text[])
GROUP BY test;
```

Consumer code builds a map from test id → count. One query instead of N.

**Option B — Drop the count if not used in the UI**

If the count isn't actually rendered anywhere in the mycure UI (which seems plausible — a services list probably doesn't show "ordered 3,563 times" next to each test), the cheapest fix is to stop computing it. Audit whether the consumer of `listServiceServices` actually uses this field.

**Option C — Cache the count**

If the count IS used in UI, cache it (either in Valkey with a 1-minute TTL or in the `diagnostic_tests` row as a denormalized column updated by an audit trigger). Depends on how fresh the count needs to be.

Recommended: start with **Option B** (audit usage). If the count isn't displayed, drop it. If it is, go to **Option A** (batch) as the first fix.

### Secondary — harden `$limit` / `$skip` parsing

When a request comes in with `$limit=#10` or any non-integer value:

- Reject with `400 Bad Request` citing `$limit must be a non-negative integer`, OR
- Silently fall back to a default of, say, 100, rather than "no limit"

The current "no limit when invalid" behavior is the dangerous fallback — it means any client bug in the limit-building code amplifies load on the server.

Also worth a client-side audit in mycure: where is the URL `$limit=#10` being built? That's a template-substitution or string-concatenation bug, not a typical client pattern.

---

## Verification plan (after the hapihub team ships the fix)

1. **Confirm the index exists on preprod** via `pg_stat_user_indexes`:

    ```sql
    SELECT indexrelid::regclass, indisvalid FROM pg_index
    WHERE indexrelid::regclass::text = 'idx_diagnostic_order_tests_test';
    ```

2. **Confirm the planner uses it** via `EXPLAIN ANALYZE` on the query shape:

    ```sql
    EXPLAIN (ANALYZE, BUFFERS)
      SELECT count(*) FROM diagnostic_order_tests WHERE test = 'some-test-id';
    ```

    Expect: `Index Only Scan using idx_diagnostic_order_tests_test`, execution time < 1 ms.

3. **Hit the user's URL against preprod** and measure `listServiceServices` duration from hapihub logs. Expect: **< 500 ms** total response time (down from 2–3 s), with most of that being the 8 remaining `$expand` hops.

4. **Check `diagnostic_order_tests` seq-scan counts** via `pg_stat_user_tables` after 24 hours of normal traffic. Expect: `seq_scan` growth rate drops meaningfully; `idx_scan` growth picks up.

5. If the N+1 refactor (Option A or B above) also lands, expect a further 5–10× reduction in `listServiceServices` latency because there will no longer be N individual round trips.

---

## Action items

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Apply `CREATE INDEX CONCURRENTLY idx_diagnostic_order_tests_test` on preprod as an infra-side stopgap so we can validate end-to-end impact today | Infra | High (if user approves — this RCA is the proposal) |
| 2 | Codify `idx_diagnostic_order_tests_test` in a non-transactional Drizzle migration in the hapihub repo, alongside the other Finding 2 indexes from the 2026-04-23 RCA | HapiHub team | **High** — the permanent version of the stopgap |
| 3 | Audit the `$expand=queueing.meta.testPackage.tests` code path. Identify where `count(*) FROM diagnostic_order_tests WHERE test = $1` is being fired from. Fix the N+1 per Option A / B / C above. | HapiHub team | **High** — even with the index, the N+1 is architecturally wrong |
| 4 | Harden `$limit` / `$skip` parsing to reject non-integer values (400) or cap at a safe default | HapiHub team | Medium — this is a latent footgun |
| 5 | mycure client-side audit: where is the URL `$limit=#10` being built with a literal `#` character? Find and fix. | mycure team | Medium |
| 6 | Apply the same index to production via `CREATE INDEX CONCURRENTLY` once the preprod validation is clean, with explicit per-change authorization per the prod guardrail. | Infra + product owner | Medium (awaiting validation on preprod first) |

---

## Appendix — how this was detected, step by step

For posterity, and as a playbook when similar reports come in:

1. User reported a specific slow URL. No logs were attached — just the URL.
2. Parsed the URL. Noted `$expand` chain + the `$limit=#10` oddity.
3. Ran `EXPLAIN ANALYZE` on the bare filter (`WHERE facility=X AND type='pe'`) — **fast (11 ms)**. Confirmed DB-side filter is not the problem.
4. Pulled last-30-min `listServiceServices` samples from preprod hapihub logs via `kubectl logs ... | grep`. Confirmed the endpoint is consistently slow (2–3 s), matching the user report.
5. Grouped preprod Postgres slow-query log (already running at `log_min_duration_statement=200ms` since the 2026-04-21 investigation) by target table. `diagnostic_order_tests` surfaced as the hot table with 651 slow calls totaling 309 seconds of DB time.
6. Grepped the postgres log for an actual query shape against `diagnostic_order_tests`. Confirmed: `SELECT count(*) FROM diagnostic_order_tests WHERE test = $1`.
7. `EXPLAIN ANALYZE` on that query — confirmed seq scan, 194 ms per call, no index present.
8. Cross-referenced with the 2026-04-23 post-cutover scan — `diagnostic_order_tests` was already flagged as "hot, no non-PK indexes." This RCA adds the specific column (`test`) and the specific user-facing endpoint.

Total time to root cause: ~10 minutes of infra investigation once the user provided the URL. Would have been sub-minute if `pg_stat_statements` were installed. (See Finding 6 of the 2026-04-23 RCA — we're still paying the observability-debt tax.)
