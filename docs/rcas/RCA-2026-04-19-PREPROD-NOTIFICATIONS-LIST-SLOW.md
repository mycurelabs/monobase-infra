# RCA: Slow `listNotificationNotifications` on Preprod — PK-only Index + JSONB Filter (OPEN)

| Field | Value |
|-------|-------|
| **Date** | 2026-04-19 |
| **Severity** | High (`listNotificationNotifications` averaging 5–6 s; visible any time the notifications bell loads) |
| **Duration** | Chronic — existed as long as `notifications` has been this size on preprod |
| **Services Affected** | HapiHub API on preprod: `GET /notifications` → `listNotificationNotifications` |
| **Environment** | **Preprod only** |
| **Detected By** | Noted during the 2026-04-19 billing-services investigation — showed up as the worst-performing list endpoint in the hapihub log sample |
| **Status** | **OPEN — not yet fixed.** Fix is not as mechanical as the queue_items / medical-tables cases because the likely filter is JSONB-shaped and needs investigation before the correct index type can be chosen. |
| **Related RCAs** | [`RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md`](./RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md), [`RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md`](./RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md) — same family of root cause pattern |

## Summary

`listNotificationNotifications` on preprod averages **6.3 s** (max 7.5 s; n=6 over a 10-min window) and did **not** improve when the medical-tables indexes landed (post-fix sample: **5.06 s** on n=1 — roughly unchanged, which confirms this is a table-specific problem, not cross-workload contention spillover). The `notifications` table is 124 MB / ~61 K rows with **only the primary-key index** — the same PK-only pattern seen in queue_items, medical_records, medical_patients, and personal_details today. However, **the correct fix is not a simple `btree` index**: inspection of the table shows the likely filter column is `viewers` — a JSONB array of role objects like `[{"id": "<userId>", "roles": ["doctor"], "organization": "<orgId>"}]`. Filtering "which notifications can this user see" requires a containment predicate on `viewers`, which a plain btree cannot accelerate; a **GIN index** is the right tool. Before applying one, the exact query hapihub emits should be captured (via slow-query logging or hapihub-side code inspection) so that the index expression matches the filter expression — otherwise the index is built but never used.

## Impact

- User-visible on any UI surface that loads notifications (the bell icon in the top nav, the notifications drawer). Hangs for 5–7 s.
- **No data loss, no errors.**
- Production not affected and not touched.

## Timeline (UTC+8)

| Time | Event |
|------|-------|
| 2026-04-19 ~01:48 | During the billing-services investigation, parsed hapihub logs for all slow list endpoints. `listNotificationNotifications` surfaced at **6272 ms avg / 7487 ms max** (n=6, 10-min window, pre-medical-index). |
| ~01:53 | After the medical-tables indexes landed, re-sampled hapihub logs (5-min window): `listNotificationNotifications` at **5061 ms avg / 5061 ms max** (n=1). **Did not improve**, which differentiates it from the billing-services case — this is a notifications-specific DB problem, not cross-workload contention. |
| ~01:55 | Schema + size check: `notifications` = 124 MB / 60 976 rows, **PK-only**. Classic missing-index shape. |
| ~01:56 | Column inspection to find filter candidates: no facility / account / user scalar columns. Candidates are `type` (text), `created_by` (text), `viewers` (jsonb array), `seen_by` (jsonb array), `expires_at`. Sample `viewers` row: `[{"id": "5bd6d1ed2154f927e8963146", "roles": ["receptionist"], "organization": "5bb1ffa38fb4591e2aca6370"}]`. |
| ~01:57 | Distribution check: `type` cardinality is tiny — 4 distinct values (queue-item=38 661, medical-encounter=18 468, inventory-stock=3 153, inventory-transaction=836). Not selective enough for a plain btree index on `type` alone. |
| ~01:58 | **Paused before applying a fix.** Unlike the queue_items / medical cases, the correct index type depends on whether hapihub's actual SQL uses a containment predicate on `viewers` (→ GIN) or a scalar filter like `created_by` (→ btree). Documenting as an open investigation. |

## Root Cause (partially confirmed)

### Primary (confirmed)

The `notifications` table (124 MB / 61 K rows) has **only its primary-key index**. Every list query therefore pays a full-table-scan tax.

```
Only index: notifications_pkey  PRIMARY KEY, btree (id)
```

### Filter shape (suspected — needs confirmation)

Based on the schema, the most likely "list my notifications" query filters rows where `viewers` contains an object with the current user's `id` (and possibly `organization` / `roles`). In SQL this would look like:

```sql
-- hypothesis A: JSONB containment on viewers.id
WHERE viewers @> '[{"id": "<userId>"}]'::jsonb

-- hypothesis B: JSONB path check
WHERE viewers::jsonb @? '$[*] ? (@.id == "<userId>")'

-- hypothesis C: OR-chain fallback (expensive, unlikely)
WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(viewers) e
              WHERE e->>'id' = '<userId>')
```

None of these can use a plain btree. The correct index family is **GIN**, either:

```sql
-- broad: all containment queries on viewers
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notifications_viewers_gin
  ON notifications USING gin (viewers jsonb_path_ops);

-- narrow (if we only ever query by id): expression index on extracted ids
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notifications_viewer_ids
  ON notifications USING gin ((
    (SELECT jsonb_agg(e->'id') FROM jsonb_array_elements(viewers) e)
  ) jsonb_path_ops);
```

The narrow form is smaller and faster to probe, but only helps if hapihub's query is rewritten to match the index expression. Applying either blindly without seeing hapihub's actual SQL carries a real risk of building a 10–20 MB index that the planner never chooses.

