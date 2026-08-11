# FIXME tracker

## OPEN: Migrate Gateway NetworkPolicies from security-baseline to per-app charts

**Status**: Partial — 4 of 6 FIXME-listed apps have per-app NetworkPolicy templates,
but the centralized policies in `allow-gateway-to-apps.yaml` were never removed,
so the apps now have duplicate NetworkPolicies (additive — works, but defeats the
migration).

### Original problem

Gateway ingress NetworkPolicies were centralized in
`charts/security-baseline/templates/allow-gateway-to-apps.yaml` with hardcoded
app names, ports, and a hardcoded `envoy-gateway-system` namespace selector. This
broke when `dentalemon-website` was added (missing entirely) and when apps moved
to NGINX Gateway (wrong namespace selector).

### Current state

**Per-app `templates/networkpolicy.yaml` files now exist** in 11 charts:

| Chart | Was in original FIXME? |
|---|---|
| `charts/api/templates/networkpolicy.yaml` | ✅ FIXME target |
| `charts/account/templates/networkpolicy.yaml` | ✅ FIXME target |
| `charts/hapihub/templates/networkpolicy.yaml` | ✅ FIXME target |
| `charts/mycure/templates/networkpolicy.yaml` | ✅ FIXME target |
| `charts/dentalemon-website/templates/networkpolicy.yaml` | (already done at FIXME time) |
| `charts/dentalemon/templates/networkpolicy.yaml` | bonus |
| `charts/hapihub-docs/templates/networkpolicy.yaml` | bonus |
| `charts/mycurelocal/templates/networkpolicy.yaml` | bonus |
| `charts/mycurev8/templates/networkpolicy.yaml` | bonus |
| `charts/syncd/templates/networkpolicy.yaml` | bonus |
| `charts/external-dns/templates/networkpolicy.yaml` | bonus |

**`allow-gateway-to-apps.yaml` still contains all 6 original entries**, now
duplicating the per-app policies for `api`, `account`, `hapihub`, `mycure`:

- `allow-gateway-to-api`
- `allow-gateway-to-api-worker`
- `allow-gateway-to-account`
- `allow-gateway-to-hapihub`
- `allow-gateway-to-mycure`
- `allow-gateway-to-minio`

**Edge cases** — neither `minio` nor `api-worker` has a local chart:

- `charts/minio/` does not exist — MinIO is a Bitnami subchart of `hapihub` (and
  others). It cannot host its own NetworkPolicy template the same way.
- `charts/api-worker/` does not exist — verify whether `api-worker` is still
  deployed anywhere; if not, the entry should be dropped entirely.

### Remaining work

1. Remove the duplicated entries from
   `charts/security-baseline/templates/allow-gateway-to-apps.yaml`:
   - `allow-gateway-to-api`
   - `allow-gateway-to-account`
   - `allow-gateway-to-hapihub`
   - `allow-gateway-to-mycure`
2. Verify `networkPolicy.enabled: true` in deployment values for those four apps
   so the per-chart policies actually render.
3. Decide on `api-worker`:
   - If still deployed: create a chart (or its own NetworkPolicy template) and
     migrate
   - If retired: drop the entry from `allow-gateway-to-apps.yaml` entirely
4. Decide on `minio`:
   - Option A: keep `allow-gateway-to-minio` in the centralized file as a special
     case for the Bitnami subchart
   - Option B: add the NetworkPolicy as part of the parent chart (e.g.,
     `charts/hapihub/templates/networkpolicy-minio.yaml`) where minio is exposed
5. Once 1-4 are done and the centralized file only contains residual edge cases
   (or is empty), either delete `allow-gateway-to-apps.yaml` or keep it solely
   for documented exceptions
