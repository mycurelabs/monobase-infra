# RCA: Slow `listQueueItems` on Preprod — Missing Index on `queue_items.queue`

| Field | Value |
|-------|-------|
| **Date** | 2026-04-19 |
| **Severity** | Medium (perf degradation, no errors, no data loss) |
| **Duration** | Chronic — existed as long as `queue_items` had grown large on preprod |
| **Services Affected** | HapiHub API (`GET /queue-items` → `listQueueItems`, `PATCH /queue-items/:id`) in preprod |
| **Environment** | **Preprod only** — production was **not** touched |
| **Detected By** | User report: "queue-items are so slow — is this a resource problem?" |
| **Fix Commit** | N/A — applied as a direct DDL on preprod Postgres (see *Fix* below) |

## Summary

`listQueueItems` requests on preprod hapihub were returning in a tight **3.7 s p50 / 4.0 s p90** band. Investigation showed that the pod itself was nearly idle (≈5% CPU, ≈12% memory) while `postgresql-0` was burning a full CPU core on **Parallel Seq Scans** of the 578 MB `queue_items` table (944K rows). The table had only its primary-key index — no index on the `queue` column used by every list query's filter. A non-blocking composite btree on `(queue, created_at DESC)` was added via `CREATE INDEX CONCURRENTLY`; the same representative query dropped from **919 ms → 0.34 ms** (≈2700×), and hapihub live p50 fell from **3.7 s → 51 ms**.

## Impact

- **Preprod only.** Every `GET /queue-items` and most `PATCH /queue-items/*` calls paid a ~3.7 s latency tax.
- **No data loss, no errors** — just slow.
- Production was not affected and was not touched during this investigation.
- Developer experience on preprod was degraded (QA/dev flows that iterate on queue items appeared unusable over network).

## Timeline (UTC+8)

| Time | Event |
|------|-------|
| 2026-04-19 (ongoing) | Preprod `queue_items` table had grown to 944K rows / 578 MB with only a PK index |
| 2026-04-19 ~00:35 | User reports "queue-items are so slow, is this a resource problem?" |
| ~00:36 | Pulled hapihub logs: `listQueueItems` p50 = 3733 ms, p90 = 4041 ms; hapihub pod at 53 m CPU / 245 Mi (idle) |
| ~00:37 | `kubectl top`: `postgresql-0` at **1176 m CPU** / 3.1 Gi — the actual hot pod |
| ~00:38 | `pg_stat_activity` showed a non-concurrent `CREATE INDEX … USING gin ("record")` on `activity_logs` that had been running ≈2 min (cancelled before completion) |
| ~00:40 | `\d queue_items` confirmed **only `queue_items_pkey`** existed on a 578 MB / 944K-row table |
| ~00:41 | `EXPLAIN (ANALYZE, BUFFERS)` on a representative `listQueueItems` query showed a **Parallel Seq Scan** dropping 90% of rows via `Filter: queue = $1`; 919 ms server-side, ~540 MB read |
| ~00:42 | Applied `CREATE INDEX CONCURRENTLY idx_queue_items_queue_created_at ON queue_items (queue, created_at DESC)` — succeeded (51 MB index) |
| ~00:43 | Same `EXPLAIN ANALYZE` switched to `Index Scan`, execution time **0.34 ms** |
| ~00:44 | Live hapihub sampling: p50 collapsed from 3733 ms → 51 ms |

## Root Cause

### Primary

The `queue_items` table had **no index on the `queue` column**, which is the primary filter for `listQueueItems`. Combined with ~944K rows and a ~1.5 KB avg row width (578 MB heap), every list-by-queue query forced a Parallel Seq Scan.

```
Seq Scan cost:      72,758 buffer pages read per query
Index Scan cost:    13 buffer pages read per query
```

### Contributing factors

