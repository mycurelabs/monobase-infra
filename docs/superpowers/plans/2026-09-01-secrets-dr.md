# Off-Provider Secrets DR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ~115 irreplaceable secrets in GCP Secret Manager (`mc-v4-prod`) an automated, **off-provider**, break-glass-recoverable backup that survives a full loss of GCP access (compromise, billing lockout, project deletion) — issue [monobase-mycure#3882](https://github.com/mycurelabs/monobase-mycure/issues/3882).

**Architecture:** A daily in-cluster CronJob (mirrors the existing wal-g backup pattern) reads every Secret Manager secret with a **read-only** GCP SA, encrypts the whole set with **SOPS + age to an OFFLINE recipient key**, and writes only the ciphertext to off-provider storage we already run (DO Spaces — versioning only, **Spaces has no Object Lock** — auto-mirrored to on-prem niflheim, where the mirror uses a `--backup-dir` quarantine (#403-style) so a deletion by a compromised Spaces key cannot erase the on-prem copy). The age **private** key is never in GCP or the cluster — it is escrowed out-of-band (Shamir-split among officers). Decryption depends only on `ciphertext + offline age key`, zero GCP dependency. A provider-specific *warm-standby* alternative (HashiCorp Vault / Akeyless / Infisical via native GCP import) is documented but **not built now** — Option A is the priority.

**Tech Stack:** GCP Secret Manager, `gcloud`, SOPS + age, Kubernetes CronJob, External Secrets Operator (for the exporter SA + Spaces creds), DO Spaces (S3), on-prem niflheim mirror, ArgoCD.

**Spec:** This plan; requirements from issue #3882 + decisions recorded there (Option A priority; provider-specific alternatives researched, not ESO-glue; plan→PR→handover flow).

## Global Constraints

- **What's protected:** 115 secrets in `mc-v4-prod` Secret Manager — `ENC_MEDICAL_RECORDS`/`ENC_PERSONAL_DETAILS`/`ENC_BILLING_*`, JWT `PRIVATE_KEY`/`PUBLIC_KEY`, `CADENCE_ISSUER_KEY`, storage/OAuth/Stripe/Postmark SA creds, `AUTH_SECRET`, across all envs. **No real Cloud KMS exists** (KMS API disabled) — these app-encryption keys live *as secrets*, so this is 100% a secrets problem.
- **Off-provider is mandatory.** GCP-native multi-region replication + versioning + CMEK stay *within* GCP and do NOT survive account/project loss — verified insufficient for #3882.
- **Encryption uses a PUBLIC key; the PRIVATE key is offline.** The cluster/CronJob can encrypt but can **never** decrypt past backups — so a full cluster or GCP compromise cannot read the DR archive. This is the whole security model.
- **No new plaintext at rest.** Plaintext exists only in a memory-backed tmpfs inside the job pod, piped straight into SOPS; never written to a persistent disk, never logged.
- **No new read exposure.** ESO already reads all these secrets, so a read-only exporter SA adds no attack surface beyond what exists; the *only* new artifact is ciphertext useless without the offline key (LastPass lesson: strong offline key, encrypt everything).
- **Reuse existing off-provider stores** — DO Spaces (enable versioning — **API-only; Spaces has no Object Lock**) + on-prem niflheim mirror **with a `--backup-dir` quarantine** (#403 pattern — deletions don't propagate) (see [[onprem-backup-mirror-niflheim]]); no new cloud account required for Option A. Real WORM immutability, if wanted, comes from a 3rd store where Object Lock actually works (B2/Wasabi/R2/S3).
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
| `values/deployments/mycure-production.yaml` | Enable the chart + its ESO remoteKeys (exporter SA, Spaces creds). |
| `docs/operations/SECRETS_DR.md` | Runbook: verify, restore/break-glass, key escrow policy, quarterly drill. |

**Human prerequisites (not chart-managed):**
- **P1. Generate the age key pair OFFLINE** (`age-keygen`) on an air-gapped/trusted machine. Commit only the **public** recipient (`age1...`). The **private** key is escrowed per the policy in Task 5 — never touches GCP, the cluster, or git.
- **P2. Create a read-only exporter GCP SA** in `mc-v4-prod` with `roles/secretmanager.viewer` + `roles/secretmanager.secretAccessor` (list + access, NO write/delete). Store its JSON key in Secret Manager as `mycure-production-secrets-dr-exporter-sa` (ESO reads it). `# ponytail: reuse ESO's existing reader SA only if it's already read-only-scoped; else a dedicated one keeps blast radius to read.`
- **P3. Create the DO Spaces backup bucket** with **versioning** (API-only, `mc version enable` — **Spaces has no Object Lock, don't rely on it**) (e.g. `mycure-secrets-dr`), and confirm the niflheim mirror covers its prefix **with a `--backup-dir` quarantine** (not a plain delete-propagating sync).
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
image: "docker.io/google/cloud-sdk:slim"   # has gcloud + gsutil; SOPS+age installed in-script or baked
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

> **Image note:** `cloud-sdk:slim` has `gcloud`/`aws` but not `sops`/`age`/`jq` — either add an `initContainer`/in-script install, or bake a small image with `gcloud + aws + sops + age + jq` (preferred; pin it). Resolve at implementation; `# ponytail: bake one pinned image, don't apt-install on every run`.

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
  - [ ] Spaces bucket has versioning (API-only); niflheim mirror covers the prefix **with `--backup-dir` quarantine** (no delete-propagation).
  - [ ] NetworkPolicy limits egress to DNS + 443.

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
4. Re-create secrets in a new/recovered project:
       jq -r 'to_entries[] | "\(.key)\t\(.value)"' /dev/shm/secrets.json | \
       while IFS=$'\t' read -r NAME B64; do
         printf '%s' "$B64" | base64 -d | \
           gcloud secrets create "$NAME" --project=<new> --data-file=- 2>/dev/null || \
         printf '%s' "$B64" | base64 -d | \
           gcloud secrets versions add "$NAME" --project=<new> --data-file=-
       done
5. Repoint ESO ClusterSecretStore at <new>; shred /dev/shm/secrets.json.

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

## Self-Review

**Spec coverage:** off-provider requirement → Spaces+niflheim, offline age key (Task 2/5). All 115 secrets → `gcloud secrets list` loop (Task 2). Break-glass restore → Task 5. Provider-specific alternative researched + documented (Vault import / HCP / Akeyless / Infisical) → Task 5, not built (Option A priority). Minimal surface → read-only SA + public-key encryption + tmpfs (Global Constraints). ✅

**Open items for biz/owner decision (issue #3882):**
1. **age private-key escrow** — who are the M-of-N custodians and the threshold (recommend 2-of-3)? This is the entire security model.
2. **Off-provider stores** — Spaces (versioning) + niflheim (`--backup-dir` quarantine) sufficient, or add a 3rd store where **Object Lock actually works** (Backblaze B2 / Wasabi / Cloudflare R2 / AWS S3) for true WORM? The Spaces write key lives in-cluster, so without an immutable copy a cluster compromise could delete the Spaces archive — the on-prem quarantine closes that half; a WORM 3rd store closes it fully. <100 MB ciphertext → cents/mo.
3. **Warm standby** — build the provider-specific Vault/Akeyless/Infisical layer now, or defer (plan defers it; Option A only).
4. **Cadence/retention** — daily export + 90 daily versions OK?

**Placeholder scan:** `<obj>`, `<new>`, `age1...`, `<name/role>` are runtime/escrow fill-ins, not logic gaps. Image needs `sops+age+jq+gcloud+aws` baked (noted in Task 2). No TODO logic.

**Type consistency:** Secret name `secrets-dr-backup` and keys `gcp-sa.json`/`spaces-access-key`/`spaces-secret-key` consistent across externalsecret (Task 1) and cronjob (Task 2); ConfigMap `secrets-dr-backup-script` + `export.sh`/`recipients.txt` consistent between configmap and cronjob mounts. ✅
