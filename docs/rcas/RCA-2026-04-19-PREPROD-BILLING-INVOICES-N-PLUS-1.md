# RCA: Slow Billing Invoice Operations on Preprod — N+1 Query on Unindexed `insurance_coverages.contract`

| Field | Value |
|-------|-------|
| **Date** | 2026-04-19 |
| **Severity** | High (`listBillingInvoiceLegacies` max 31.9 s; `listBillingInvoiceItems` max 8.8 s; `retrieveBillingInvoiceLegacy` avg 823 ms) |
| **Duration** | Chronic — existed as long as `insurance_coverages` has been this size on preprod |
| **Services Affected** | HapiHub API on preprod: `listBillingInvoiceLegacies`, `retrieveBillingInvoiceLegacy`, likely the 8.8 s tail of `listBillingInvoiceItems` |
| **Environment** | **Preprod only** |
| **Detected By** | Followup to the billing-services investigation — user asked for billing-items / invoice analysis. Live-query sampling on preprod Postgres caught `SELECT count(*) FROM insurance_coverages WHERE contract = $1` being issued **3 times in a 10-second window**, confirming an N+1 pattern. |
| **Related RCAs** | [`queue_items`](./RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md), [`medical tables`](./RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md), [`billing services (search)`](./RCA-2026-04-19-PREPROD-BILLING-SERVICES-SEARCH-SLOW.md), [`notifications (open)`](./RCA-2026-04-19-PREPROD-NOTIFICATIONS-LIST-SLOW.md) |
| **Fix Commit** | None. Applied as direct DDL on preprod Postgres (see *Fix* below). |

## Summary

Billing invoice list/retrieve endpoints on preprod were spiking to tens of seconds (`listBillingInvoiceLegacies` max 31.9 s on a **29-row** table). The large billing tables were already reasonably indexed — `billing_items` has five non-PK indexes, and seq-scanning `billing_legacy_invoices` at 88 KB / 29 rows is effectively free — so the root cause was **not** a simple missing-index-on-the-primary-table pattern seen in the queue_items or medical_tables RCAs. Instead, live-query sampling on Postgres revealed that during billing-invoice requests, hapihub repeatedly issues `SELECT count(*) FROM insurance_coverages WHERE contract = $1` — once per contract on the invoice, and the call does a full sequential scan of `insurance_coverages` (9 MB / 30 K rows) because there is **no index on the `contract` column**. Each seq scan is 11.5 ms; run in a tight loop over many contracts on many invoices, the latency compounds to the 32 s tail. Adding a non-blocking btree on `insurance_coverages(contract)` drops the per-call cost from 11.5 ms to **0.057 ms** (≈200×) and the planner picks `Index Only Scan`. This is a **stopgap**: the real fix is to eliminate the N+1 in the hapihub handler.

## Impact

- User-visible: invoice list/retrieve endpoints hang for multiple seconds, worst case tens of seconds.
- **No data loss, no errors** — HTTP 200s throughout.
- Production was not affected and was not touched.

## Timeline (UTC+8)

