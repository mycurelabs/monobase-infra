# Off-Provider Secrets DR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ~115 irreplaceable secrets in GCP Secret Manager (`mc-v4-prod`) an automated, **off-provider**, break-glass-recoverable backup that survives a full loss of GCP access (compromise, billing lockout, project deletion) — issue [monobase-mycure#3882](https://github.com/mycurelabs/monobase-mycure/issues/3882).

**Architecture:** Two halves that meet only through the Spaces bucket. (1) An **in-cluster** daily CronJob (mirrors the existing wal-g backup pattern) reads every Secret Manager secret with a **read-only** GCP SA, encrypts the whole set with **SOPS + age to an OFFLINE recipient key**, and writes only the ciphertext to off-provider storage we already run (DO Spaces — versioning only, **Spaces has no Object Lock**). (2) A **host-side script on niflheim** (`scripts/secrets-dr-mirror-setup.sh`, Task 6) then quarantine-mirrors that bucket with an `rclone sync --backup-dir=…/secrets-deleted/<date>` (modeled on `mycure-wal-reconcile` — **not** the general Kopia mirror, which has no `--backup-dir`, and **not** a change to the shared `onprem-backup-setup.sh`) so a deletion by a compromised Spaces key cannot erase the on-prem copy. The CronJob runs in the `mycure-production` namespace; the quarantine runs on the off-cluster bare-metal niflheim host a Helm chart can't reach — same host/cluster split as PRs #400/#402 (host work ships as a `scripts/` script + runbook, not chart templates). The age **private** key is never in GCP or the cluster — it is escrowed out-of-band (Shamir-split among officers). Decryption depends only on `ciphertext + offline age key`, zero GCP dependency. A provider-specific *warm-standby* alternative (HashiCorp Vault / Akeyless / Infisical via native GCP import) is documented but **not built now** — Option A is the priority.

**Tech Stack:** GCP Secret Manager, `gcloud`, SOPS + age, Kubernetes CronJob, External Secrets Operator (for the exporter SA + Spaces creds), DO Spaces (S3), on-prem niflheim mirror, ArgoCD.

**Spec:** This plan; requirements from issue #3882 + decisions recorded there (Option A priority; provider-specific alternatives researched, not ESO-glue; plan→PR→handover flow).

## Global Constraints

- **What's protected:** 115 secrets in `mc-v4-prod` Secret Manager — `ENC_MEDICAL_RECORDS`/`ENC_PERSONAL_DETAILS`/`ENC_BILLING_*`, JWT `PRIVATE_KEY`/`PUBLIC_KEY`, `CADENCE_ISSUER_KEY`, storage/OAuth/Stripe/Postmark SA creds, `AUTH_SECRET`, across all envs. **No real Cloud KMS exists** (KMS API disabled) — these app-encryption keys live *as secrets*, so this is 100% a secrets problem.
- **Off-provider is mandatory.** GCP-native multi-region replication + versioning + CMEK stay *within* GCP and do NOT survive account/project loss — verified insufficient for #3882.
- **Encryption uses a PUBLIC key; the PRIVATE key is offline.** The cluster/CronJob can encrypt but can **never** decrypt past backups — so a full cluster or GCP compromise cannot read the DR archive. This is the whole security model.
- **No new plaintext at rest.** Plaintext exists only in a memory-backed tmpfs inside the job pod, piped straight into SOPS; never written to a persistent disk, never logged.
- **No new read exposure.** ESO already reads all these secrets, so a read-only exporter SA adds no attack surface beyond what exists; the *only* new artifact is ciphertext useless without the offline key (LastPass lesson: strong offline key, encrypt everything).
- **Reuse existing off-provider stores** — DO Spaces (enable versioning — **API-only; Spaces has no Object Lock**) + a **new small dedicated quarantining sync built here** — the `mycure-secrets-dr` bucket is mirrored by nothing today, and the general niflheim mirror has no `--backup-dir`, so this must be built as **a script on niflheim (`scripts/secrets-dr-mirror-setup.sh`, Task 6)**, modeled on `mycure-wal-reconcile`, NOT by editing the shared `onprem-backup-setup.sh`, so deletions don't propagate (see [[onprem-backup-mirror-niflheim]]); no new cloud account required for Option A. Real WORM immutability, if wanted, comes from a 3rd store where Object Lock actually works (B2/Wasabi/R2/S3).
- **Chart conventions:** new chart `charts/secrets-dr-backup/`, auto-discovered by ArgoCD, deployed into `mycure-production`. Mirror `charts/database-secrets` walg pattern (SA + RBAC + default-deny NetworkPolicy + hardened securityContext + ESO-sourced creds).
- **No secrets in git.** age *public* key is committed (ConfigMap); everything else via ESO.

---

## Cost implications (verified)

