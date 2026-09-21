#!/usr/bin/env bash
# Self-check for the dpop_jti_seen prune + provisioning SQL (PR #451,
# monobase-mycure#4393). Runs the ACTUAL rendered SQL — extracted from the two
# chart ConfigMaps with `helm template` — and the ACTUAL client-side batch loop
# from the CronJob template, against a throwaway postgres container, so a logic
# regression in the templates fails this test.
#
# Covers the review's required cases:
#   1. absent table             -> clean no-op (exit 0), role still provisioned
#   2. provisioning idempotency -> re-run creates index (CONCURRENTLY) + grants
#   3. live vs expired vs NULL  -> only expired deleted; live AND null-expiry survive
#   4. batch limit              -> client loop deletes in batchSize chunks until 0
#   5. database error           -> surfaced (nonzero), never swallowed
#   6. least-privilege role     -> dpop_pruner CANNOT INSERT/UPDATE/DDL, only SEL/DEL
#   7. committed-progress falsifier -> a batch that times out mid-run does NOT roll
#      back rows committed by earlier batches (durable per-batch progress)
#   8. no argv password         -> provisioner imports the role password via \getenv,
#      never on psql's command line
#
# RELIABILITY (PR #451 review blocker 4): the Bitnami PG image runs a TEMPORARY
# init postmaster during first-boot, then shuts it down and restarts. A readiness
# probe that catches the temp postmaster then races the shutdown. We gate on
# STABLE readiness: pg_isready AND a real `SELECT 1` succeeding for several
# CONSECUTIVE checks, so we only proceed after the real postmaster is up for good.
#
# SCHEMA (PR #451 review blocker 5): the table is created with a NULLABLE
# `timestamp` expires_at, matching source migration monobase-mycure#0106_oauth_dpop
# (NOT `timestamptz NOT NULL`). A NULL expires_at is never < now(), so null rows
# are never pruned — asserted explicitly below.
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

# Confirm the provisioner does NOT pass the role password on psql's argv (blocker 1).
PROV_JOB="$(helm template t "$CHART" -f "$VALS" --show-only templates/provision-dpop-pruner-job.yaml)"
say "0. provisioner passes NO role password on psql argv (\\getenv only)"
# Match the ARGV pattern specifically (`-v pruner_password=…`), not the word in a
# comment — the template comment legitimately mentions pruner_password.
if printf '%s' "$PROV_JOB" | grep -qE '\-v[[:space:]]+pruner_password'; then
  fail "provision Job argv still passes -v pruner_password (password visible to ps)"
else
  pass "no -v pruner_password on provisioner argv"
fi
if printf '%s' "$PROV_SQL" | grep -q '\\getenv pruner_password PRUNER_PASSWORD'; then
  pass "provision.sql imports role password via \\getenv"
else
  fail "provision.sql does not \\getenv the role password"
fi

# --- spin up throwaway postgres ---------------------------------------------
say "starting throwaway postgres ($IMG)"
docker run -d --name "$CTR" \
  -e POSTGRESQL_PASSWORD="$PGPW" -e POSTGRESQL_DATABASE="$DB" \
  "$IMG" >/dev/null

# STABLE readiness: the bitnami image runs a temp init postmaster, then RESTARTS.
# Require several CONSECUTIVE successes (pg_isready AND a real SELECT on $DB) so we
# survive that restart and only proceed once the real server is up for good. Any
# failure resets the streak.
#
# TWO-GATE readiness (the single "N consecutive SELECTs" gate is NOT enough — on a
# loaded host the temp init postmaster can answer queries for >10s before Bitnami
# shuts it down, so a short streak passes against the doomed postmaster and the very
# next query dies with "the database system is shutting down"). We therefore:
#   GATE 1 (log): wait until Bitnami logs it has FINISHED init and (re)started the
#     REAL foreground server — the "** Starting PostgreSQL **" banner that is emitted
#     ONLY after initdb + the temp-postmaster shutdown. Everything before it is the
#     throwaway init postmaster.
#   GATE 2 (query): AFTER that marker, require $need CONSECUTIVE SELECT 1 successes,
#     streak reset on any failure, to confirm the real server is accepting stably.
# Budget generous for slow first-boot init; override via DPOP_TEST_READY_TIMEOUT.
say "waiting for STABLE post-init readiness (survives bitnami temp-postmaster restart)"
deadline=$(( $(date +%s) + ${DPOP_TEST_READY_TIMEOUT:-1200} ))