1. **Preprod shares the staging node pool.** Commit `b7dac0c` ("reduce resource requests and move preprod to staging node pool") intentionally colocated preprod Postgres with the staging node pool to save capacity. This didn't *cause* the slowness (the seq scan would be slow anywhere), but it means Postgres CPU is a more precious resource in preprod than it was before — any missing-index regression is more visible.
2. **`activity_logs` has the same shape** — 2142 MB / 1.18 M rows, PK-only. A blocking `CREATE INDEX … USING gin ("record")` was observed mid-run but did not complete (likely cancelled during one of today's hapihub restarts / version bumps). While it ran it also consumed Postgres CPU, compounding the slowness during that window.
3. **No `pg_stat_statements`** extension installed on preprod Postgres, so this only surfaced when a human profiled it manually. There is no automated slow-query visibility today.

### Why investigation was *not* misdirected

The user specifically asked whether a 500 Mbps client link could be the bottleneck. The hapihub log `duration` field is **server-side wall-clock** (time between request receipt and response completion inside hapihub), so the network path to the user's PC was provably not in the critical path. That anchored the investigation on server-side resources from the first step.

## Fix

**Applied directly to preprod Postgres** (no change in git):

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_queue_items_queue_created_at
  ON queue_items (queue, created_at DESC);
```

Why `CONCURRENTLY`:
- Does **not** take an `ACCESS EXCLUSIVE` lock on the table — reads and writes continue uninterrupted during the build.
- Build took well under 30 s on 578 MB of data.
- If it had failed mid-build, it would have left an `indisvalid = false` index that is safely ignored by the planner and could be dropped without impact.

Why composite `(queue, created_at DESC)` rather than just `(queue)`:
- `listQueueItems` filters by `queue` and sorts by `created_at DESC`. The composite index serves both the `WHERE` and the `ORDER BY` in a single scan, so `LIMIT 20`-style queries never read the heap beyond the 20 rows they need.

### Measured improvement

| | Plan | Heap bytes read | Time |
|---|---|---|---|
| **Before** | `Parallel Seq Scan` with `Filter: queue = $1` (removes 90% of rows) | ≈540 MB per query | **919 ms** (EXPLAIN) / **~3.7 s p50** (live hapihub) |
| **After** | `Index Scan using idx_queue_items_queue_created_at` | ≈100 KB per query | **0.34 ms** (EXPLAIN) / **51 ms p50** (live hapihub) |

Speedup ≈ **2700× on the planner cost, ~70× on observed end-to-end latency.**

## Is the fix live?

**Yes — live on preprod right now.** The index exists, is `indisvalid = true`, `indisready = true`, and the query planner is using it (confirmed by post-fix `EXPLAIN`).

Caveats:

- The fix is **not in git**. It exists only as a row in preprod's `pg_index`. That is intentional (it's a DDL applied via `psql`), but it means:
  - If preprod Postgres is restored from a pre-2026-04-19 backup, the index will be missing and the slowness will return.
  - If the `postgresql-0` PVC is destroyed and the DB is re-seeded, the index must be recreated.
- **Production is unchanged.** Production's `queue_items` table still has PK-only indexing. If production users start reporting similar slowness, apply the same command there (see *Applying to production* below).
- HapiHub's own migration system did not add this index in any 11.2.x release observed. Until hapihub ships a migration that codifies it, this is a manual, out-of-band fix.

## Revert instructions

If the index ever needs to be removed (unexpected planner regression, storage pressure, or because hapihub ships a conflicting migration):

### 1. Confirm the target

```bash
PGPW=$(kubectl -n mycure-preprod get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "\d queue_items"
```

Expect to see `"idx_queue_items_queue_created_at" btree (queue, created_at DESC)` in the index list.

### 2. Drop it non-blockingly

```bash
kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "DROP INDEX CONCURRENTLY IF EXISTS idx_queue_items_queue_created_at;"
```

- `DROP INDEX CONCURRENTLY` takes only a `SHARE UPDATE EXCLUSIVE` lock — it **does not block reads or writes**.
- Must run outside a transaction block (psql does this by default with `-c`).
- If it fails mid-drop, rerun the same command; `IF EXISTS` makes it idempotent.

### 3. Verify drop succeeded

```bash
kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "SELECT indexrelid::regclass FROM pg_index WHERE indrelid = 'queue_items'::regclass;"
```

Only `queue_items_pkey` should remain.

### 4. Expect return of slowness

Dropping the index will immediately restore the 3–4 s latency floor on `listQueueItems`. This is expected and by itself is **not a reason to re-add the index** — only do that if the regression was caused by the index itself.

## Applying the same fix to production (when explicitly authorized)

Production was **not** touched in this incident per the user's standing "never change prod without explicit approval" directive. If and when production is authorized for the same fix:

```bash
# 1. Size check first — confirm the table is actually large in prod
PGPW=$(kubectl -n mycure-production get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

kubectl -n mycure-production exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "SELECT pg_size_pretty(pg_total_relation_size('queue_items')), \
             (SELECT count(*) FROM queue_items);"

# 2. Apply concurrently — safe on a live DB
kubectl -n mycure-production exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_queue_items_queue_created_at \
      ON queue_items (queue, created_at DESC);"
```

On a production-sized `queue_items` table the build may take longer (minutes), but reads and writes continue uninterrupted throughout.

## Correct long-term remediation (in code, not in the DB)

The manual `CREATE INDEX` applied above is a **stopgap**. The correct home for this change is **hapihub's own migration history** (this `mycure-infra` repo owns deploys and image pins, not schema). Concretely:

1. **Add a new Drizzle migration in the hapihub repo**, e.g. `drizzle/migrations/NNNN_add_queue_items_queue_index.sql`:

    ```sql
    -- drizzle:non-transactional   (or whatever pragma/config hapihub uses
    --                              to disable the implicit BEGIN/COMMIT —
    --                              CREATE INDEX CONCURRENTLY cannot run
    --                              inside a transaction)

    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_queue_items_queue_created_at
      ON queue_items (queue, created_at DESC);
    ```

2. **Declare the index in the Drizzle schema definition** (wherever `queue_items` is declared, likely `src/db/schema.ts` or similar) so `drizzle-kit generate` doesn't propose re-creating it on the next schema pass:

    ```ts
    export const queueItems = pgTable('queue_items', {
      // ...existing columns
    }, (t) => ({
      queueCreatedAtIdx: index('idx_queue_items_queue_created_at')
        .on(t.queue, t.createdAt.desc()),
    }))
    ```

3. **Ship as a normal hapihub release** (e.g. `11.2.14`). Once merged + tagged, bump the tag in `values/deployments/*.yaml` in this repo, ArgoCD auto-syncs, hapihub runs migrations at startup, and the index gets applied on **every** environment (staging, preprod, production, on-prem, future tenants) — no more manual DDL.

4. **Idempotency with the manual preprod index**: reuse the same index name (`idx_queue_items_queue_created_at`). `CREATE INDEX IF NOT EXISTS` then becomes a no-op on preprod (no wasted rebuild, no conflict) and a real build elsewhere. If the migration uses a different name, preprod will briefly hold two equivalent indexes — drop the manual one after rollout (see *Revert instructions*).

### What *not* to do in `mycure-infra`

- **Don't add a Helm post-install `Job`** that runs DDL from a chart. That couples charts to DB credentials, creates a second source of truth for schema, and makes schema depend on deploy ordering.
- **Don't encode it as a one-shot ArgoCD PreSync hook** for the same reason.
- Keep schema with the app that owns it. The chart's responsibility ends at "run the container".

## Lessons Learned

### What went well

- Comparing `kubectl top pod` on hapihub vs postgres immediately pointed to the DB as the hot resource, not the app pod. This foreclosed "throw more CPU at hapihub" as a wrong answer.
- The log `duration` field in hapihub is server-side, so ruling out network was a one-sentence check rather than an investigation.
- `CREATE INDEX CONCURRENTLY` + `IF NOT EXISTS` made the fix fully safe (non-blocking, idempotent, easily reversible) and cheap enough to apply with confidence.

### What went wrong

- No slow-query visibility: `pg_stat_statements` is not installed on preprod (or anywhere else in the fleet, pending verification). Without it, this kind of "a particular query is slow" finding depends on ad-hoc log parsing.
- **Schema drift vs. code.** The fix was applied as out-of-band DDL directly on preprod Postgres. This is acceptable as a same-incident stopgap but creates schema drift — the *correct* home for this change is hapihub's migration history (see *Correct long-term remediation* above). Until that's in place, a DB restore or PVC rebuild on preprod will silently regress.
- The earlier `CREATE INDEX … USING gin ("record")` on `activity_logs` was kicked off as a non-concurrent, blocking DDL and was cancelled mid-flight. That it was non-concurrent is itself a red flag — whoever/whatever issues that migration should use `CONCURRENTLY`.

## Action items

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Enable `pg_stat_statements` on preprod (and then prod) so slow queries are visible without log scraping | Infra | Medium |
| 2 | **Raise a PR in the hapihub repo** adding a Drizzle migration for this index (non-transactional — see *Correct long-term remediation*) and declare the index in the Drizzle schema. Ship in the next hapihub release; after merge, drop the manual preprod index only if its name differs from the migration's. | HapiHub team | Medium |
| 3 | Audit remaining large tables for PK-only indexing: `activity_logs` (2.1 GB / 1.18 M rows) is the next obvious candidate | Infra | Medium |
| 4 | Investigate why the `CREATE INDEX … USING gin ("record")` on `activity_logs` was non-concurrent and was cancelled. Decide whether to retry it with `CONCURRENTLY` | HapiHub team | Low |
| 5 | Decide whether to apply the same `idx_queue_items_queue_created_at` to production — contingent on user authorization per the prod-change guardrail | Infra + product owner | Low |
| 6 | Add a lightweight Grafana panel or alert on hapihub `duration` p95 for queue operations so the next regression is caught automatically | SRE | Low |
