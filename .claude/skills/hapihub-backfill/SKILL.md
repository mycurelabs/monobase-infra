---
name: hapihub-backfill
description: Use this skill whenever the user asks to run, seed, or backfill a hapihub ANALYTICS ROLLUP in a Kubernetes cluster — e.g. "backfill analytics", "seed the analytics rollup", "run the daily-counts backfill", "populate analytics_daily_counts", or "list the analytics backfills". It runs the `hapihub backfill` CLI (compiled into the v11 hapihub binary) via `kubectl exec` against the correct deployment, with the repo's standard cluster-access resolution and a pre-run confirmation. Idempotent and safe.
version: 1.0.0
---

# hapihub-backfill

Run hapihub's analytics rollup **backfills** in a k8s cluster. The backfill CLI is a registry compiled into the hapihub binary (`hapihub backfill [name] [--list]`). It one-shot recomputes a derived/rollup table from source data — idempotent, bounded (stops at "now"), and disposable.

> Source-of-truth for the backfill design + the "how to add a new one" recipe is in the **mycure monorepo**: `services/hapihub/docs/runbooks/analytics-backfills.md`. This skill is only the **operational k8s runner**.

## Before anything: resolve cluster access

This skill **does not** resolve kubeconfig/context itself. **Apply the `kubectl-access` skill first** to obtain `--kubeconfig <path>` and `--context <ctx>`, and pass those flags on **every** `kubectl` invocation. Never `export KUBECONFIG` or `kubectl config use-context` (keep the shell hermetic). Below, `$KC`/`$CTX` denote the resolved flags.

## Target deployment — IMPORTANT

The backfill CLI exists **only in hapihub v11** (`>= 11.10.0`). In this infra the v11 hapihub is the **`hapihub-next`** release (resources named `hapihub-next`), NOT the canonical `hapihub` (which is v10/Mongo and has no `backfill` subcommand).

- **Deployment:** `deploy/hapihub-next`
- **Namespace:** `mycure-production` (production) — or `mycure-preprod` (pre-prod). **Confirm the environment with the user** before running against production.

## Procedure

1. **Resolve access** (kubectl-access skill) → `$KC $CTX`.
2. **Confirm environment** with the user (production vs preprod) → set `NS` (`mycure-production` default).
3. **Verify the CLI is present** (guards against the v10 deploy / a pre-11.10.0 image):
   ```bash
   kubectl $KC $CTX -n $NS exec deploy/hapihub-next -- hapihub backfill --list
   ```
   - If this errors with "unknown command"/usage, the deployed image predates the backfill CLI (< 11.10.0) or you hit the wrong deployment. **Stop** and tell the user the analytics version isn't deployed yet (it ships with hapihub `11.10.0`).
4. **Confirm the run** with the user (it writes to prod — though idempotent + disposable; see Safety). State which backfill + namespace.
5. **Run it** (non-interactive; it runs to completion and exits 0):
   ```bash
   # one backfill
   kubectl $KC $CTX -n $NS exec deploy/hapihub-next -- hapihub backfill <name>
   # all registered backfills
   kubectl $KC $CTX -n $NS exec deploy/hapihub-next -- hapihub backfill
   ```
   Stream/relay the log output (it logs `backfill: running…` / `backfill: done`).
6. **Report** the result. Optionally sanity-check (see Verify).

## Available backfills

Always discover them live with `--list` (the registry grows as analytics is added). At time of writing:

| name | what it backfills |
|---|---|
| `analytics-daily-counts` | `analytics_daily_counts` — historical per-day counts for medical patients/records/encounters (powers the dashboard clinical trends) |

## Safety (why this is low-risk)

- **Idempotent** — keyed by stable id (`collection:day:dim`) with upsert; re-running overwrites the same rows. Run it as many times as needed.
- **Bounded** — freezes a cutoff = now and processes a finite range, then exits. No daemon, no loop.
- **Not a prerequisite** — the nightly keep-current jobs maintain rollups going forward, and the read endpoints fall back to a **live query** when a rollup is empty. So the dashboard is correct with or without a backfill; this only pre-aggregates history (or repairs a gap after downtime).
- **Disposable / trivial revert** — rollup tables are derived. If a result ever looks wrong, the revert is simply truncating the table (reads fall back to live, and a re-run/nightly job rebuilds it):
  ```sql
  TRUNCATE analytics_daily_counts;
  ```
  (run against the cluster's Postgres — via the DB pod / your usual psql access).

## Verify (optional)

After a run, confirm rows landed (requires DB access in the cluster; adapt to how psql is reached here, e.g. exec into the postgres pod):
```sql
SELECT collection, count(*) AS days, sum(count) AS total
FROM analytics_daily_counts GROUP BY collection;
```

## Do NOT

- Do **not** target `deploy/hapihub` (v10/Mongo — no `backfill` CLI).
- Do **not** run `bun run scripts/play/...` in the pod — the prod image is a **compiled binary** with no source/`bun`; only the `hapihub <subcommand>` form works.
- Do **not** mutate shell state for kubeconfig/context — pass flags per the `kubectl-access` skill.
