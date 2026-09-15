#!/usr/bin/env bash
# Self-check for the dpop_jti_seen prune + provisioning SQL (PR #451,
# monobase-mycure#4393). Runs the ACTUAL rendered SQL — extracted from the two
# chart ConfigMaps with `helm template` — against a throwaway postgres container,
# so a logic regression in the templates fails this test.
#
# Covers the review's required cases:
#   1. absent table            -> clean no-op (exit 0), role still provisioned
#   2. provisioning idempotency -> re-run creates index + grants once table exists
#   3. live vs expired rows    -> only expired deleted, live proofs untouched
#   4. batch limit             -> loops in batchSize chunks until 0 remain
#   5. database error          -> surfaced (nonzero), never swallowed
#   6. least-privilege role    -> dpop_pruner CANNOT INSERT/UPDATE/DDL, only SEL/DEL
#
# Lazy by design: no framework. Needs `docker` + `helm`. Run from anywhere:
#   bash charts/hapihub/tests/prune-dpop-jti.test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$(cd "$HERE/.." && pwd)"
CTR="dpop-jti-test-pg-$$"
PGPW="testpw"
DB="hapihub"
IMG="docker.io/bitnamilegacy/postgresql:16.4.0-debian-12-r13"
FAILED=0
VALS="$(mktemp)"

cleanup() { docker rm -f "$CTR" >/dev/null 2>&1 || true; rm -f "$VALS"; }
trap cleanup EXIT

say()  { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  PASS: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*"; FAILED=1; }

# --- render the real SQL out of the chart -----------------------------------
cat > "$VALS" <<'EOF'
enabled: true
global: {namespace: t, domain: example.com, environment: staging}
pruneExpiredDpopJti: {enabled: true, batchSize: 500}
postgresql: {enabled: true, external: false, auth: {database: hapihub, username: postgres}}
valkey: {enabled: false}
minio: {enabled: false}
mailpit: {enabled: false}
cache: {enabled: false}
EOF

PRUNE_SQL="$(helm template t "$CHART" -f "$VALS" --show-only templates/prune-dpop-jti-configmap.yaml \
  | sed -n '/prune.sql: |/,$p' | sed '1d;s/^    //')"
PROV_SQL="$(helm template t "$CHART" -f "$VALS" --show-only templates/provision-dpop-pruner-configmap.yaml \
  | sed -n '/provision.sql: |/,$p' | sed '1d;s/^    //')"

[ -n "$PRUNE_SQL" ] || { echo "could not extract prune.sql"; exit 1; }
[ -n "$PROV_SQL" ] || { echo "could not extract provision.sql"; exit 1; }

# --- spin up throwaway postgres ---------------------------------------------
say "starting throwaway postgres ($IMG)"
docker run -d --name "$CTR" \
  -e POSTGRESQL_PASSWORD="$PGPW" -e POSTGRESQL_DATABASE="$DB" \
  "$IMG" >/dev/null
# pg_isready reports the postmaster up BEFORE bitnami finishes creating the
# custom POSTGRESQL_DATABASE, so actually connect to $DB and run a query.
ready=0
for i in $(seq 1 45); do
  if docker exec -e PGPASSWORD="$PGPW" "$CTR" psql -U postgres -d "$DB" -tAc 'SELECT 1' >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 1
done
[ "$ready" = 1 ] || { echo "pg / $DB never ready"; docker logs "$CTR" 2>&1 | tail -20; exit 1; }

supq() { docker exec -i -e PGPASSWORD="$PGPW" "$CTR" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
prunerq() { docker exec -i -e PGPASSWORD=prunerpw "$CTR" psql -U dpop_pruner -d "$DB" -v ON_ERROR_STOP=1 "$@"; }

run_prov() { # provision.sql as superuser
  printf '%s' "$PROV_SQL" | docker exec -i -e PGPASSWORD="$PGPW" "$CTR" \
    psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 \
      -v DBNAME="$DB" -v pruner_role=dpop_pruner -v pruner_password=prunerpw -f -
}
run_prune() { # prune.sql as pruner role
  printf '%s' "$PRUNE_SQL" | docker exec -i -e PGPASSWORD=prunerpw "$CTR" \
    psql -U dpop_pruner -d "$DB" -v ON_ERROR_STOP=1 \
      -v batch="${1:-500}" -v lock_timeout=5s -v statement_timeout=60s -f -
}

# --- 1. provision + prune with table ABSENT ---------------------------------
say "1. table absent -> provision creates role only, prune is a clean no-op"
if run_prov >/tmp/dpop_prov1.log 2>&1; then pass "provision.sql exit 0 with table absent"; else fail "provision.sql errored with table absent"; cat /tmp/dpop_prov1.log; fi
if supq -tAc "SELECT 1 FROM pg_roles WHERE rolname='dpop_pruner'" | grep -q 1; then pass "dpop_pruner role created"; else fail "dpop_pruner role missing"; fi
if run_prune 500 >/tmp/dpop_prune1.log 2>&1; then pass "prune.sql exit 0 with table absent"; else fail "prune.sql errored with table absent"; cat /tmp/dpop_prune1.log; fi
grep -q "absent" /tmp/dpop_prune1.log && pass "prune emitted absent-table NOTICE" || fail "no absent-table NOTICE"

# --- create the table (simulate migration monobase-mycure#0106_oauth_dpop) --
say "creating dpop_jti_seen (simulating migration monobase-mycure#0106_oauth_dpop)"
supq -c "CREATE TABLE public.dpop_jti_seen (jti text PRIMARY KEY, expires_at timestamptz NOT NULL);" >/dev/null
pass "table created (jti PK only, no expires_at index — matches source migration)"

# --- 2. provisioning idempotency: re-run now applies index + grants ---------
say "2. re-run provision -> index + grants land (chicken-and-egg resolved)"
run_prov >/tmp/dpop_prov2.log 2>&1 && pass "provision.sql exit 0 (2nd run, table present)" || { fail "provision 2nd run errored"; cat /tmp/dpop_prov2.log; }
if supq -tAc "SELECT 1 FROM pg_indexes WHERE indexname='dpop_jti_seen_expires_at_idx'" | grep -q 1; then pass "(expires_at) index created"; else fail "expires_at index missing"; fi
run_prov >/tmp/dpop_prov3.log 2>&1 && pass "provision.sql idempotent (3rd run exit 0)" || fail "provision not idempotent"

# --- 3. live vs expired -----------------------------------------------------
say "3. only EXPIRED rows deleted, live proofs untouched"
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at) VALUES
  ('expired-1', now() - interval '10 min'),
  ('expired-2', now() - interval '1 sec'),
  ('live-1',    now() + interval '55 sec'),
  ('live-2',    now() + interval '30 min');" >/dev/null
run_prune 500 >/tmp/dpop_prune3.log 2>&1 && pass "prune.sql exit 0" || { fail "prune errored"; cat /tmp/dpop_prune3.log; }
remaining="$(supq -tAc "SELECT string_agg(jti, ',' ORDER BY jti) FROM public.dpop_jti_seen")"
[ "$remaining" = "live-1,live-2" ] && pass "only live rows remain ($remaining)" || fail "unexpected rows remain: '$remaining'"

# --- 4. batch limit: many expired rows, small batch, must loop --------------
say "4. batched delete loops in batchSize chunks until 0 remain"
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at)
  SELECT 'bulk-'||g, now() - interval '5 min' FROM generate_series(1,1200) g;" >/dev/null