### Why applying a btree now would be wrong

The two scalar-text candidates (`type`, `created_by`) are either too low-cardinality (`type` has only 4 values — dropping 99 % of rows on `type` still leaves 38 K rows for the dominant case) or unlikely to be the user's filter at all (`created_by` is the *sender*, not the recipient). An index on `(type, created_at DESC)` would be built, would be used, but would still read most of the table for the `queue-item` type — not a meaningful improvement.

## Fix

**None applied in this RCA.** Deliberately.

The family of fixes below should be evaluated against the actual hapihub query. Options, in order of likely correctness:

1. **GIN on `viewers`** using `jsonb_path_ops` — broad, likely used for `viewers @> '[{"id": ...}]'` or similar. Recommended first try if the filter is `viewers`-shaped.
2. **Expression GIN index** on extracted ids — smaller and more selective, but requires hapihub's query to target the same expression.
3. **Schema change in hapihub**: instead of `viewers` as an array of JSON objects, introduce a separate `notification_viewers` join table with (`notification_id`, `user_id`) and a btree on `user_id`. That's the cleanest long-term model but is a migration, not a stopgap.

## Is a fix live?

**No.** Nothing was applied for notifications. The previous medical-tables fix indirectly improved every other endpoint via CPU headroom, but measured `listNotificationNotifications` latency remains ~5 s.

## Investigation checklist — to unblock the fix

The next person (or AI session) working this should:

1. **Capture the actual SQL.** On the preprod Postgres, enable slow-query logging briefly:

    ```sql
    ALTER SYSTEM SET log_min_duration_statement = '1000ms';
    SELECT pg_reload_conf();
    -- wait for a user-facing notifications load
    -- tail postgres logs: kubectl -n mycure-preprod logs postgresql-0 -f
    -- when done:
    ALTER SYSTEM RESET log_min_duration_statement;
    SELECT pg_reload_conf();
    ```

2. **OR read hapihub repo source.** Find the `listNotificationNotifications` handler and its Drizzle query. Look at `drizzle/migrations/` and `src/db/schema.ts` (or wherever the `notifications` table is defined) for any existing index hints and the expected filter shape.

3. **Pick the matching index.** Once the SQL is known, choose from the options above.

4. **Apply with `CREATE INDEX CONCURRENTLY`** and verify the planner picks it via `EXPLAIN ANALYZE`.

5. **If the planner does not pick it**, either the query doesn't match the index expression (most common GIN trap) or the planner thinks a seq scan is cheaper. Adjust the query or the index expression accordingly.

## Applying a fix to production (when explicitly authorized)

Production was **not** touched in this incident per the user's standing "never change prod without explicit approval" directive. When a fix is settled in preprod and you are authorized to apply it to production, run the same DDL against `-n mycure-production`.

## Correct long-term remediation (in code, not in the DB)

Same principle as the other RCAs in this set — the DB is the wrong place to own schema decisions long-term. Options:

1. **Drizzle migration + schema index declaration in the hapihub repo**, pointing at whichever index shape matches the actual filter. This is the minimum bar to make the fix survive DB rebuilds.
2. **Schema redesign**: if `viewers` is in practice a `(notification_id, user_id, role, organization)` tuple set, model it as a join table rather than a JSONB array. A small `notification_viewers` table with a btree on `user_id` will outperform any GIN on the array for "my notifications" queries and will make foreign-key-based authorization queries explicit. This is a larger change but is probably the correct target.

### What *not* to do in `mycure-infra`

- Don't apply a GIN index on `viewers` on preprod blindly as a stopgap without confirming the hapihub query uses it. Unlike a btree on a well-known filter column, a GIN on a JSONB column that hapihub's query doesn't match will cost build time and disk with zero runtime benefit. Confirm first, apply second.

## Lessons Learned

### What went well

- Noticed the lack of improvement after the medical-tables fix landed (5061 ms → still 5061 ms) and correctly distinguished this case from the cross-workload-contention pattern that explained billing services. Two visibly similar symptoms, two different root causes.
- Stopped before applying the wrong kind of index. A btree on `type` would have looked reasonable on paper and would have silently failed to help the hot query.

### What went wrong

- No automated visibility into *which* query is slow on which table. Having `pg_stat_statements` (or even just `log_min_duration_statement`) turned on would have given us the exact SQL within minutes. Every missing-index incident today has been found by symptom, not by observability.
- `notifications` table's schema design pre-bakes an indexing problem: a JSONB array of authorization records is a convenient write model and an inconvenient read model. Once the data grows, every "my notifications" list requires either a GIN or a join-table rewrite.

## Action items

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Capture the actual `listNotificationNotifications` SQL (slow-query logging or hapihub-source read), pick the matching GIN index, apply via `CREATE INDEX CONCURRENTLY` on preprod, verify with `EXPLAIN ANALYZE` | Infra + HapiHub team | **High** |
| 2 | Land a Drizzle migration in the hapihub repo that codifies the chosen index (same pattern as the queue_items / medical-tables RCA action items). Declare the index in the Drizzle schema. | HapiHub team | **High** |
| 3 | Evaluate whether the `viewers` JSONB-array model should become a proper `notification_viewers` join table. If yes, plan the migration separately. | HapiHub team | Medium |
| 4 | Install `pg_stat_statements` on preprod (blocked item across all three RCAs today) | Infra | Medium |
| 5 | Apply the settled fix to production when authorized | Infra + product owner | Awaiting auth |