| Time | Event |
|------|-------|
| 2026-04-19 ~01:58 | After the billing-services + notifications RCAs, user asks to check billing items / invoices specifically |
| ~01:59 | Parsed hapihub logs (30-min window): `listBillingInvoiceLegacies` avg 3.0 s / max 31.9 s (n=12), `listBillingInvoiceItems` avg 136 ms / max 8.8 s (n=71), `retrieveBillingInvoiceLegacy` avg 823 ms (n=16) |
| ~02:00 | Schema / size check: `billing_items` (1989 MB / 2.16 M rows, **5 non-PK indexes**), `billing_invoices` (811 MB / 1.47 M rows, `(facility, status, created_at)` index present but 0 scans in recent window), `billing_payments` (541 MB / 1.56 M rows, PK-only — but no listBillingPayments traffic observed), `billing_legacy_invoices` (**88 KB / 29 rows** — the table itself is tiny, so the 32 s can't be a table scan) |
| ~02:01 | Enabled `log_min_duration_statement = 500ms` on preprod Postgres via `ALTER SYSTEM` + `SELECT pg_reload_conf()` |
| ~02:02 | Live-query sampling via `pg_stat_activity` caught the smoking gun: `SELECT count(*) FROM insurance_coverages WHERE contract = $1` appearing 3 times inside a 10-second sampling loop — confirmed N+1 |
| ~02:03 | Checked `insurance_coverages`: 9 MB / 30 K rows, **only PK**, no index on `contract`. `EXPLAIN ANALYZE` on the count query: **Seq Scan, 11.45 ms, 968 shared buffers read** |
| ~02:04 | User authorized the fix |
| ~02:05 | `CREATE INDEX CONCURRENTLY idx_insurance_coverages_contract ON insurance_coverages (contract)` — succeeded, `indisvalid = true`, 392 KB index |
| ~02:06 | Re-ran the same EXPLAIN: plan switched to `Index Only Scan`, **0.057 ms** — ≈200× faster per call |

## Root Cause

### Primary

`insurance_coverages` has no index on its `contract` column. Every `SELECT ... WHERE contract = $1` on the table does a full Parallel Seq Scan of all 30 K rows, reading 968 shared buffers (~8 MB) per call and taking ~11.5 ms.

```
Only index (before):  insurance_coverages_pkey  PRIMARY KEY, btree (id)
```

### Amplifier: N+1 in the billing handler

The handler path behind `listBillingInvoiceLegacies` / `retrieveBillingInvoiceLegacy` / the tail of `listBillingInvoiceItems` issues `SELECT count(*) FROM insurance_coverages WHERE contract = $1` once **per contract per invoice** (inferred from live-query sampling — 3 occurrences of the same shape within a 10-second window during otherwise-quiet preprod traffic). So the total latency is:

```
total ≈ (number of invoices) × (avg contracts per invoice) × 11.5 ms
        + ORM round-trip overhead per call
```

For a worst-case list with many invoices and many contracts per invoice, this easily reaches tens of seconds even though no single query is slow enough to look suspicious in isolation. This is **the** classic N+1 signature: many small fast queries that aggregate into a catastrophic total.

### Why the "missing-index-on-the-big-table" pattern didn't apply here

Unlike queue_items (578 MB, PK-only) or medical_records (3.8 GB, PK-only), the primary billing tables were already indexed well:

| Table | Size | Rows | Non-PK indexes |
|---|---|---|---|
| `billing_items` | 1989 MB | 2.16 M | **5** — including `(invoice)` (433 scans), `(facility, invoice_type)` (2 scans) |
| `billing_invoices` | 811 MB | 1.47 M | **1** — `(facility, status, created_at)` (0 scans in sample window, but present) |
| `billing_payments` | 541 MB | 1.56 M | 0 — but no list op seen in 30 min of logs |
| `billing_legacy_invoices` | 88 KB | **29** | 0 — seq scan of 29 rows is 0.1 ms, indexing makes no sense |

The handler is doing the right thing for the big tables. It's the *auxiliary lookup* (`insurance_coverages`) that has no index — and that auxiliary lookup is in a loop.

## Fix

**Applied directly to preprod Postgres** (no change in git):

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_insurance_coverages_contract
  ON insurance_coverages (contract);
```

### Why `CONCURRENTLY` + `IF NOT EXISTS`

- Non-blocking: reads and writes on `insurance_coverages` continue uninterrupted during the build (which on a 30 K-row table is seconds).
- `IF NOT EXISTS` makes the DDL idempotent and safe to replay.

### Why btree (and not GIN or anything fancier)

- The filter is a scalar `=` on a `text` column — a vanilla btree is exactly the right shape.
- The column is declared `NULL`able but in practice rarely null; if it's null often, the planner still benefits because the index is much smaller than the heap and scans still win.

### Measured improvement

| | Plan | Time | Buffers read |
|---|---|---|---|
| **Before** | `Seq Scan on insurance_coverages` | **11.45 ms** | shared hit=968 (~8 MB) |
| **After** | `Index Only Scan using idx_insurance_coverages_contract` | **0.057 ms** | shared hit=2 |

Per-call speedup: ~200×. **End-to-end request speedup is bounded by how many times the N+1 fires per request** — if the handler issues 1000 of these in a loop, 1000 × 11.4 ms (11.4 s) collapses to 1000 × 0.06 ms (60 ms), plus ORM round-trip overhead which the index does not reduce.

### What the fix does NOT do

- **Does not eliminate the N+1.** Hapihub still issues N serial round trips, each just much faster. The real fix is on the hapihub side — batch the lookup with a single `WHERE contract = ANY($1)` or a JOIN against `insurance_coverages`.
- **Does not address the 8.8 s tail on `listBillingInvoiceItems`.** That tail is a different query shape — likely a filter that misses the 5 existing `billing_items` indexes. Separate investigation.
- **Does not address the `billing_payments` PK-only state.** We didn't observe `listBillingPayments` traffic, so it's unclear whether it's actually exercised on preprod. If it becomes hot, expect the queue_items / medical_records pattern to apply.

## Is the fix live?

**Yes — live on preprod right now.** `idx_insurance_coverages_contract` exists, `indisvalid = true`, and the planner is using `Index Only Scan` (confirmed by post-fix `EXPLAIN`).

Same persistence / permanence caveats as the earlier RCAs in this family:

| Scenario | Outcome |
|---|---|
| `postgresql-0` pod restart | ✅ Index persists (on-disk in the PVC) |
| Hapihub redeploy / version bump | ✅ Index persists |
| Normal hapihub migration runner at startup | ✅ Index persists (runner only applies *new* migrations) |
| **DB restored from pre-2026-04-19 backup** | ❌ Index missing |
| **PVC destroyed + DB re-seeded** | ❌ Index missing |
| **Future `drizzle-kit push`-style schema sync** | ❌ Can silently DROP |

In short: **durable against day-to-day operations, not durable against schema resets.** The only permanent fix is a Drizzle migration in the hapihub repo.

Production was **not** touched. Production's `insurance_coverages` table has the same PK-only shape; if similar slowness is reported there, apply the same command with `-n mycure-production` (but verify table size first and seek explicit authorization per the prod-change guardrail).

## Revert instructions

```bash
PGPW=$(kubectl -n mycure-preprod get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

# Confirm presence
kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "SELECT indexrelid::regclass, indisvalid, pg_size_pretty(pg_relation_size(indexrelid))
      FROM pg_index
      WHERE indexrelid::regclass::text = 'idx_insurance_coverages_contract';"

# Drop non-blockingly
kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "DROP INDEX CONCURRENTLY IF EXISTS idx_insurance_coverages_contract;"
```

`DROP INDEX CONCURRENTLY` takes only a `SHARE UPDATE EXCLUSIVE` lock — non-blocking for reads and writes. `IF EXISTS` makes it idempotent. Dropping it will restore the 11.5 ms seq-scan floor per call and the tens-of-seconds tail on invoice-legacy endpoints.

## Applying to production (when explicitly authorized)

```bash
PGPW=$(kubectl -n mycure-production get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

# Size check first
kubectl -n mycure-production exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "SELECT pg_size_pretty(pg_total_relation_size('insurance_coverages')),
             (SELECT count(*) FROM insurance_coverages);"

# Apply concurrently
kubectl -n mycure-production exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_insurance_coverages_contract \
      ON insurance_coverages (contract);"
```

Expected build time: seconds, since the preprod table was only 9 MB. Production may be larger — estimate by checking `pg_total_relation_size('insurance_coverages')` first.

Note: production is currently on hapihub 10.x, not 11.2.x. The `insurance_coverages` table and the N+1 pattern in the billing handler should exist in both, but verify with `\d insurance_coverages` first.

## Correct long-term remediation (in code, not in the DB)

Two separate changes in the **hapihub** repo. Both are needed:

### 1. Codify the index in a Drizzle migration

Same shape as the other RCAs. Add:

```sql
-- drizzle:non-transactional
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_insurance_coverages_contract
  ON insurance_coverages (contract);
```

…plus declare the index in the Drizzle schema definition for `insurance_coverages`. That guarantees the fix applies to every environment (production, staging, on-prem, future tenants) and survives DB rebuilds / restores.

### 2. Eliminate the N+1 in the billing-invoice handler

**This is the bigger win.** Even with the index, each N+1 call pays hapihub ↔ Postgres round-trip overhead (connection pool, network, ORM serialization) — on a co-located VPC that's typically 0.5–2 ms per round trip. For 1000 calls per request that's still 0.5–2 seconds of pure overhead that the index cannot remove.

Depending on how hapihub consumes the result, the replacement pattern is one of:

```sql
-- A) If the handler only needs counts per contract:
SELECT contract, count(*) AS coverage_count
FROM insurance_coverages
WHERE contract = ANY($1::text[])
GROUP BY contract;

-- B) If it needs the coverage rows themselves:
SELECT * FROM insurance_coverages
WHERE contract = ANY($1::text[]);

-- C) If it's used to decorate invoices already being fetched:
LEFT JOIN LATERAL (
  SELECT count(*) AS coverage_count
  FROM insurance_coverages
  WHERE contract = billing_invoices.contract
) c ON true
```

All three collapse the N round-trips into 1. Whichever shape matches the hapihub handler's ergonomic needs is correct.

### What *not* to do in `mycure-infra`

- Don't add a Helm post-install Job running this DDL. Schema belongs with the app, same rationale as the earlier RCAs.

## Lessons Learned

### What went well

- Used live `pg_stat_activity` sampling as a cheap replacement for `pg_stat_statements`. Caught the repeated `count(*) FROM insurance_coverages` pattern in a 10-second window — decisive evidence of N+1 without needing slow-query logging.
- Checked `pg_stat_user_indexes` before assuming the primary billing tables were unindexed — they weren't. Saved time that would have been wasted on cargo-culting queue_items-style indexes onto `billing_items`.
- `Index Only Scan` on the new index (the planner doesn't even need to hit the heap for `count(*)`) — the composite win of "right column + right query shape" for this lookup.

### What went wrong

- **Fifth occurrence today of "symptom detected by user, not by observability."** No `pg_stat_statements`, no query-level Grafana, so every slow-query problem this session was found by someone complaining and someone else manually sampling `pg_stat_activity`. This does not scale.
- **N+1 patterns are silent.** No single query is slow enough to cross any reasonable slow-query threshold (11 ms per call is fine in isolation). Detection requires either (a) query-count-per-request metrics, which hapihub doesn't emit, or (b) correlating spikes in `calls` on `pg_stat_statements` — which isn't installed. A structured APM (Datadog / Sentry traces) would surface the pattern immediately.
- **Four stopgap indexes now exist only in preprod DB state** — queue_items, medical_records, medical_patients, personal_details, insurance_coverages. That's five out-of-band schema changes in a single day. Each additional one raises the cost of a DB restore or PVC rebuild. We need the hapihub migrations landed before this list grows further.

## Action items

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Raise a PR in the **hapihub** repo adding a Drizzle migration for `idx_insurance_coverages_contract`, and declare the index in the Drizzle schema. Bundle with the other four pending indexes from 2026-04-19 RCAs. | HapiHub team | **High** |
| 2 | Fix the N+1 in the billing-invoice handler. Replace per-contract `SELECT count(*)` calls with a single `WHERE contract = ANY($1::text[])` query (or JOIN). This is the larger latency win. | HapiHub team | **High** |
| 3 | Investigate the 8.8 s tail on `listBillingInvoiceItems` — likely a different query shape missing the 5 existing `billing_items` indexes. Enable `log_min_duration_statement` (already done on preprod), capture a slow instance, `EXPLAIN` it | HapiHub team + Infra | Medium |
| 4 | Install `pg_stat_statements` on preprod and production. Add a Grafana panel sorted by `total_exec_time` and one by `calls` — the `calls` panel catches N+1 patterns that the `total_exec_time` panel misses. | Infra | **High** (blocked on multiple RCAs now) |
| 5 | Audit `billing_payments` (541 MB, PK-only) and `billing_invoice_agts` (76 MB, PK-only) — no traffic observed today, but same PK-only shape; if they become hot the same remediation pattern applies | Infra + HapiHub team | Low |
| 6 | Apply the same index to production when authorized | Infra + product owner | Awaiting auth |

## Observability change applied during this investigation

For the duration of this incident, `log_min_duration_statement = 500ms` was enabled on preprod Postgres via `ALTER SYSTEM` + `pg_reload_conf()`. Every query slower than 500 ms is now logged to the `postgresql-0` pod stdout. This is a low-cost diagnostic aid and has been left on — consider making it permanent in preprod (and installing it properly in production) as part of action item #4.

To disable:

```bash
PGPW=$(kubectl -n mycure-preprod get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "ALTER SYSTEM RESET log_min_duration_statement;"

kubectl -n mycure-preprod exec postgresql-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "SELECT pg_reload_conf();"
```
