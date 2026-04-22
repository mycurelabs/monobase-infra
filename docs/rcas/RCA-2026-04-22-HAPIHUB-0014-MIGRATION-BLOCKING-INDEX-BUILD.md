# RCA: Hapihub Migration `0014_preprod_missing_indexes.sql` Takes `ACCESS EXCLUSIVE` Locks — Prod Deploy Would Block `medical_records` Writes for 5–15 min

| Field | Value |
|-------|-------|
| **Date** | 2026-04-22 |
| **Severity** | **High (forward-looking risk)** — no incident yet; will cause a multi-minute write outage on `medical_records` the moment any hapihub version containing `0014` rolls out to production |
| **Status** | **Open — fix required in hapihub repo before prod upgrade** |
| **Services at risk** | HapiHub API (write paths on `queue_items`, `medical_records`, `medical_patients`, `personal_details`, `insurance_coverages`) |
| **Environment** | Risk materializes on **any** environment with prod-scale data. Preprod won't fully surface it (tables are smaller than prod). |
| **Detected by** | Code review of hapihub `drizzle-pg/0014_preprod_missing_indexes.sql` (commit `8e3a36c2`, introduced Apr 22 2026) while verifying the preprod DB restore test |
| **Related RCAs** | [`RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md`](./RCA-2026-04-19-PREPROD-QUEUE-ITEMS-SLOW.md), [`RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md`](./RCA-2026-04-19-PREPROD-MEDICAL-TABLES-SLOW.md), [`RCA-2026-04-19-PREPROD-BILLING-INVOICES-N-PLUS-1.md`](./RCA-2026-04-19-PREPROD-BILLING-INVOICES-N-PLUS-1.md) — `0014` is the hapihub team's codification of the stopgap indexes these RCAs documented |
| **Fix Commit** | N/A — awaiting change in hapihub repo |

## Summary

The hapihub team shipped migration `0014_preprod_missing_indexes.sql` in commit `8e3a36c2`, codifying 5 of the 6 preprod stopgap indexes we'd applied manually during the Apr 19–20 performance investigations (`queue_items`, `medical_records`, `medical_patients`, `personal_details`, `insurance_coverages`). Same names, same columns, same sort orders as our ad-hoc DDL. This is the correct long-term fix — every RCA from Apr 19 asked for exactly this, and the hapihub team delivered.

However, `0014` uses plain `CREATE INDEX IF NOT EXISTS` rather than `CREATE INDEX CONCURRENTLY`. Drizzle wraps each migration file in `BEGIN ... COMMIT`, and Postgres forbids `CREATE INDEX CONCURRENTLY` inside a transaction, so a transactional migration is forced into the plain (blocking) variant. Plain `CREATE INDEX` takes **`ACCESS EXCLUSIVE`** on the target table for the entire duration of the scan. On prod-scale `medical_records` (preprod alone is 3.8 GB / 3.5 M rows; prod is larger), that lock would hold for **~5–15 minutes**, during which every write to `medical_records` blocks and every read that acquires a row-level lock stalls. A medical system cannot tolerate a 5–15 minute write outage on records without triggering operational and clinical-safety issues.

The hapihub team has already demonstrated they know how to handle this — migrations `0012_patient_search_indexes.sql` and `0013_patient_search_middle_name.sql` contain an explicit operator-runbook docstring saying "run the `CONCURRENTLY` variant manually before deploying; the migration then becomes a no-op via `IF NOT EXISTS`". That's a viable pattern for an ops team willing to do manual pre-deploys. **It does not fit this org's policy of "code owns schema; ops does not run DDL manually"** — a policy we've respected through every preprod index fix to date. The fix for `0014` must therefore happen in the hapihub repo, not at the ops layer.

## Impact (if deployed as-is to production)

- **Primary**: `ACCESS EXCLUSIVE` on `medical_records` for the duration of the index build.
  - Estimated **5–15 min** at prod scale. Every write path (new record, signoff, edit, classify, finalize) blocks. Every concurrent reader that tries to acquire a row lock blocks.