# GATE 1: Bitnami emits "Starting PostgreSQL in background..." for the TEMP init
# postmaster, "Stopping PostgreSQL..." to tear it down, then "** Starting PostgreSQL **"
# for the real foreground server. Wait for that final banner to appear AFTER a
# Stopping line (i.e. the post-init start), so we never match the pre-init banner.
started=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  logs="$(docker logs "$CTR" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
  if printf '%s\n' "$logs" | grep -q 'Stopping PostgreSQL' \
     && printf '%s\n' "$logs" | grep -qE '\*\* Starting PostgreSQL \*\*'; then
    started=1; break
  fi
  # If the container died during init, fail fast with its logs.
  docker inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -q true || {
    echo "postgres container exited during init"; docker logs "$CTR" 2>&1 | tail -30; exit 1; }
  sleep 2
done
[ "$started" = 1 ] || { echo "bitnami never reached post-init 'Starting PostgreSQL' banner"; docker logs "$CTR" 2>&1 | tail -30; exit 1; }

# GATE 2: real server up — now require a stable consecutive-SELECT streak.
need=5; ok=0; stable=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  if docker exec "$CTR" pg_isready -U postgres -d "$DB" -q >/dev/null 2>&1 \
     && docker exec -e PGPASSWORD="$PGPW" "$CTR" psql -U postgres -d "$DB" -tAc 'SELECT 1' >/dev/null 2>&1; then
    ok=$((ok + 1))
    if [ "$ok" -ge "$need" ]; then stable=1; break; fi
  else
    ok=0
  fi
  sleep 2
done
[ "$stable" = 1 ] || { echo "pg / $DB never reached stable readiness"; docker logs "$CTR" 2>&1 | tail -20; exit 1; }
pass "postgres stably ready (post-init banner + $need consecutive checks)"

supq() { docker exec -i -e PGPASSWORD="$PGPW" "$CTR" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
prunerq() { docker exec -i -e PGPASSWORD=prunerpw "$CTR" psql -U dpop_pruner -d "$DB" -v ON_ERROR_STOP=1 "$@"; }

run_prov() { # provision.sql as superuser; role password via env (\getenv), NOT argv
  printf '%s' "$PROV_SQL" | docker exec -i \
    -e PGPASSWORD="$PGPW" -e PRUNER_PASSWORD=prunerpw "$CTR" \
    psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 \
      -v DBNAME="$DB" -v pruner_role=dpop_pruner -f -
}

# One batch of prune.sql as the pruner role (mirrors ONE loop iteration). Prints
# the `DELETED <n>` line the CronJob shell loop parses. Args: batch [lock] [stmt].
run_prune_once() {
  printf '%s' "$PRUNE_SQL" | docker exec -i -e PGPASSWORD=prunerpw "$CTR" \
    psql -U dpop_pruner -d "$DB" -v ON_ERROR_STOP=1 \
      -v batch="${1:-500}" -v lock_timeout="${2:-5s}" -v statement_timeout="${3:-60s}" -f -
}

# Faithful reproduction of the CronJob's CLIENT-SIDE batch loop: re-invoke
# prune.sql (one committed batch each) until a batch deletes 0 rows or MAX_ITER.
# This is what proves durable per-batch progress (blocker 2/7).
run_prune_loop() { # batch max_iter [lock] [stmt]
  local batch="${1:-500}" max="${2:-1000}" lock="${3:-5s}" stmt="${4:-60s}"
  local total=0 i=0 n out
  while [ "$i" -lt "$max" ]; do
    i=$((i + 1))
    out="$(run_prune_once "$batch" "$lock" "$stmt" 2>&1)" || { echo "$out"; return 1; }
    echo "$out"
    n="$(printf '%s\n' "$out" | sed -n 's/^DELETED \([0-9][0-9]*\)$/\1/p' | tail -1)"
    [ -n "$n" ] || { echo "no DELETED count in batch $i"; return 1; }
    total=$((total + n))
    [ "$n" -eq 0 ] && break
  done
  echo "LOOP_TOTAL $total in $i call(s)"
}

# --- 1. provision + prune with table ABSENT ---------------------------------
say "1. table absent -> provision creates role only, prune is a clean no-op"
if run_prov >/tmp/dpop_prov1.log 2>&1; then pass "provision.sql exit 0 with table absent"; else fail "provision.sql errored with table absent"; cat /tmp/dpop_prov1.log; fi
if supq -tAc "SELECT 1 FROM pg_roles WHERE rolname='dpop_pruner'" | grep -q 1; then pass "dpop_pruner role created"; else fail "dpop_pruner role missing"; fi
if run_prune_once 500 >/tmp/dpop_prune1.log 2>&1; then pass "prune.sql exit 0 with table absent"; else fail "prune.sql errored with table absent"; cat /tmp/dpop_prune1.log; fi
grep -q "absent" /tmp/dpop_prune1.log && pass "prune emitted absent-table NOTICE" || fail "no absent-table NOTICE"
grep -qE "^DELETED 0$" /tmp/dpop_prune1.log && pass "absent path prints 'DELETED 0' stop sentinel" || fail "absent path missing 'DELETED 0'"

# --- create the table (simulate migration monobase-mycure#0106_oauth_dpop) --
# REAL schema: expires_at is a NULLABLE timestamp (NOT timestamptz NOT NULL).
say "creating dpop_jti_seen (real schema: nullable 'timestamp', jti PK only)"
supq -c "CREATE TABLE public.dpop_jti_seen (jti text PRIMARY KEY, expires_at timestamp);" >/dev/null
pass "table created (nullable timestamp expires_at, no expires_at index — matches migration)"

# --- 2. provisioning idempotency: re-run now applies index + grants ---------
say "2. re-run provision -> index (CONCURRENTLY) + grants land (chicken-and-egg resolved)"
run_prov >/tmp/dpop_prov2.log 2>&1 && pass "provision.sql exit 0 (2nd run, table present)" || { fail "provision 2nd run errored"; cat /tmp/dpop_prov2.log; }
if supq -tAc "SELECT 1 FROM pg_indexes WHERE indexname='dpop_jti_seen_expires_at_idx'" | grep -q 1; then pass "(expires_at) index created"; else fail "expires_at index missing"; fi
if supq -tAc "SELECT i.indisvalid FROM pg_class c JOIN pg_index i ON i.indexrelid=c.oid WHERE c.relname='dpop_jti_seen_expires_at_idx'" | grep -q t; then pass "index is VALID (CONCURRENTLY build completed)"; else fail "index is INVALID"; fi
run_prov >/tmp/dpop_prov3.log 2>&1 && pass "provision.sql idempotent (3rd run exit 0)" || fail "provision not idempotent"

# --- 3. live vs expired vs NULL ---------------------------------------------
say "3. only EXPIRED rows deleted; live AND null-expiry rows survive"
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at) VALUES
  ('expired-1', now() - interval '10 min'),
  ('expired-2', now() - interval '1 sec'),
  ('live-1',    now() + interval '55 sec'),
  ('live-2',    now() + interval '30 min'),
  ('null-1',    NULL),
  ('null-2',    NULL);" >/dev/null
