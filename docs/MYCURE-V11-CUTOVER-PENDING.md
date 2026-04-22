# MyCure v11 Cutover — Pending Followups

**Context:** Phase A of the v11 cutover landed on 2026-04-22. See [`docs/MYCURE-V11-CUTOVER-PHASE-A-2026-04-22.md`](MYCURE-V11-CUTOVER-PHASE-A-2026-04-22.md) for what shipped and why.

This document lists the **outstanding work** — nothing here is urgent, nothing here is user-facing broken. Each item can be done on its own schedule.

---

## Tracker

| # | Item | Priority | Owner | When |
|---|---|---|---|---|
| 1 | **Phase B — canonical URL swap** (v11 takes `hapihub.localfirsthealth.com`, v10 moves to `hapihub-legacy.localfirsthealth.com`) | Medium | Infra | After a few days/weeks of v11 stability |
| 2 | **Export archive tables to cold storage** for compliance retention | Medium | Infra + Compliance | This week |
| 3 | **Drop archive tables** from prod PVC once exports are verified | Low | Infra | After #2 |
| 4 | **Fix `pg-concurrent-migrator` replica race** in hapihub repo | Low | HapiHub team | Next hapihub release cycle |

---

## 1. Phase B — canonical URL swap

### Goal

- `hapihub.localfirsthealth.com` → v11 (taken over from v10)
- `hapihub-legacy.localfirsthealth.com` → v10 (new hostname)
- `api.mycure.md` → v11 (taken over from v10)
- `mycure.localfirsthealth.com` → continues calling canonical (so points at v11 implicitly)
- `mycurev8.localfirsthealth.com` → updated to call `hapihub-legacy.localfirsthealth.com`

### When to do it

Wait for the following signals before scheduling:

- **v11 error rate vs v10**: pull `duration` + error rates from hapihub-next pod logs over several days. v11 should be comparable to or better than v10 on representative endpoints.
- **No user reports of data gaps**: mycure users hitting v11 should see the same data mycurev8 users see via v10 (validates the Mongo→Postgres sync is keeping up in practice).
- **Database headroom**: both backends are hitting the same Postgres. Confirm Postgres CPU / IOPS still have room. If not, consider resource adjustments before loading canonical traffic onto v11.
- **Compliance sign-off** if anyone flagged the audit-trail question.

Don't rush. There's no user cost to leaving v11 on the temp URL indefinitely.

### The diff (one commit)

A single commit on `values/deployments/mycure-production.yaml` with four edits:

```diff
# hapihub (v10) — gives up canonical, takes legacy hostname
 hapihub:
   gateway:
     hostnames:
-      - hapihub.localfirsthealth.com
-      - api.mycure.md
+      - hapihub-legacy.localfirsthealth.com
     sectionName: https-lfh
-    additionalSectionNames:
-      - https-mycure

# hapihubNext (v11) — takes canonical
 hapihubNext:
   gateway:
     hostnames:
-      - hapihub-next.localfirsthealth.com
+      - hapihub.localfirsthealth.com
+      - api.mycure.md
     sectionName: https-lfh
+    additionalSectionNames:
+      - https-mycure

# mycure (new frontend) — point back at canonical
 mycure:
   config:
-    API_URL: "https://hapihub-next.localfirsthealth.com"
-    HAPIHUB_URL: "https://hapihub-next.localfirsthealth.com"
+    API_URL: "https://hapihub.localfirsthealth.com"
+    HAPIHUB_URL: "https://hapihub.localfirsthealth.com"

# mycurev8 (legacy frontend) — point at legacy hostname
 mycurev8:
   config:
-    API_URL: "https://hapihub.localfirsthealth.com"
+    API_URL: "https://hapihub-legacy.localfirsthealth.com"
```

### Execution steps

1. Verify `hapihub-legacy.localfirsthealth.com` is covered by the wildcard TLS cert for `*.localfirsthealth.com` (it almost certainly is — all other sibling subdomains work). If cert is per-host, allow ~60 s after merge for cert-manager to issue it.
2. Commit + push. ArgoCD syncs in ~2 min.
3. Kubernetes rolls: `hapihub` Deployment's HTTPRoute gets updated hostnames; `hapihub-next` HTTPRoute gets canonical hostnames; `mycure` pods roll with new env vars; `mycurev8` pods roll with new env var.
4. External-dns creates the `hapihub-legacy.*` DNS record.