Secrets are KB-scale, so unlike the GCS bucket (#3878) this is essentially free — the cost story is the *opposite* extreme, and it's the strongest argument for Option A over a warm standby.

**Option A (recommended) — effectively $0/mo:**
| Component | Cost | Why |
|---|---|---|
| Secret Manager **access ops** | **$0** | ~115 reads/day ≈ 3,450/mo, under the **10,000/mo free tier**; beyond it it's $0.03/10k (~$0.01/mo). |
| Secret Manager **version storage** | **$0 incremental** | We only *read* — no new versions created. (Existing 115 versions × $0.06 = ~$6.90/mo are already billed regardless of this backup.) |
| **DO Spaces** storage | **$0 incremental** | Ciphertext <1 MB/day × 90 versions ≪ 100 MB, well inside the existing $5/mo Spaces bundle (250 GB + 1 TB transfer) already paid for PG backups. |
| **niflheim** mirror | **$0 incremental** | Existing on-prem mirror ([[onprem-backup-mirror-niflheim]]). |
| **Compute** | **$0 incremental** | Seconds/day on existing nodes. |
| *Optional 3rd store (AWS S3 Object Lock)* | **~cents/mo** | <100 MB storage ~$0.002/mo; GCP egress of KB/day is under the 100 GB free tier; PUTs negligible. |

**Provider-specific warm-standby alternatives — real money (why they're deferred):**
- **HCP Vault Dedicated:** Development tier ~$0.03–0.62/hr (~$22–450/mo) is single-node with **no HA and no snapshot restore** → unusable for DR. DR-grade needs Standard/Plus (~$1.58–1.84/hr ≈ $1,150–1,350/mo) **per cluster**, and DR replication needs a **second cluster** → **~$2,300+/mo**, plus **$72.92/client/mo**. (Rates vary across sources post-IBM tier renames — confirm in the HCP portal.)
- **Self-managed Vault Enterprise:** DR replication is Enterprise-only = quote-based license (typically tens of k$/yr) + you run the infra + solve Vault's own unseal-key DR.
- **Infisical:** self-host is free on the MIT core (infra cost only, ~tens/mo on our cluster) but enterprise features need a license; Cloud Pro is **$18/identity/mo** and machine identities count (scales fast).
- **Akeyless:** SaaS only (no true self-host), sales-quote, "fairly costly."

**Takeaway:** Option A costs ~$0/mo and rides infra we already run; a warm standby costs hundreds-to-thousands/mo. Build the warm layer only if a live-standby RTO genuinely justifies the spend (Task 5 documents the path).

---

## File Structure

| File | Responsibility |
|---|---|
| `charts/secrets-dr-backup/Chart.yaml` | Chart metadata. |
| `charts/secrets-dr-backup/values.yaml` | `enabled`, schedule, Spaces bucket/endpoint, age recipient(s), exporter SA secret name, retention. |
| `charts/secrets-dr-backup/templates/serviceaccount.yaml` | k8s SA for the job (no k8s RBAC needed — it talks out, not to the API). |
| `charts/secrets-dr-backup/templates/networkpolicy.yaml` | Default-deny egress except DNS + 443 (Secret Manager API + Spaces). |
| `charts/secrets-dr-backup/templates/externalsecret.yaml` | ESO: read-only GCP exporter SA JSON + DO Spaces key/secret. |
| `charts/secrets-dr-backup/templates/configmap.yaml` | age recipient public key(s) + the export script. |
| `charts/secrets-dr-backup/templates/cronjob.yaml` | The daily export→encrypt→upload job. |
| `charts/secrets-dr-backup/templates/prometheusrule.yaml` | Failure + staleness alerts for the CronJob (Task 4.5). |
| `values/deployments/mycure-production.yaml` | Enable the chart + its ESO remoteKeys (exporter SA, Spaces creds). |
| `scripts/secrets-dr-mirror-setup.sh` | **Host-side** (niflheim) quarantining mirror of the Spaces bucket — systemd service + timer, `rclone sync --backup-dir`. NOT a chart template (Task 6). |
| `docs/operations/SECRETS_DR.md` | Runbook: verify, restore/break-glass, key escrow policy, quarterly drill. |

**Human prerequisites (not chart-managed):**
- **P1. Generate the age key pair OFFLINE** (`age-keygen`) on an air-gapped/trusted machine. Commit only the **public** recipient (`age1...`). The **private** key is escrowed per the policy in Task 5 — never touches GCP, the cluster, or git.
- **P2. Create a read-only exporter GCP SA** in `mc-v4-prod` with `roles/secretmanager.viewer` + `roles/secretmanager.secretAccessor` (list + access, NO write/delete). Store its JSON key in Secret Manager as `mycure-production-secrets-dr-exporter-sa` (ESO reads it). `# ponytail: reuse ESO's existing reader SA only if it's already read-only-scoped; else a dedicated one keeps blast radius to read.`
- **P3. Create the DO Spaces backup bucket** `mycure-secrets-dr` with **versioning** (API-only, `mc version enable` — **Spaces has no Object Lock, don't rely on it**). That's it: the quarantining mirror that consumes this bucket is **built by the plan** as a host-side script on niflheim (Task 6, `scripts/secrets-dr-mirror-setup.sh`) — it is NOT a human prerequisite and NOT chart-managed.
- **P4. Decide age-key escrow** (Task 5 policy) — biz/security call, see handover.

---

### Task 1: Chart scaffold + exporter SA/creds wiring

**Files:**
- Create: `charts/secrets-dr-backup/{Chart.yaml,values.yaml}`
- Create: `charts/secrets-dr-backup/templates/{serviceaccount.yaml,externalsecret.yaml,networkpolicy.yaml}`

**Interfaces:**
- Consumes: `global.namespace`; ESO `ClusterSecretStore` (existing GCP store); Spaces creds remoteKeys.
- Produces: k8s Secret `secrets-dr-backup` (keys: `gcp-sa.json`, `spaces-access-key`, `spaces-secret-key`) + SA `secrets-dr-backup` + egress NetworkPolicy.

- [ ] **Step 1: `Chart.yaml`**

```yaml
apiVersion: v2
name: secrets-dr-backup
description: Off-provider encrypted DR export of GCP Secret Manager secrets (monobase-mycure#3882)
version: 0.1.0
```

- [ ] **Step 2: `values.yaml`**

```yaml
enabled: false            # opt-in per overlay
schedule: "0 17 * * *"    # 01:00 PHT daily; secrets change rarely
sourceProjectId: "mc-v4-prod"
secretFilter: ""          # empty = all secrets; or a name prefix e.g. "mycure-production-"
ageRecipients: []         # list of age1... public keys (offline private keys)
spaces:
  bucket: "mycure-secrets-dr"
  endpoint: "https://sgp1.digitaloceanspaces.com"
retentionNote: "Spaces versioning (API-only; no Object Lock); real immutability = niflheim --backup-dir quarantine; ~90 daily versions"
image: ""                 # REQUIRED: a baked image with gcloud + sops + age + jq + the S3
                          # uploader (aws-cli OR rclone). `cloud-sdk:slim` ships gcloud+gsutil
                          # but NOT aws/sops/age/jq — see Task 2 image note. No default: fail
                          # loud rather than silently run a broken slim image.
global:
  namespace: mycure-production
```

- [ ] **Step 3: `serviceaccount.yaml`** — plain SA, no RBAC (job only makes egress calls):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secrets-dr-backup
  namespace: {{ .Values.global.namespace }}
```

- [ ] **Step 4: `externalsecret.yaml`** — pull the read-only exporter SA + Spaces creds:

```yaml
{{- if .Values.enabled }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: secrets-dr-backup
  namespace: {{ .Values.global.namespace }}
spec:
  refreshInterval: 1h
  secretStoreRef: { name: gcp-backend, kind: ClusterSecretStore }
  target: { name: secrets-dr-backup, creationPolicy: Owner }
  data:
    - secretKey: gcp-sa.json
      remoteRef: { key: mycure-production-secrets-dr-exporter-sa }
    - secretKey: spaces-access-key
      remoteRef: { key: mycure-production-spaces-access-key }
    - secretKey: spaces-secret-key
      remoteRef: { key: mycure-production-spaces-secret-key }
{{- end }}
```

- [ ] **Step 5: `networkpolicy.yaml`** — default-deny egress except DNS + 443 (mirror walg-backup):

```yaml
{{- if .Values.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: secrets-dr-backup
  namespace: {{ .Values.global.namespace }}
spec:
  podSelector: { matchLabels: { app.kubernetes.io/name: secrets-dr-backup } }
  policyTypes: ["Egress"]
  egress:
    - to: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } } }]
      ports: [{ port: 53, protocol: UDP }, { port: 53, protocol: TCP }]
    - to: [{ ipBlock: { cidr: 0.0.0.0/0 } }]
      ports: [{ port: 443, protocol: TCP }]   # Secret Manager API + Spaces (managed IPs)
{{- end }}
```

- [ ] **Step 6: Lint + commit**

Run: `helm lint charts/secrets-dr-backup` and `helm template charts/secrets-dr-backup --set enabled=true | head`
```bash
git add charts/secrets-dr-backup
git commit -m "feat(secrets-dr): chart scaffold + exporter SA/creds wiring (monobase-mycure#3882)"
```

---

### Task 2: The export → encrypt → upload CronJob

**Files:**
- Create: `charts/secrets-dr-backup/templates/{configmap.yaml,cronjob.yaml}`

**Interfaces:**
- Consumes: Secret `secrets-dr-backup`, ConfigMap `secrets-dr-backup-script`, `.Values.ageRecipients`, `.Values.spaces.*`.
- Produces: a daily object `secrets/<sourceProjectId>/YYYY-MM-DD.json.age` (timestamp injected at runtime, not build time) in the Spaces bucket.

- [ ] **Step 1: `configmap.yaml`** — age recipients + the script (SOPS keeps keys visible / values encrypted, so the archive is auditable without decrypting):

```yaml
{{- if .Values.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: secrets-dr-backup-script
  namespace: {{ .Values.global.namespace }}
data:
  recipients.txt: |
    {{- range .Values.ageRecipients }}
    {{ . }}
    {{- end }}
  export.sh: |
    #!/usr/bin/env bash
    set -euo pipefail
    export CLOUDSDK_CORE_DISABLE_PROMPTS=1
    gcloud auth activate-service-account --key-file=/creds/gcp-sa.json
    PROJECT="${SOURCE_PROJECT}"
    OUT=/dev/shm/secrets.json          # tmpfs (Memory) — never a real disk
    echo '{}' > "$OUT"
    # Assemble {name: latest_value} for every secret. Values held only in tmpfs.
    # name.basename() — `name` alone is the full resource path
    # (projects/<num>/secrets/<id>); the bare <id> is what `secrets create` needs
    # on restore, so a full path would bake the OLD project number into the new one.
    for NAME in $(gcloud secrets list --project="$PROJECT" --format='value(name.basename())' \
                    ${SECRET_FILTER:+--filter="name:${SECRET_FILTER}"}); do
      # base64 BEFORE the shell can touch the bytes: $(...) strips ALL trailing
      # newlines, so PEM keys (PRIVATE_KEY/PUBLIC_KEY/CADENCE_ISSUER_KEY, SA JSONs)
      # would lose their trailing \n at capture. Piping into base64 -w0 never lets
      # the substitution see a trailing newline, so raw bytes round-trip exactly.
      B64=$(gcloud secrets versions access latest --secret="$NAME" --project="$PROJECT" | base64 -w0)
      jq --arg n "$NAME" --arg v "$B64" '.[$n]=$v' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    done
    COUNT=$(jq 'length' "$OUT"); echo "exported $COUNT secrets"
    # Encrypt to the OFFLINE age recipient(s). Ciphertext is the only thing that
    # ever leaves this pod. sops --input-type json keeps keys visible for audit.
    RECIPIENTS=$(paste -sd, /script/recipients.txt)
    sops --encrypt --age "$RECIPIENTS" --input-type json --output-type json "$OUT" \
      > /dev/shm/secrets.enc.json
    shred -u "$OUT" 2>/dev/null || rm -f "$OUT"
    # Upload ciphertext to Spaces (versioned; Spaces has NO Object Lock — the
    # niflheim --backup-dir quarantine is what makes a delete non-destructive).
    # Date from runtime.
    STAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
    export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY"
    aws --endpoint-url "$SPACES_ENDPOINT" s3 cp /dev/shm/secrets.enc.json \
      "s3://${SPACES_BUCKET}/secrets/${PROJECT}/${STAMP}.json.age"
    echo "uploaded s3://${SPACES_BUCKET}/secrets/${PROJECT}/${STAMP}.json.age ($COUNT secrets)"
{{- end }}
```

- [ ] **Step 2: `cronjob.yaml`** — hardened, tmpfs-only, mirror walg securityContext:

```yaml
{{- if .Values.enabled }}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: secrets-dr-backup
  namespace: {{ .Values.global.namespace }}
  labels: { app.kubernetes.io/name: secrets-dr-backup }
spec:
  schedule: {{ .Values.schedule | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 1800
      template:
        metadata:
          labels: { app.kubernetes.io/name: secrets-dr-backup }
        spec:
          serviceAccountName: secrets-dr-backup
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 1001
            seccompProfile: { type: RuntimeDefault }
          containers:
            - name: export
              image: {{ .Values.image | quote }}
              imagePullPolicy: IfNotPresent
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities: { drop: ["ALL"] }
              command: ["/bin/bash", "/script/export.sh"]
              env:
                - { name: HOME, value: /tmp }
                - { name: SOURCE_PROJECT, value: {{ .Values.sourceProjectId | quote }} }
                - { name: SECRET_FILTER, value: {{ .Values.secretFilter | quote }} }
                - { name: SPACES_BUCKET, value: {{ .Values.spaces.bucket | quote }} }
                - { name: SPACES_ENDPOINT, value: {{ .Values.spaces.endpoint | quote }} }
                - name: SPACES_ACCESS_KEY
                  valueFrom: { secretKeyRef: { name: secrets-dr-backup, key: spaces-access-key } }
                - name: SPACES_SECRET_KEY
                  valueFrom: { secretKeyRef: { name: secrets-dr-backup, key: spaces-secret-key } }
              volumeMounts:
                - { name: creds, mountPath: /creds, readOnly: true }
                - { name: script, mountPath: /script, readOnly: true }
                - { name: tmp, mountPath: /tmp }
                - { name: shm, mountPath: /dev/shm }
              resources:
                requests: { cpu: 50m, memory: 128Mi }
                limits:   { cpu: 500m, memory: 512Mi }
          volumes:
            - { name: creds, secret: { secretName: secrets-dr-backup, items: [{ key: gcp-sa.json, path: gcp-sa.json }] } }
            - { name: script, configMap: { name: secrets-dr-backup-script, defaultMode: 0555 } }
            - { name: tmp, emptyDir: {} }
            - { name: shm, emptyDir: { medium: Memory } }   # plaintext lives ONLY here
{{- end }}
```

> **Image note:** `cloud-sdk:slim` has `gcloud`/`gsutil` but **NOT** `aws`, `sops`, `age`, or `jq` — and the upload target is DO Spaces (S3-compatible), which `gsutil`/`gcloud storage` can't write. So the uploader needs a real S3 client. Bake a small pinned image with `gcloud + aws + sops + age + jq` (preferred), or swap the `aws s3 cp` upload for `rclone copyto` against a Spaces remote (the same tool niflheim uses in Task 6). Either way, the default `image: ""` must be overridden with a baked image — don't ship `cloud-sdk:slim`. Resolve at implementation; `# ponytail: bake one pinned image, don't apt-install on every run`.

- [ ] **Step 3: Render + commit**

Run: `helm template charts/secrets-dr-backup --set enabled=true --set ageRecipients={age1xxx} | grep -A2 kind:`
```bash
git add charts/secrets-dr-backup/templates/{configmap.yaml,cronjob.yaml}
git commit -m "feat(secrets-dr): daily export→age-encrypt→Spaces CronJob"
```

---

### Task 3: Enable in the production overlay (gated) + plan review

**Files:**
- Modify: `values/deployments/mycure-production.yaml` (add the chart values + ESO remoteKeys for exporter SA + Spaces creds if not already synced).

- [ ] **Step 1:** Add under the appropriate app block:

```yaml
secretsDrBackup:
  enabled: true
  schedule: "0 17 * * *"
  ageRecipients:
    - "age1..."   # from prereq P1 (public; offline private key escrowed)
  spaces:
    bucket: "mycure-secrets-dr"
```

- [ ] **Step 2: Review checklist (STOP on any failure)**
  - [ ] Exporter SA is read-only (`viewer` + `secretAccessor`, no write/delete).
  - [ ] `ageRecipients` are the OFFLINE public keys; no private key anywhere in repo/cluster.
  - [ ] Plaintext path is `/dev/shm` (Memory emptyDir) only; `readOnlyRootFilesystem: true`.
  - [ ] Spaces bucket has versioning (API-only); the **dedicated quarantining sync is BUILT** for the `mycure-secrets-dr` prefix (standalone, `--backup-dir=…/secrets-deleted/<date>`) — no delete-propagation.
  - [ ] NetworkPolicy scopes egress to DNS + 443 only. **Framing:** with `ipBlock: 0.0.0.0/0` this is an egress-*scoping* / allowlist-intent control (port-restricting, documents where the pod is allowed to talk, trips on a policy that tries to widen it), **not** a confidentiality control — 0.0.0.0/0 egress hides nothing. Confidentiality comes solely from the age public-key encryption; the NetworkPolicy just bounds the blast radius of a compromised pod.

- [ ] **Step 3:** Do NOT auto-merge to prod until biz sign-off on the escrow policy (this is plan-first).

---

### Task 4: First run + backup verification

- [ ] **Step 1:** After ArgoCD syncs, trigger a manual run:
```bash
kubectl create job --from=cronjob/secrets-dr-backup secrets-dr-manual-1 -n mycure-production
kubectl logs -n mycure-production job/secrets-dr-manual-1
```
Expected: `exported 115 secrets` … `uploaded s3://mycure-secrets-dr/secrets/mc-v4-prod/<stamp>.json.age`.

- [ ] **Step 2:** Confirm the object exists and is ciphertext:
```bash
aws --endpoint-url https://sgp1.digitaloceanspaces.com s3 ls s3://mycure-secrets-dr/secrets/mc-v4-prod/
# download + confirm it does NOT decrypt without the offline key (should fail):
sops --decrypt <obj>   # expect: no matching age identity
```

- [ ] **Step 3:** Confirm it landed on the niflheim mirror (see [[onprem-backup-mirror-niflheim]]).

---

### Task 4.5: CronJob failure alerting

A silently-failing secrets backup is the worst kind — this job protects the *irreplaceable* keys, so it is strictly more critical than the wal-g/GCS tiers and must page on failure, not wait for a weekly manual `s3 ls`. Mirrors PR #398's Task 4.5 (Tier-1 alerting), adapted to a k8s CronJob.

**Files:**
- Modify: `charts/secrets-dr-backup/values.yaml` (add `alert.enabled` + webhook/receiver ref).
- Create: `charts/secrets-dr-backup/templates/prometheusrule.yaml` (alert on job failure).

- [ ] **Step 1:** Add the alerting knobs to `values.yaml`:

```yaml
alert:
  enabled: true
  # Fires when the most recent job failed OR no job has succeeded in >36h
  # (a missed schedule is as bad as a failed run for a daily DR job).
  staleAfter: 36h
```

- [ ] **Step 2:** Add a `PrometheusRule` (the cluster already runs kube-state-metrics + Alertmanager for the other backup tiers — reuse that receiver, no new plumbing):

```yaml
{{- if and .Values.enabled .Values.alert.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: secrets-dr-backup
  namespace: {{ .Values.global.namespace }}
  labels: { release: monitoring }
spec:
  groups:
    - name: secrets-dr-backup
      rules:
        - alert: SecretsDrBackupJobFailed
          expr: kube_job_status_failed{namespace="{{ .Values.global.namespace }}",job_name=~"secrets-dr-backup.*"} > 0
          for: 5m
          labels: { severity: critical }
          annotations:
            summary: "Off-provider secrets DR export FAILED"
            description: "The daily secrets-dr-backup CronJob failed — the irreplaceable Secret Manager keys are NOT being backed up off-provider. Check `kubectl logs -n {{ .Values.global.namespace }} job/<name>`. Issue monobase-mycure#3882."
        - alert: SecretsDrBackupStale
          expr: (time() - max(kube_job_status_completion_time{namespace="{{ .Values.global.namespace }}",job_name=~"secrets-dr-backup.*"})) > {{ .Values.alert.staleAfter | default "36h" | trimSuffix "h" | atoi | mul 3600 }}
          labels: { severity: critical }
          annotations:
            summary: "Off-provider secrets DR export is STALE"
            description: "No secrets-dr-backup job has succeeded within the freshness window — the off-provider archive is aging out. Issue monobase-mycure#3882."
{{- end }}
```

> **Fallback if the cluster has no Prometheus-Operator CRDs:** add an `OnFailure`-style notifier container to the CronJob that POSTs to the same Discord webhook the niflheim mirror uses (`mycure-backup-notify` shape), or an Alertmanager `alertmanager://` push. At minimum this task must produce an *automated* failure signal — never a documented manual check.

- [ ] **Step 3: Render + commit**

Run: `helm template charts/secrets-dr-backup --set enabled=true --set ageRecipients={age1xxx} | grep -A2 'kind: PrometheusRule'`
```bash
git add charts/secrets-dr-backup/{values.yaml,templates/prometheusrule.yaml}
git commit -m "feat(secrets-dr): CronJob failure + staleness alerting (monobase-mycure#3882)"
```

---

### Task 5: Runbook + escrow policy (the security model)

**Files:**
- Create: `docs/operations/SECRETS_DR.md`

- [ ] **Step 1: Write the runbook** with these sections:

```markdown
# Off-Provider Secrets DR — Runbook (GCP Secret Manager)

**What:** daily encrypted export of all mc-v4-prod Secret Manager secrets to
DO Spaces (versioning; no Object Lock) + niflheim mirror (--backup-dir quarantine), encrypted with age to OFFLINE keys.
Chart: charts/secrets-dr-backup. Issue: monobase-mycure#3882.

## age key escrow policy (THE security model)
- Private key is Shamir-split M-of-N (recommend 2-of-3) across officers:
  <name/role A>, <B>, <C>. No single person can break glass.
- Each share stored in a separate password manager / hardware token, offline.
- Public recipient(s) committed in values (ageRecipients). Rotate yearly and on
  any officer offboarding (re-encrypt future exports; old archives stay valid
  under the old key until aged out).

## Health check (weekly)
    aws --endpoint-url <ep> s3 ls s3://mycure-secrets-dr/secrets/mc-v4-prod/ | tail
Latest object within 24h. If stale: check CronJob / job logs.

## Break-glass restore (GCP lost or secrets wiped)
1. Reassemble the age private key from M-of-N shares on a trusted machine.
2. Pull the latest ciphertext (from Spaces OR niflheim).
3. Decrypt: `sops --decrypt <obj> > /dev/shm/secrets.json` (tmpfs only).
4. Re-create secrets in a new/recovered project. Only the "already exists"
   case falls through to `versions add`; any OTHER create failure (permission,
   quota, bad project) surfaces and aborts — a blanket `2>/dev/null ||` would
   silently mask a broken restore:
       jq -r 'to_entries[] | "\(.key)\t\(.value)"' /dev/shm/secrets.json | \
       while IFS=$'\t' read -r NAME B64; do
         err=$(printf '%s' "$B64" | base64 -d | \
           gcloud secrets create "$NAME" --project=<new> --data-file=- 2>&1) && continue
         if printf '%s' "$err" | grep -qiE 'already exists|ALREADY_EXISTS'; then
           printf '%s' "$B64" | base64 -d | \
             gcloud secrets versions add "$NAME" --project=<new> --data-file=-
         else
           printf 'restore FAILED for %s: %s\n' "$NAME" "$err" >&2
           exit 1
         fi
       done
5. Repoint ESO ClusterSecretStore at <new>; shred /dev/shm/secrets.json.

## What the restore gives you (and what it does NOT)
The export captures the **`latest` version value of each secret only**. A restore
therefore reconstructs the current secret set — enough to bring the platform back —
but it is a value snapshot, not a fidelity clone of the Secret Manager project:
- **No version history** — prior versions are dropped; the restored secret starts at v1.
- **No labels / annotations** — metadata used for filtering/organization is not preserved.
- **No replication policy** — restored secrets take the new project's default (usually
  automatic); re-apply any user-managed replication explicitly if required.
- **No IAM bindings / rotation config / expiry** — per-secret access grants and
  rotation schedules must be re-applied out of band.
This is acceptable for break-glass (the *values* are the irreplaceable part), but the
restorer must know they are rebuilding metadata, not inheriting it.

## Quarterly break-glass drill (proves it, per PG-drill precedent)
- Reassemble the key, decrypt the latest archive into a THROWAWAY project,
  verify secret count + spot-check ENC_MEDICAL_RECORDS decrypts a known record,
  tear down, record result on the DR tracking issue.

## Provider-specific WARM-STANDBY alternative (future, not built)
If a live standby RTO is ever required, the provider-native path (NOT ESO-glue):
- HashiCorp Vault native GCP import source (`source_gcp`) → Vault Enterprise DR
  replication, or HCP Vault Dedicated (runs on AWS/Azure = off-GCP, managed DR +
  auto-snapshots). Trade-off: secrets sit decrypted in a 2nd online store.
- Akeyless (zero-knowledge DFC, no DB to replicate) or self-hosted Infisical
  (open-source, native GCP integration) as SaaS alternatives.
These are warm layers on top of — not replacements for — the offline archive.
```

- [ ] **Step 2: Commit**
```bash
git add docs/operations/SECRETS_DR.md
git commit -m "docs(secrets-dr): runbook + age-key escrow policy + break-glass drill"
```

---

### Task 6: niflheim quarantining mirror (host-side script)

The in-cluster CronJob (Tasks 1–2) only *uploads* to `mycure-secrets-dr` — **nothing mirrors that bucket off-provider yet**. This task builds the second half: a **host-side script on niflheim**, not a chart template. `charts/secrets-dr-backup/` deploys into the in-cluster `mycure-production` namespace; niflheim is an off-cluster bare-metal host a Helm chart can't reach — same host/cluster split PRs #400/#402 navigate, so it ships as a `scripts/` script + runbook. The two halves meet **only** through the Spaces bucket. The mirror uses `rclone sync --backup-dir` so a delete on Spaces (compromised/mis-scoped write key) moves the object into a dated quarantine directory locally instead of deleting the on-prem copy; a prune sweeps quarantine dirs older than a retention window (the `WAL_QUARANTINE_DAYS` pattern, here `QUARANTINE_DAYS`). Modeled on `mycure-wal-reconcile`; **NOT** an edit to the shared `onprem-backup-setup.sh` (another owner's hotspot).

**Files:**
- Create: `scripts/secrets-dr-mirror-setup.sh`
- Modify: `docs/operations/SECRETS_DR.md` (add a "niflheim quarantine mirror" section pointing at the script + the quarantine dir).

**Interfaces:**
- Consumes (env): `SPACES_ACCESS_KEY`, `SPACES_SECRET_KEY` (read-only Spaces key preferred); flags for bucket/region/dir/retention.
- Produces: one systemd `secrets-dr-mirror.service` + `.timer` on niflheim that runs `rclone sync spaces:mycure-secrets-dr/ <dir>/ --backup-dir <dir>/secrets-deleted/<date>`, plus an age-based quarantine prune.

- [ ] **Step 1: `scripts/secrets-dr-mirror-setup.sh`** — a trimmed sibling of `onprem-backup-setup.sh` (same defaults/arg-parsing/systemd idiom, but a plain `rclone sync` — no kopia, no LUKS). The script *emits* the units; the `rclone` command inside them is what actually quarantines:

```bash
#!/usr/bin/env bash
# Sets up a QUARANTINING pull-mirror of the mycure-secrets-dr Spaces bucket on
# niflheim. Unlike the shared onprem-backup-setup.sh (Kopia/Velero, no
# --backup-dir), this uses `rclone sync --backup-dir` so a delete on Spaces
# (compromised write key) can NEVER erase the on-prem DR copy — the object is
# moved into a dated quarantine dir instead. A prune sweeps quarantine dirs
# older than QUARANTINE_DAYS (mirrors the wal-reconcile WAL_QUARANTINE_DAYS knob).
# Ciphertext only (<100 MB); the age private key is never here.
#
# Usage:
#   sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… scripts/secrets-dr-mirror-setup.sh [flags]
set -euo pipefail

# ---------- defaults ----------
BACKUP_DIR=/var/backups/mycure-secrets-dr
BUCKET=mycure-secrets-dr
REGION=sgp1
QUARANTINE_DAYS=90                         # prune secrets-deleted/<date> dirs older than this
SERVICE_USER=mycure-secrets-dr
TIMER_ON_CALENDAR="*-*-* 03:20:00 UTC"     # after the 01:00 PHT cluster export lands
RCLONE_VERSION=1.69.1
RCLONE_BIN=/usr/local/bin/rclone
RCLONE_CONFIG=/etc/rclone/secrets-dr.conf
SERVICE_NAME=secrets-dr-mirror
SYSTEMD_DIR=/etc/systemd/system
PRUNE_BIN=/usr/local/sbin/secrets-dr-prune

log() { printf '\033[1;34m[secrets-dr]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[secrets-dr]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir=*)        BACKUP_DIR="${1#*=}";        shift;;
    --bucket=*)            BUCKET="${1#*=}";            shift;;
    --region=*)            REGION="${1#*=}";            shift;;
    --quarantine-days=*)   QUARANTINE_DAYS="${1#*=}";   shift;;
    --service-user=*)      SERVICE_USER="${1#*=}";      shift;;
    --timer-on-calendar=*) TIMER_ON_CALENDAR="${1#*=}"; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) err "unknown flag: $1 (see --help)";;
  esac
done

[[ $EUID -eq 0 ]] || err "must run as root (use sudo)"
: "${SPACES_ACCESS_KEY:?SPACES_ACCESS_KEY env var is required}"
: "${SPACES_SECRET_KEY:?SPACES_SECRET_KEY env var is required}"
command -v apt-get >/dev/null || err "apt-based distros only"

# ---------- rclone (pinned static binary) ----------
apt-get update -qq
apt-get install -y -qq curl ca-certificates unzip >/dev/null
if ! "$RCLONE_BIN" version 2>/dev/null | grep -q "rclone v$RCLONE_VERSION"; then
  arch=$(uname -m); case "$arch" in x86_64) ra=amd64;; aarch64) ra=arm64;; *) err "unsupported arch $arch";; esac
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${ra}.zip" -o "$tmp/r.zip"
  unzip -q "$tmp/r.zip" -d "$tmp"
  install -m 0755 "$tmp"/rclone-v*-linux-*/rclone "$RCLONE_BIN"
fi

# ---------- service user + dirs ----------
id -u "$SERVICE_USER" >/dev/null 2>&1 || \
  useradd --system --no-create-home --shell /usr/sbin/nologin --user-group "$SERVICE_USER"
mkdir -p "$BACKUP_DIR/current" "$BACKUP_DIR/secrets-deleted"
chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR"
chmod -R 0750 "$BACKUP_DIR"

# ---------- rclone config (read-only Spaces key preferred) ----------
mkdir -p "$(dirname "$RCLONE_CONFIG")"
umask 077
cat > "$RCLONE_CONFIG" <<EOF
[spaces]
type = s3
provider = DigitalOcean
region = $REGION
endpoint = $REGION.digitaloceanspaces.com
access_key_id = $SPACES_ACCESS_KEY
secret_access_key = $SPACES_SECRET_KEY
acl = private
EOF
umask 022
chgrp "$SERVICE_USER" "$RCLONE_CONFIG"
chmod 0640 "$RCLONE_CONFIG"
unset SPACES_ACCESS_KEY SPACES_SECRET_KEY   # scrub env

# ---------- quarantine prune helper ----------
# Delete secrets-deleted/<date> dirs older than QUARANTINE_DAYS. Mirrors the
# wal-reconcile WAL_QUARANTINE_DAYS knob: a bounded window to recover a
# mistaken/hostile delete before the quarantine copy itself ages out.
install -m 0755 /dev/stdin "$PRUNE_BIN" <<PRUNE
#!/usr/bin/env bash
set -euo pipefail
QDIR="$BACKUP_DIR/secrets-deleted"
[[ -d "\$QDIR" ]] || exit 0
find "\$QDIR" -mindepth 1 -maxdepth 1 -type d -mtime +$QUARANTINE_DAYS -print -exec rm -rf {} +
PRUNE

# ---------- systemd service ----------
# rclone sync moves any object deleted upstream into a dated quarantine dir
# instead of deleting it locally; the prune then bounds that dir by age.
cat > "$SYSTEMD_DIR/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=Quarantining mirror of the mycure-secrets-dr Spaces bucket (off-provider DR)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
Environment=RCLONE_CONFIG=$RCLONE_CONFIG
ExecStart=$RCLONE_BIN sync spaces:$BUCKET/ $BACKUP_DIR/current/ \\
  --backup-dir $BACKUP_DIR/secrets-deleted/%i \\
  --suffix "" \\
  --transfers 2 \\
  --checkers 4 \\
  --log-level INFO \\
  --stats-one-line
ExecStartPost=$PRUNE_BIN
TimeoutStartSec=1h
Nice=10

[Install]
WantedBy=multi-user.target
UNIT

# %i (the instance date) is injected by wrapping the ExecStart date at call
# time — systemd OnCalendar timers don't expand %i, so we template it via a
# drop-in that sets the dated backup-dir. Simplest robust form: a wrapper.
install -m 0755 /dev/stdin /usr/local/sbin/secrets-dr-sync <<SYNC
#!/usr/bin/env bash
set -euo pipefail
export RCLONE_CONFIG=$RCLONE_CONFIG
DATE=\$(date -u +%Y-%m-%d)
exec $RCLONE_BIN sync spaces:$BUCKET/ $BACKUP_DIR/current/ \\
  --backup-dir "$BACKUP_DIR/secrets-deleted/\$DATE" \\
  --transfers 2 --checkers 4 --log-level INFO --stats-one-line
SYNC

# Point the unit at the wrapper (clean date handling) + keep the prune.
cat > "$SYSTEMD_DIR/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=Quarantining mirror of the mycure-secrets-dr Spaces bucket (off-provider DR)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=/usr/local/sbin/secrets-dr-sync
ExecStartPost=$PRUNE_BIN
TimeoutStartSec=1h
Nice=10

[Install]
WantedBy=multi-user.target
UNIT

# ---------- systemd timer ----------
cat > "$SYSTEMD_DIR/$SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Daily timer for the secrets-dr quarantining mirror

[Timer]
OnCalendar=$TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=10m
Unit=$SERVICE_NAME.service

[Install]
WantedBy=timers.target
UNIT

# ---------- validate creds + enable ----------
sudo -u "$SERVICE_USER" RCLONE_CONFIG="$RCLONE_CONFIG" \
  rclone lsd "spaces:$BUCKET/" >/dev/null 2>&1 || \
  err "rclone failed to list spaces:$BUCKET — check the read-only Spaces key + bucket name"
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME.timer" >/dev/null

log "setup complete:"
echo "  bucket        : spaces:$BUCKET ($REGION)"
echo "  mirror dir    : $BACKUP_DIR/current"
echo "  quarantine    : $BACKUP_DIR/secrets-deleted/<date> (pruned after ${QUARANTINE_DAYS}d)"
echo "  timer         : $TIMER_ON_CALENDAR"
echo "  trigger now   : sudo systemctl start $SERVICE_NAME.service"
```

> **Note on the two `.service` heredocs above:** the first (with an inline `%i` `--backup-dir`) is shown then immediately *replaced* by the wrapper-based unit — `%i` is only expanded for templated `@` units, so the production form is the wrapper (`secrets-dr-sync`) which computes `date -u +%Y-%m-%d` at run time. At implementation, keep only the wrapper form; the first block is retained here to explain *why* the wrapper exists. `# ponytail: one unit, one wrapper — don't template a @.service just for a date.`

- [ ] **Step 2: Runbook + commit**

Add a "niflheim quarantine mirror" section to `docs/operations/SECRETS_DR.md`: how to (re)run the setup (`sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… scripts/secrets-dr-mirror-setup.sh`), where the quarantine lives (`/var/backups/mycure-secrets-dr/secrets-deleted/<date>`), and how to recover an object a Spaces delete moved into quarantine.
```bash
git add scripts/secrets-dr-mirror-setup.sh docs/operations/SECRETS_DR.md
git commit -m "feat(secrets-dr): niflheim quarantining Spaces mirror (host-side, monobase-mycure#3882)"
```

---

## Self-Review

**Spec coverage:** off-provider requirement → in-cluster upload (Task 2) + niflheim quarantining mirror (Task 6), offline age key (Task 2/5). All 115 secrets → `gcloud secrets list` loop (Task 2). Failure/staleness alerting → Task 4.5. Quarantine (delete can't destroy the DR copy) → Task 6 `rclone sync --backup-dir` + age prune. Break-glass restore → Task 5 (restore surfaces only the `latest` value — no history/labels/replication, documented). Provider-specific alternative researched + documented (Vault import / HCP / Akeyless / Infisical) → Task 5, not built (Option A priority). Minimal surface → read-only SA + public-key encryption + tmpfs (Global Constraints). ✅

**Host/cluster split:** the CronJob (Tasks 1–2, in-cluster `mycure-production`) and the quarantine (Task 6, off-cluster niflheim) meet ONLY through the Spaces bucket. The quarantine is a `scripts/` host script, NOT a chart template — a chart can't reach niflheim (same split as PRs #400/#402). ✅

**Open items for biz/owner decision (issue #3882):**
1. **age private-key escrow** — who are the M-of-N custodians and the threshold (recommend 2-of-3)? This is the entire security model.
2. **Off-provider stores** — Spaces (versioning) + niflheim (`--backup-dir` quarantine) sufficient, or add a 3rd store where **Object Lock actually works** (Backblaze B2 / Wasabi / Cloudflare R2 / AWS S3) for true WORM? The Spaces write key lives in-cluster, so without an immutable copy a cluster compromise could delete the Spaces archive — the on-prem quarantine closes that half; a WORM 3rd store closes it fully. <100 MB ciphertext → cents/mo.
3. **Warm standby** — build the provider-specific Vault/Akeyless/Infisical layer now, or defer (plan defers it; Option A only).
4. **Cadence/retention** — daily export + 90 daily versions OK?

**Placeholder scan:** `<obj>`, `<new>`, `age1...`, `<name/role>`, `<date>` are runtime/escrow fill-ins, not logic gaps. Image is `image: ""` by design (fail loud) and needs `sops+age+jq+gcloud+aws` (or rclone) baked — noted in Task 2 + values.yaml. Task 6 ships two `.service` heredocs (inline-`%i` illustrative + wrapper production); keep only the wrapper. No TODO logic.

**Type consistency:** Secret name `secrets-dr-backup` and keys `gcp-sa.json`/`spaces-access-key`/`spaces-secret-key` consistent across externalsecret (Task 1) and cronjob (Task 2); ConfigMap `secrets-dr-backup-script` + `export.sh`/`recipients.txt` consistent between configmap and cronjob mounts. ✅