run_prune_loop 500 1000 >/tmp/dpop_prune3.log 2>&1 && pass "prune loop exit 0" || { fail "prune loop errored"; cat /tmp/dpop_prune3.log; }
remaining="$(supq -tAc "SELECT string_agg(jti, ',' ORDER BY jti) FROM public.dpop_jti_seen")"
[ "$remaining" = "live-1,live-2,null-1,null-2" ] && pass "live + null rows remain ($remaining)" || fail "unexpected rows remain: '$remaining'"
nulls="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen WHERE expires_at IS NULL")"
[ "$nulls" = "2" ] && pass "null-expiry rows NEVER pruned (never-expiring, count=$nulls)" || fail "null rows disturbed: $nulls"
supq -c "DELETE FROM public.dpop_jti_seen;" >/dev/null

# --- 4. batch limit: many expired rows, small batch, must loop --------------
say "4. client loop deletes in batchSize chunks until 0 remain"
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at)
  SELECT 'bulk-'||g, now() - interval '5 min' FROM generate_series(1,1200) g;" >/dev/null
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at) VALUES ('keep-null', NULL);" >/dev/null
run_prune_loop 500 1000 >/tmp/dpop_prune4.log 2>&1 && pass "prune loop exit 0 on 1200 rows" || { fail "batched prune errored"; cat /tmp/dpop_prune4.log; }
left_expired="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen WHERE expires_at < now()")"
[ "$left_expired" = "0" ] && pass "all expired rows cleared across batches" || fail "$left_expired expired rows left after batched prune"
# 1200 rows / 500 per batch => 3 delete calls (500,500,200) + 1 zero call = 4 calls.
calls="$(grep -c '^DELETED ' /tmp/dpop_prune4.log || true)"
[ "$calls" -ge 4 ] && pass "loop made $calls psql calls (>=4: proves per-batch client invocations)" || fail "expected >=4 psql calls, got $calls"
grep -qE "LOOP_TOTAL 1200 " /tmp/dpop_prune4.log && pass "loop reports 1200 deleted" || fail "expected 'LOOP_TOTAL 1200'"
survivor="$(supq -tAc "SELECT string_agg(jti,',') FROM public.dpop_jti_seen")"
[ "$survivor" = "keep-null" ] && pass "null row still intact after bulk prune ($survivor)" || fail "null row disturbed: '$survivor'"
supq -c "DELETE FROM public.dpop_jti_seen;" >/dev/null