### What happens during the swap

For a few seconds during the NGINX Gateway reload, there may be a **brief window (5–10 s)** where `hapihub.localfirsthealth.com` could 502 as the route flips from v10's Service to v11's Service. Plan for low-traffic hours if you want to minimize noise. Users would typically retry on refresh.

mycurev8 users experience the same brief window when their `API_URL` env var updates. Ideally handle by picking off-hours.

### Verification after swap

```bash
# v11 on canonical
curl -s https://hapihub.localfirsthealth.com/health
# → expect v11-shaped response

# v10 on legacy
curl -s https://hapihub-legacy.localfirsthealth.com/health
# → expect v10-shaped response

# mycure still loads on its own URL
open https://mycure.localfirsthealth.com

# mycurev8 still loads (its API_URL is now hapihub-legacy)
open https://mycurev8.localfirsthealth.com
```

Watch `hapihub` + `hapihub-next` pod logs for 10–15 minutes post-swap. Expected: v11 CPU picks up (it's now serving canonical traffic), v10 CPU drops (it's now only serving mycurev8).

### Rollback

Revert the commit; push. ArgoCD reverses all four edits in one sync. Canonical returns to v10. No data migration required — all writes made during Phase B went to Postgres (v11) or Mongo (v10); the migration script keeps both in sync.

---

## 2. Export archive tables to cold storage

### Goal

Preserve the pre-dedupe audit-trail data in long-term encrypted cold storage (e.g., an encrypted GCS bucket) with appropriate retention (healthcare-typical: 7 years or per your compliance policy). This is the "safety net" for the ≈1.16 M audit-log rows that were removed from live tables.

### Archive tables currently in prod DB

| Table | Rows | Approx. on-disk size |
|---|---|---|
| `personal_details_history_archive_20260422` | 271,032 | ~200 MB |
| `diagnostic_order_tests_history_archive_20260422` | 11,103 | ~5 MB |
| `inventory_stocks_history_archive_20260422` | 1,033,427 | ~1 GB |
| `medical_records_history_archive_20260422` | 752,473 | ~500 MB |
| **Total** | 2,068,035 | ~1.7 GB raw |

### Commands

Pg_dump each archive table to a compressed file and upload to GCS. Do one at a time to limit disk pressure during the dump.

```bash
# Setup — pull the postgres password once
PGPW=$(kubectl -n mycure-production get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

TIMESTAMP=20260422
GCS_BUCKET=gs://mycure-compliance-archives/hapihub-history-${TIMESTAMP}

# For each table, stream pg_dump through gzip to a local file
for TABLE in \
  personal_details_history_archive_${TIMESTAMP} \
  diagnostic_order_tests_history_archive_${TIMESTAMP} \
  inventory_stocks_history_archive_${TIMESTAMP} \
  medical_records_history_archive_${TIMESTAMP}; do
  echo "Dumping $TABLE..."
  kubectl -n mycure-production exec -i postgresql-primary-0 -- \
    env PGPASSWORD="$PGPW" pg_dump -U postgres -d hapihub \
      -t public."$TABLE" \
      --format=custom --compress=9 --no-owner --no-privileges \
    > "/tmp/${TABLE}.dump"

  echo "Size: $(du -h /tmp/${TABLE}.dump | cut -f1)"

  echo "Uploading to GCS..."
  gcloud storage cp "/tmp/${TABLE}.dump" "${GCS_BUCKET}/${TABLE}.dump"

  # Optional: verify the GCS copy
  gcloud storage objects describe "${GCS_BUCKET}/${TABLE}.dump" | grep size
done
```

Expected compressed sizes (custom format + zstd/gzip level 9):
- `personal_details_history`: ~40–80 MB
- `diagnostic_order_tests_history`: ~1–3 MB
- `inventory_stocks_history`: ~150–300 MB
- `medical_records_history`: ~80–150 MB

### Verification

1. **File round-trip test** on any one archive (ideally the smallest — `diagnostic_order_tests_history`): download from GCS, `pg_restore` into a throwaway local Postgres, `SELECT count(*)` from the restored table, confirm it matches the original row count.
2. **Set GCS object retention / lifecycle** per compliance policy (e.g., lock for 7 years, deny-delete ACL).
3. **Document the archive location** in whatever compliance / data-governance registry your org uses.

### Practical caveats