- **Secondary**: `ACCESS EXCLUSIVE` on `queue_items` for 1–2 min. Queue management UI and patient-flow workflows stall.
- **Minor**: Sub-minute locks on `medical_patients`, `personal_details`, `insurance_coverages`. Annoying but not outage-grade.
- **Deployment cascade**: hapihub rolling update can't proceed until the first pod finishes migrations. If any migration exceeds the pod's startup probe grace period, the pod is killed mid-migration; rollout stalls with a half-applied state.
- **Clinical-safety implication**: for a healthcare SaaS, a 5–15 minute window where clinicians can't save patient records is a user-trust incident regardless of how it's framed internally.

## Evidence

### `drizzle-pg/0014_preprod_missing_indexes.sql` full content

```sql
CREATE INDEX IF NOT EXISTS "idx_queue_items_queue_created_at"        ON "queue_items"        USING btree ("queue","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_medical_records_patient_created_at"  ON "medical_records"    USING btree ("patient","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_medical_patients_facility_created_at" ON "medical_patients"  USING btree ("facility","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_personal_details_facility_created_at" ON "personal_details"  USING btree ("facility","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_insurance_coverages_contract"        ON "insurance_coverages" USING btree ("contract");
```

No docstring. No large-tenant caveat. No `CONCURRENTLY`.

### Compare with `0012_patient_search_indexes.sql` (handled correctly)

That file has an 83-line docstring explaining the lock behavior, giving operators an explicit pre-deploy script with `CREATE INDEX CONCURRENTLY` variants, and noting "any tenant with a large `personal_details` or `medical_patients` table — rule of thumb: 100k+ rows in either — operators MUST run the CONCURRENTLY variants BELOW manually against that tenant's DB BEFORE deploying a hapihub version containing this migration."

The hapihub team knew to write this for `0012`. They didn't write it for `0014`.

### Expected vs. observed lock duration (benchmarks)

Rough sizing from preprod heap scans, extrapolated:

| Table | Preprod rows | Preprod heap | Build time (preprod, non-concurrent) | Expected prod build time |
|---|---|---|---|---|
| `queue_items` | 944 K | 578 MB | ~15 s | ~1–3 min |
| `medical_records` | 3.55 M | 3.8 GB heap / 3.09 GB heap alone | ~1 min (preprod, 1 CPU contention-free) | **~5–15 min at prod concurrency** |
| `medical_patients` | 480 K | 183 MB | seconds | ~30 s |
| `personal_details` | 495 K | 187 MB | seconds | ~30 s |
| `insurance_coverages` | 31 K | 9 MB | < 1 s | < 5 s |

On preprod, the `CREATE INDEX CONCURRENTLY` we ran Apr 19 completed in under 60 s on `medical_records`. The non-concurrent variant would be slightly faster (no two-phase index build) but holds the exclusive lock the whole time. On prod hardware with larger data volumes and active writes competing for WAL / buffer cache, expect this window to blow out.

## Root Cause

Two compounding factors:

### 1. Drizzle wraps each migration in a transaction

Drizzle's migration runner (`drizzle-kit migrate` / `@drizzle-orm/pg-core` applyMigrations) executes each migration file inside `BEGIN ... COMMIT`. This is the correct safety default for most DDL (rollback on failure), but it **forces every `CREATE INDEX` into the non-concurrent variant** because Postgres rejects `CREATE INDEX CONCURRENTLY` with `ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block` (SQLSTATE 25001).

### 2. `0014` doesn't opt out of the transaction

The hapihub team's Drizzle setup appears to support per-file transaction opt-out (via a pragma comment or config flag in drizzle.pg.config.ts — exact mechanism is Drizzle-version-specific). Migrations `0012` and `0013` didn't opt out either, but they compensated with an operator-docstring pre-deploy step. `0014` has neither opt-out nor docstring.

### 3. Organizational policy conflicts with the `0012`/`0013` pattern

