{{/*
maestroapp.promoteScript — the fleet-pin reconcile script (mono#4095).

Rendered verbatim into BOTH the event-driven promote Job and the optional
periodic reconcile CronJob so the two can never drift. It is POSIX-sh (the
image's /bin/sh is dash) and depends only on tools proven present in the
bitnami minio image: `mc`, `jq` (/usr/bin/jq 1.6), `sha256sum`, and `mktemp`.

GUARANTEE (read this before "atomic"): there is NO cross-object atomic commit
here. Each platform-root latest.json is an independent S3 object; moving three
pointers is three independent copies and no store primitive makes them flip as
one. So this script does NOT promise instantaneous atomicity. What it DOES
guarantee is an eventually-consistent RECONCILE:

  * validate-all-before-any-write — no root pointer is touched until EVERY
    platform's v<PIN>/latest.json is present and structurally valid, so a
    typo'd/partly-published pin promotes NOTHING (never a half-fleet bump);
  * idempotent re-assert — every run compares each root to the pinned manifest
    by content hash and re-copies on ANY difference (missing, wrong version, OR
    same-version-but-wrong-bytes), so drift self-corrects;
  * self-healing partial failure — if a copy fails mid-phase the script keeps
    reconciling the remaining platforms, then exits non-zero, so the next run
    (selfHeal Force+Replace re-create, or the periodic CronJob) completes the
    stragglers. It never wedges: a partial failure is always recoverable by
    simply running again.
*/}}
{{/*
maestroapp.promotePodSpec — the pod `spec:` body shared by the event-driven
promote Job and the optional reconcile CronJob, so the two can never drift on
the security context, image, env, or resources. Rendered under a `spec:` key at
the caller's indentation.
*/}}
{{- define "maestroapp.promotePodSpec" -}}
restartPolicy: Never
# Talks only to the in-cluster store with creds from a mounted secret env — it
# never calls the k8s API, so drop its SA token.
automountServiceAccountToken: false
# Restricted-PSS compliant (preprod/prod namespaces enforce it). The bitnami
# minio image runs as 1001; MC_CONFIG_DIR=/tmp keeps mc happy without a writable
# HOME (readOnlyRootFilesystem + emptyDir /tmp below).
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  seccompProfile:
    type: RuntimeDefault
{{- if .Values.global.nodePool }}
# Land on the environment's app pool, not the default nonprod nodes (prod pools
# are tainted node-pool=<name>:NoSchedule).
nodeSelector:
  node-pool: {{ .Values.global.nodePool }}
tolerations:
  - key: "node-pool"
    operator: "Equal"
    value: {{ .Values.global.nodePool | quote }}
    effect: "NoSchedule"
{{- end }}
volumes:
  - name: tmp
    emptyDir: {}
containers:
  - name: promote
    # Registry-qualified: a bare `bitnamilegacy/minio` fails the
    # restrict-registries admission allowlist (docker.io/ required).
    image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
    securityContext:
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]
    volumeMounts:
      - name: tmp
        mountPath: /tmp
    command: [sh, -ec]
    args:
      - |
        {{- include "maestroapp.promoteScript" . | nindent 8 }}
    env:
      - name: PIN
        value: {{ .Values.version | quote }}
      - name: PLATFORMS
        value: {{ join " " .Values.platforms | quote }}
      - name: STORE_ENDPOINT
        value: {{ .Values.store.endpoint | quote }}
      - name: BUCKET
        value: {{ .Values.store.bucket | quote }}
      - name: STORE_USER
        value: {{ .Values.store.username | quote }}
      - name: STORE_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ .Values.store.existingSecret }}
            key: {{ .Values.store.existingSecretPasswordKey }}
    resources:
      requests:
        cpu: 10m
        memory: 32Mi
      limits:
        cpu: 100m
        memory: 64Mi
{{- end -}}

{{- define "maestroapp.promoteScript" -}}
export MC_CONFIG_DIR=/tmp/.mc
# First-sync ordering race: the minio provisioning hook (post-install/upgrade)
# creates the artifacts-promoter user, but this Job is sync-wave 3 and the
# parent app can read minio-artifacts' STALE Healthy status and reach wave 3
# before the hook finishes. A bare `mc alias set` would then hard-fail, exhaust
# backoffLimit, and leave a Failed Job that selfHeal won't re-run (manifest
# unchanged). Retry auth for ~5min so the user has time to appear; a genuinely
# bad credential still fails loudly after the ceiling.
n=0
until mc alias set store "$STORE_ENDPOINT" "$STORE_USER" "$STORE_PASSWORD" >/dev/null 2>&1; do
  n=$((n+1))
  if [ "$n" -ge 30 ]; then
    echo "ERROR: store auth failed after $n attempts (promoter user not provisioned yet?)"; exit 1
  fi
  echo "waiting for store auth (attempt $n)…"; sleep 10
done