- The archive tables can be exported while prod is serving traffic. `pg_dump` takes only an `ACCESS SHARE` lock on the source. No user impact.
- Time expectation: whole operation (all 4 tables) should complete in 15–30 minutes, depending on network to the cluster.
- If `pg_dump` of the largest table (`inventory_stocks_history_archive`) is slow, add `--jobs=4` — but that requires directory format (`-Fd`) rather than `-Fc`, which means using `kubectl cp` instead of stdout streaming.

---

## 3. Drop archive tables after export verified

### When

Only after item #2 completes AND the GCS dumps have been test-restored into a throwaway DB AND compliance has accepted the cold-storage copy as the source of record.

### Commands

```bash
PGPW=$(kubectl -n mycure-production get secret postgresql \
  -o jsonpath='{.data.postgres-password}' | base64 -d)

kubectl -n mycure-production exec postgresql-primary-0 -- \
  env PGPASSWORD="$PGPW" psql -U postgres -d hapihub \
  -c "DROP TABLE IF EXISTS personal_details_history_archive_20260422;" \
  -c "DROP TABLE IF EXISTS diagnostic_order_tests_history_archive_20260422;" \
  -c "DROP TABLE IF EXISTS inventory_stocks_history_archive_20260422;" \
  -c "DROP TABLE IF EXISTS medical_records_history_archive_20260422;"
```

Reclaims ~1.7 GB of prod PVC disk. Non-blocking — these tables have no triggers, no foreign keys, nothing referring to them.

---

## 4. `pg-concurrent-migrator` replica-race fix

### Problem observed during Phase A

When 3 `hapihub-next` replicas started simultaneously, each pod invoked `pg-concurrent-migrator.ts` and each tried `CREATE INDEX CONCURRENTLY IF NOT EXISTS <name>` for the same indexes in parallel. Postgres allows only one `CREATE INDEX CONCURRENTLY` per index at a time — the losing replica errored, pods restarted, the migrator retried with `DROP INDEX CONCURRENTLY` (to clean up the invalid index left behind) → eventually converges, but cosmetically noisy.

Visible symptom: 1-3 restarts on each `hapihub-next` pod during initial rollout.

### Fix

Wrap the migrator's index-building loop in a Postgres advisory lock:

```ts
// pseudo-code — real code lives in hapihub repo
const LOCK_KEY = 0x484150494855420n;  // "HAPIHUB" as bigint
await db.execute(sql`SELECT pg_advisory_lock(${LOCK_KEY})`);
try {
  for (const idx of indexes) {
    await db.execute(sql.raw(`CREATE INDEX CONCURRENTLY IF NOT EXISTS ...`));
  }
} finally {
  await db.execute(sql`SELECT pg_advisory_unlock(${LOCK_KEY})`);
}
```

`pg_advisory_lock` is cross-session — only one pod at a time holds it. Other pods block until it's released, then find the indexes already built and skip via `IF NOT EXISTS`. No wasted work, no pod restarts.

### Where

This fix is in the **hapihub repo** (`services/hapihub/src/utils/drizzle/pg-concurrent-migrator.ts`), not mono-infra. Should be a small PR — maybe 20 lines. Ship in the next hapihub patch (e.g., `11.2.21`).

### Priority

Low — purely cosmetic. All indexes still end up valid. Pods still end up Running + Ready. But worth fixing so the next deploy of this kind doesn't look like something went wrong.

---

## Out of scope (not followups, just notes)

- **Pre-cutover amendment UI data visibility**: as documented in the Phase A RCA, the amendment-trail UIs (RIS/LIS test history, PME report history) won't show pre-cutover entries because of the `id`/`_record` semantic flip. If product wants pre-cutover amendments visible, that's a separate project to write a data-reshape script (translate legacy rows to new convention) — likely not worth the effort. For compliance, the archive tables retain everything and can be queried via SQL.
- **Retiring v10 and mycurev8**: eventually, once no one is using mycurev8 and v10 has no traffic, the `hapihub:` block in `mycure-production.yaml` can be removed and the `mongodb` StatefulSet scaled to zero. That's a multi-month horizon and out of scope for this cutover.
- **Preprod reflecting prod's new shape**: if you want preprod to continue being a useful rehearsal for future prod changes, eventually add a `hapihubLegacy:` block to preprod so its structure mirrors what prod looks like mid-cutover. Not urgent — preprod works fine for its current role.