The docstring pattern in `0012`/`0013` assumes ops will run `CREATE INDEX CONCURRENTLY` manually before the deploy. For this org, **operators explicitly do not run manual DDL**: schema ownership lives with the app, and every preprod index fix in the RCAs above was written to be migrated in hapihub rather than left as ops-side DDL. So even if `0014` had inherited `0012`'s docstring, the prescribed manual step wouldn't be executed, and the non-concurrent migration would run on deploy day regardless.

The intersection of these three factors is what creates the risk: transactional migrations + no manual pre-deploy step available + a large table in the index list.

## Fix (required, in hapihub repo)

Three options, ranked by correctness:

### Option A — Mark `0014` as a non-transactional migration (recommended)

Drizzle-kit supports per-file transaction control. Depending on the Drizzle version in use, this is done via one of:

- A pragma comment at the top of the `.sql` file (some Drizzle versions respect `-- breakpoint` or `--> statement-breakpoint` plus a metadata flag).
- A TypeScript migration file (`.ts` instead of `.sql`) that explicitly opens its own connection and runs DDL outside the transaction — useful when the migration needs fine control.
- A `drizzle.pg.config.ts` flag setting migration mode for specific files.

Rewrite `0014` as a non-transactional migration containing:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_queue_items_queue_created_at"         ON "queue_items"         (queue, created_at DESC NULLS LAST);
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_medical_records_patient_created_at"   ON "medical_records"     (patient, created_at DESC NULLS LAST);
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_medical_patients_facility_created_at" ON "medical_patients"    (facility, created_at DESC NULLS LAST);
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_personal_details_facility_created_at" ON "personal_details"    (facility, created_at DESC NULLS LAST);
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_insurance_coverages_contract"         ON "insurance_coverages" (contract);
```

Each `CREATE INDEX CONCURRENTLY` runs in its own implicit transaction (Postgres's concurrent index build pattern). No `ACCESS EXCLUSIVE` lock — only `SHARE UPDATE EXCLUSIVE`, which does not block normal reads or writes. Build time is the same total wall-clock, but writes keep flowing. On prod's `medical_records`, the build still takes minutes, but **no user-facing outage**.

Caveat: if `CREATE INDEX CONCURRENTLY` fails mid-build (e.g., migration runner crash, connection drop), Postgres leaves an `indisvalid = false` index in the catalog. Drizzle needs to handle this — either by `DROP INDEX ... ; CREATE INDEX CONCURRENTLY ...` at the top of the migration, or by a cleanup step that drops any invalid index with a matching name before rebuilding. `0012` and `0013` document this recovery procedure but don't automate it; it'd be worth codifying.

### Option B — Split `0014` into per-index non-transactional files

Five separate migrations (`0014_index_queue_items.sql`, `0015_index_medical_records.sql`, etc.), each containing a single `CREATE INDEX CONCURRENTLY` and marked non-transactional. Same net effect as Option A. More files, but each one is independently recoverable — if one fails, the others proceed on the next deploy.

### Option C — Add the `0012`/`0013`-style operator docstring to `0014`

Not recommended **for this org** because it presumes ops runs manual DDL pre-deploy, which conflicts with the established "code owns schema" policy. Might be the right answer for a different org. If the hapihub team ships other tenants with different ops models, the docstring pattern is a reasonable fallback for those tenants — but for this one, Option A should be the default.

## What NOT to do

- **Do not** run `CREATE INDEX CONCURRENTLY` manually on prod before the deploy as a workaround. That would make the policy inconsistent and re-introduces the exact schema-drift problem we spent two days documenting in the Apr 19–20 RCAs.
- **Do not** deploy hapihub `11.2.19` (or any version containing `0014`) to production until this is fixed. A controlled pre-announced maintenance window is an option if absolutely necessary, but ask the hapihub team for a fix first.
- **Do not** add a mono-infra-side pre-sync hook that runs DDL. Same reason — that's ops running DDL by another name.

## Verification steps once the fix ships

1. Hapihub team releases a new patch (e.g., `11.2.20`) where `0014` is non-transactional (Option A) or split (Option B).
2. Deploy to preprod. `pg_stat_progress_create_index` during the rollout should show `phase = building index, concurrent build` — confirming CONCURRENTLY is being used.
3. Simulate a prod-scale rollout: **before the deploy**, kick off a synthetic write workload against `medical_records` (small UPDATE spray every 500 ms). During the migration, verify the writes keep succeeding without > 1 s stalls. If they block for minutes, the migration is still non-concurrent and needs another round.
4. Measure total migration time. If it's close to prod's RTO budget, flag it. But non-concurrent is the hard no; any concurrent build time is tolerable because user-facing paths stay open.

## Lessons Learned

### What went well

- The hapihub team codified the 5 preprod stopgap indexes correctly (right names, right columns, right sort order) based purely on the RCA documents from Apr 19–20. Zero back-and-forth needed. That's a good signal that the RCA format is useful to the eventual implementer.
- They already knew how to handle the lock problem — `0012`/`0013` demonstrate the knowledge exists on the team. This is a forgotten detail, not a missing skill.

### What went wrong

- `0014` regressed the migration-safety pattern from `0012`/`0013`. A CR checklist that asks "does this migration take `ACCESS EXCLUSIVE` on a table with > 1 M rows? If yes, either mark non-transactional or add the docstring" would have caught it.
- Catching this required reading the migration file by hand. There is no CI check (yet) that flags `CREATE INDEX` without `CONCURRENTLY` on tables above a size threshold. Could be a simple lint — the hapihub team should consider adding one.
- The gap is invisible on preprod-sized data. `medical_records` at 3.8 GB completes in a minute on preprod; the lock duration would feel "annoying but survivable". At prod scale, the same migration is a small outage. Preprod testing alone will not catch this kind of regression unless traffic is deliberately being applied during the migration.

### What this reveals about preprod as a prod predictor

Preprod still isn't a reliable oracle for migration impact:

- Preprod's `medical_records` is smaller than prod's (cloned subset + writes diverge after the clone).
- Preprod has 1 hapihub replica vs prod's 5; pod-kill-on-slow-migration behavior is different.
- Preprod is single-postgres-primary; prod has primary + read replica with WAL replay lag considerations.

A prod deploy of `0014` could behave meaningfully worse than preprod predicts. Fixing the `CONCURRENTLY` issue removes this whole class of uncertainty because the migration no longer holds an exclusive lock — whether it takes 1 min or 20 min at prod scale becomes a performance note rather than a correctness/availability issue.

## Action items

| # | Action | Owner | Priority |
|---|--------|-------|----------|
| 1 | Hapihub team rewrites `0014` as a non-transactional migration using `CREATE INDEX CONCURRENTLY` (Option A above). Ship as next patch (e.g. `11.2.20`). | HapiHub team | **High — blocking prod upgrade** |
| 2 | Also codify the missing `idx_notifications_viewers_gin` (GIN on `notifications.viewers` with `jsonb_path_ops`) as part of the same migration — still stopgap-only in preprod, not yet in hapihub code. | HapiHub team | **High** |
| 3 | Add a CI or pre-merge lint that flags `CREATE INDEX` (without `CONCURRENTLY`) in any migration targeting a table above a row-count threshold. Prevents this class of regression. | HapiHub team | Medium |
| 4 | Codify an automated recovery path for `indisvalid = false` indexes (concurrent build failed mid-way). Either drop-and-retry at the start of each migration, or a startup self-heal step. | HapiHub team | Medium |
| 5 | Do **not** apply `0014` by running it manually on prod, and do **not** deploy a hapihub version containing `0014` to prod, until Action #1 ships. This is a cross-team coordination item — infra should block the prod image bump PR until the hapihub side is fixed. | Infra | **High** |
| 6 | Re-verify the fix on preprod with synthetic write load during the migration (step 3 of the verification procedure above). Preprod-scale alone won't catch the regression; you need to prove writes stay non-blocked. | Infra + HapiHub team | Medium |
| 7 | Consider whether this policy ("code owns schema, ops does not run DDL") should be formalized in a written infra doc so future migrations like `0012`/`0013` don't get shipped assuming ops will run `CONCURRENTLY` out-of-band. | Infra | Low |