run_prune 500 >/tmp/dpop_prune4.log 2>&1 && pass "prune.sql exit 0 on 1200 rows" || { fail "batched prune errored"; cat /tmp/dpop_prune4.log; }
left_expired="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen WHERE expires_at < now()")"
[ "$left_expired" = "0" ] && pass "all expired rows cleared across batches" || fail "$left_expired expired rows left after batched prune"
grep -qE "deleted 1200 " /tmp/dpop_prune4.log && pass "NOTICE reports 1200 deleted" || fail "expected 'deleted 1200' NOTICE"
live_left="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen")"
[ "$live_left" = "2" ] && pass "live rows still intact after bulk prune ($live_left)" || fail "live rows disturbed: $live_left"

# --- 5. database error is surfaced, not swallowed ---------------------------
say "5. a DB error surfaces (nonzero exit), never swallowed"
if printf '%s' "SELECT 1/0;" | docker exec -i -e PGPASSWORD="$PGPW" "$CTR" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -f - >/tmp/dpop_err.log 2>&1; then
  fail "division-by-zero unexpectedly exited 0 (errors would be swallowed)"
else
  pass "psql -v ON_ERROR_STOP=1 propagates DB error as nonzero exit"
fi
supq -c "REVOKE DELETE ON public.dpop_jti_seen FROM dpop_pruner;" >/dev/null
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at) VALUES ('x', now() - interval '1 min');" >/dev/null
if run_prune 500 >/tmp/dpop_prune5.log 2>&1; then
  fail "prune succeeded despite revoked DELETE (error swallowed)"
else
  pass "revoked DELETE surfaces as nonzero prune exit (error not swallowed)"
fi
supq -c "GRANT DELETE ON public.dpop_jti_seen TO dpop_pruner;" >/dev/null

# --- 6. least-privilege: role cannot write/DDL ------------------------------
say "6. least-privilege — dpop_pruner limited to SELECT/DELETE"
if prunerq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at) VALUES ('nope', now());" >/tmp/dpop_perm.log 2>&1; then
  fail "dpop_pruner could INSERT (should be denied)"
else
  pass "dpop_pruner INSERT denied"
fi
if prunerq -c "DROP TABLE public.dpop_jti_seen;" >/tmp/dpop_ddl.log 2>&1; then
  fail "dpop_pruner could DROP TABLE (should be denied)"
else
  pass "dpop_pruner DDL denied"
fi
if prunerq -c "SELECT count(*) FROM public.dpop_jti_seen;" >/dev/null 2>&1; then
  pass "dpop_pruner SELECT allowed (needed for ctid subquery)"
else
  fail "dpop_pruner SELECT denied (breaks batched delete)"
fi
if prunerq -c "DELETE FROM public.dpop_jti_seen WHERE expires_at < now();" >/dev/null 2>&1; then
  pass "dpop_pruner DELETE allowed"
else
  fail "dpop_pruner DELETE denied"
fi

# --- verdict -----------------------------------------------------------------
say "RESULT"
if [ "$FAILED" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "$FAILED"