# --- 5. database error is surfaced, not swallowed ---------------------------
say "5. a DB error surfaces (nonzero exit), never swallowed"
if printf '%s' "SELECT 1/0;" | docker exec -i -e PGPASSWORD="$PGPW" "$CTR" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -f - >/tmp/dpop_err.log 2>&1; then
  fail "division-by-zero unexpectedly exited 0 (errors would be swallowed)"
else
  pass "psql -v ON_ERROR_STOP=1 propagates DB error as nonzero exit"
fi
supq -c "REVOKE DELETE ON public.dpop_jti_seen FROM dpop_pruner;" >/dev/null
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at) VALUES ('x', now() - interval '1 min');" >/dev/null
if run_prune_once 500 >/tmp/dpop_prune5.log 2>&1; then
  fail "prune succeeded despite revoked DELETE (error swallowed)"
else
  pass "revoked DELETE surfaces as nonzero prune exit (error not swallowed)"
fi
# And the CronJob loop must ABORT (not spin) when a batch yields no DELETED count.
if run_prune_loop 500 1000 >/tmp/dpop_loop5.log 2>&1; then
  fail "loop succeeded despite revoked DELETE (should abort)"
else
  pass "client loop aborts nonzero when a batch errors (no infinite spin)"
fi
supq -c "GRANT DELETE ON public.dpop_jti_seen TO dpop_pruner;" >/dev/null
supq -c "DELETE FROM public.dpop_jti_seen;" >/dev/null

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

# --- 7. committed-progress FALSIFIER ----------------------------------------
# Prove per-batch commits are DURABLE: run two successful batches, then force the
# NEXT batch to time out (statement_timeout=1ms with a lock-held delay) and show
# the rows the earlier batches deleted STAY deleted — a timeout rolls back only
# the failing batch, never the committed ones. The old single-DO design rolled
# back EVERYTHING on a timeout; this asserts that regression can't return.
say "7. committed-progress falsifier: a timed-out batch does NOT roll back prior committed batches"
supq -c "INSERT INTO public.dpop_jti_seen (jti, expires_at)
  SELECT 'prog-'||g, now() - interval '5 min' FROM generate_series(1,1000) g;" >/dev/null
before="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen")"
# Two committed batches of 300 each (=600 deleted), each its own psql invocation.
run_prune_once 300 >/tmp/dpop_prog1.log 2>&1 && pass "committed batch 1 (300)" || fail "batch 1 errored"
run_prune_once 300 >/tmp/dpop_prog2.log 2>&1 && pass "committed batch 2 (300)" || fail "batch 2 errored"
mid="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen")"
[ "$((before - mid))" = "600" ] && pass "600 rows committed-deleted across 2 batch calls" || fail "expected 600 deleted, got $((before - mid))"
# Now force a batch to time out: hold an exclusive lock in a background session,
# then run a batch with a tiny statement_timeout so it fails while waiting.
LOCKER_SQL='BEGIN; LOCK TABLE public.dpop_jti_seen IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(8); COMMIT;'
printf '%s' "$LOCKER_SQL" | docker exec -i -e PGPASSWORD="$PGPW" "$CTR" psql -U postgres -d "$DB" -f - >/tmp/dpop_locker.log 2>&1 &
LOCKER_PID=$!
sleep 1
if run_prune_once 300 1s 500ms >/tmp/dpop_timeout.log 2>&1; then
  fail "batch under a held lock should have timed out but exited 0"
else
  pass "batch times out (lock_timeout) while table is exclusively locked"
fi
wait "$LOCKER_PID" 2>/dev/null || true
after="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen")"
[ "$after" = "$mid" ] && pass "timed-out batch rolled back ONLY itself; prior 600 stay deleted (durable progress)" || fail "row count changed unexpectedly across timeout: mid=$mid after=$after"
# A subsequent normal run drains the rest — progress resumes, nothing stuck.
run_prune_loop 300 1000 >/tmp/dpop_prog_drain.log 2>&1 && pass "loop drains remainder after the timeout (resumes cleanly)" || fail "drain after timeout errored"
rest="$(supq -tAc "SELECT count(*) FROM public.dpop_jti_seen WHERE expires_at < now()")"
[ "$rest" = "0" ] && pass "all expired rows eventually cleared (0 remain)" || fail "$rest expired rows still remain"

# --- verdict -----------------------------------------------------------------
say "RESULT"
if [ "$FAILED" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "$FAILED"
