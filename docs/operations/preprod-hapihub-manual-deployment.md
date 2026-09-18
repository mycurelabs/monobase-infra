# Preproduction HapiHub manual deployment

## Scope and authority

Target only context `k3d-mycure-onprem-vanaheim` (Vanaheim), namespace
`mycure-preprod`; Applications `mycure-preprod-hapihub` and
`mycure-preprod-hapihub-worker` live in `argocd`. No production or staging action.

`hapihub.manualDeployment: true` in `values/deployments/mycure-preprod.yaml`
installs a declarative gate for **both** Applications: no automated sync/prune or
self-heal, sync retry limit zero. Root self-heal preserves this declared gate;
a temporary `kubectl` patch is not the gate. Merging installs the gate, **not
permission to upgrade**. Root sync is not permission to recursively sync children.
A manual sync can still run: ownership and approval remain operator duties.
Re-enable automation only in a separate reviewed change after successful rollout.

The main release alone owns the role-provision configuration, role-provision Job,
and migration Job (PreSync weights `-6`, `-5`, `0`). Worker overrides cannot enable
duplicate hooks or bypass the shared gate. Under the gate, both Jobs have
`backoffLimit: 0`, `restartPolicy: Never`, no time-to-live (TTL) cleanup, and no
`HookFailed`/`HookSucceeded` deletion. `BeforeHookCreation` is deliberately retained:
**archive all first-failure evidence before any newly authorized manual sync**,
which can replace the previous hooks. Retain successful hook evidence too.
This is not eternal log storage: node failure, eviction, or manual deletion can
still lose evidence. Export it promptly to protected storage outside the cluster.

## Before merge, then verify the installed gate

1. Resolve the existing review hold through the authorized reviewer; pin and
   review the actual base/head and rendered manifests. Run
   `mise run test-hapihub-manual-deployment` and targeted Helm lint/render checks.
2. Before merge, the operator checks **both** live Applications for active or
   pending/queued operations, including retries. Inspect `.operation` and
   `.status.operationState` (phase, retry count, timestamps), plus the root's
   operation and any operator/automation queue that could initiate a child sync.
   On Vanaheim, use this explicitly pinned read-only check:

   ```sh
   /usr/bin/mise x kubectl@1.31.1 -- kubectl \
     --kubeconfig /home/freyr/.kube/config \
     --context k3d-mycure-onprem-vanaheim -n argocd get applications \
     mycure-preprod-hapihub mycure-preprod-hapihub-worker -o yaml
   ```

   Store operation metadata privately. Do not merge/rely on the gate if either
   operation is active or pending; seek operator resolution and new verification.
   Disabling automation **does not cancel an already-running or queued operation**.
3. After the authorized merge and root reconciliation, inspect the actual two
   Application specifications: `.spec.syncPolicy.automated` must be **absent**,
   `.spec.syncPolicy.retry.limit` must be `0`, and both child values must contain
   `manualDeployment: true`. Verify the reviewed source revision, root convergence,
   no active/pending operations or queued retries, and no unexpected rollout.
   Do not infer installation from Git alone. Stop if these checks fail.

## Separately authorized rollout

1. Obtain explicit operator approval for one HapiHub manual sync, not a recursive
   root sync or a simultaneous worker sync. Recheck the gate and operation queues
   immediately before execution. Do not selectively sync resources (that skips
   hooks); do not use prune, force, replace, reset, or retry overrides above zero.
2. Capture current ledger/object state, running images, readiness, and the existing
   healthy Maestroapp `2.1.116` peer baseline. Do not downgrade it. Check the
   protected backup's freshness against intervening writes and the recovery point
   the operator accepts. Refresh/rehearse as needed; historical rehearsal evidence
   is not a current backup. Verify an off-host copy or explicitly accept that
   whole-Vanaheim loss remains uncovered. Never publish dumps, credentials, or
   sensitive logs in the repository or review discussion.
3. Verify the reviewed `11.20.126` image provenance, current tag resolution and
   platform manifest; record immutable identifiers. The tag and `IfNotPresent`
   are not immutable proof. Verify the actual migration container and both
   Deployments' runtime image identifiers as they run. Check ledger and target
   objects for pending `0101-0103`, including partial/invalid objects, and validate
   the role/secret references and grants without exposing credentials. Provisioning
   must precede migration: the historical restore needed database-level grants
   absent from its dump. Do not skip it or migrate as the runtime role.
4. Export any existing hook/Pod logs and operation metadata before replacing hooks.
   With those checks and approval complete, the operator performs **one full sync**
   of `mycure-preprod-hapihub` with `argocd app sync`: explicitly supply `--server`
   with the verified preproduction Argo CD server address and `--retry-limit 0`.
   Verify that server's Application destination matches this cluster/namespace;
   never rely on the client's default server or context. No automatic retry is
   authorized. Watch provision then migrate; the worker remains untouched.
5. Require successful hooks, expected ledger **102** and target-object state,
   verified HapiHub runtime image, readiness and route checks before separately
   approving and manually syncing `mycure-preprod-hapihub-worker` with retry limit
   `0` and the same explicitly verified `--server`, again without selective sync,
   prune, force, or reset. Verify worker readiness,
   runtime image, and existing `.116` peer health. If the ledger differs from the
   reviewed starting point, stop for review rather than forcing a count.
6. Preserve evidence and the closed automation gate. `.124` already contains
   `billing_items.taxes`; `0101-0103` are cloud-only for this 76-collection contract.
   `.126` is application/migration parity, **not a proven admission repair**.
   The running Cadence startup/admission fingerprint remains unknown: a catalog
   fingerprint is not proof of the in-memory one. Fresh Windows `.111` enrollment,
   admission, heartbeats and application checks need their own authorization.
   Keep Cadence `2.1.103` unchanged; no Cadence restart without separate evidence
   and approval, including assessment of the existing `.116` peer.

## Failure: stop, preserve, investigate

Keep both gates closed. Do not issue a second sync or retry, delete a failed Job,
reset state, prune resources, or restart Cadence. Promptly export privately:

- First provision/migration Job and Pod manifests/status, all container logs,
  events, exit reasons and timestamps (including previous logs if available).
- Both Applications' operation metadata, source revision, sync result/retry state,
  reviewed/rendered values, and observed image identifiers.
- Ledger and affected object/index state, backup identity and recovery-point facts,
  without publishing sensitive data or secret values.

Inspect the first error and partial schema/ownership state before proposing repair.
`BeforeHookCreation` deletes the old hook on another sync, so evidence archival
must complete **before** a newly approved attempt. Job retention alone is not an
archive. Require new explicit approval before any retry or restore. An image
rollback is **not** a schema rollback; restore entails a separate downtime/data-loss
and recovery-point decision. Never delete/reset namespaces, volumes, or storage
identities as recovery. No production or staging action is authorized here.