# Scratch dir for the validated v<PIN> manifests (we cat each once, reuse the
# local copy for both structural validation AND the Phase-B content compare, so
# the bytes we validate are exactly the bytes we publish).
work=$(mktemp -d /tmp/promote.XXXXXX)

# --- Phase A — validate EVERY platform's v<PIN>/latest.json ------------------
# STRUCTURAL validation (not a substring match): parse the manifest with `jq`
# and assert the real .version field == PIN. Malformed JSON that merely CONTAINS
# the "version":"<PIN>" substring fails `jq` and is REJECTED — it can never be
# published. No root pointer is written in this phase; on exhaustion we exit
# non-zero having written NOTHING. ~5min bounded (30 * 10s).
vattempt=0
while :; do
  missing=""
  for dir in $PLATFORMS; do
    base="store/$BUCKET/maestroapp/desktop/$dir"
    src="$base/v$PIN/latest.json"
    if ! mc stat "$src" >/dev/null 2>&1; then
      echo "! $dir: v$PIN/latest.json not published"; missing="$missing $dir"; continue
    fi
    # Pull the manifest to disk, then parse it. `jq -e` exits non-zero on
    # malformed JSON OR a null/absent .version, so both "not JSON" and
    # "no version field" are caught here.
    if ! mc cat "$src" >"$work/$dir.json" 2>/dev/null; then
      echo "! $dir: v$PIN/latest.json unreadable"; missing="$missing $dir"; continue
    fi
    if ! mver=$(jq -e -r '.version' "$work/$dir.json" 2>/dev/null); then
      echo "! $dir: v$PIN/latest.json is not valid JSON / has no .version"; missing="$missing $dir"; continue
    fi
    if [ "$mver" != "$PIN" ]; then
      echo "! $dir: v$PIN/latest.json version='$mver', want $PIN"; missing="$missing $dir"; continue
    fi
    echo "validated $dir v$PIN"
  done
  [ -z "$missing" ] && break
  vattempt=$((vattempt+1))
  if [ "$vattempt" -ge 30 ]; then
    echo "ERROR: v$PIN not fully valid after $vattempt attempts — missing/invalid:$missing (typo'd pin, partial release, or corrupt manifest); NO root pointer written"; exit 1
  fi
  echo "waiting for v$PIN artifacts (attempt $vattempt) — missing:$missing"; sleep 10
done

# --- Phase B — reconcile each platform-root to the validated manifest --------
# Every platform validated, so it is safe to write root pointers. Compare the
# CURRENT root latest.json against the pinned v<PIN> manifest by CONTENT HASH,
# not just its version string — a root that already reports the right version
# but serves the wrong bytes (same-version content drift) still differs by hash
# and gets re-copied. Idempotent: a byte-identical root is a cheap no-op.
#
# NOT ATOMIC across platforms (see _helpers header): we copy each independently.
# On a copy failure we record it, keep reconciling the rest, and exit non-zero
# at the end so the next run finishes any stragglers — never wedged.
failed=""
for dir in $PLATFORMS; do
  base="store/$BUCKET/maestroapp/desktop/$dir"
  want="$work/$dir.json"                 # the validated v<PIN> bytes from Phase A
  want_h=$(sha256sum "$want" | cut -d' ' -f1)
  # Current root bytes (absent root => empty hash => guaranteed mismatch).
  cur_h=""
  if mc cat "$base/latest.json" >"$work/$dir.root.json" 2>/dev/null; then
    cur_h=$(sha256sum "$work/$dir.root.json" | cut -d' ' -f1)
  fi
  if [ "$cur_h" = "$want_h" ]; then
    echo "= $dir root already byte-identical to v$PIN"; continue
  fi
  echo "~ $dir root differs (hash $cur_h != $want_h) — reconciling to v$PIN"
  if ! mc cp "$base/v$PIN/latest.json" "$base/latest.json"; then
    echo "ERROR: $dir copy failed — will be retried next run"; failed="$failed $dir"; continue
  fi
  # Verify the store now serves the exact pinned bytes.
  if ! mc cat "$base/latest.json" >"$work/$dir.verify.json" 2>/dev/null; then
    echo "ERROR: $dir root unreadable after copy — will be retried next run"; failed="$failed $dir"; continue
  fi
  new_h=$(sha256sum "$work/$dir.verify.json" | cut -d' ' -f1)
  if [ "$new_h" != "$want_h" ]; then
    echo "ERROR: $dir copied but store serves wrong bytes (hash $new_h != $want_h) — will be retried next run"; failed="$failed $dir"; continue
  fi
  echo "OK: $dir reconciled to v$PIN"
done
if [ -n "$failed" ]; then
  echo "ERROR: reconcile incomplete — failed:$failed. Others are done; re-run completes the rest."; exit 1
fi
echo "fleet pin v$PIN reconciled (all roots byte-identical to v$PIN)"
{{- end -}}
