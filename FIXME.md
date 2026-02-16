# FIXME: api.mycure.md TLS certificate not yet provisioned

## Problem

The `https-mycure` Gateway listener for `*.mycure.md` requires a TLS secret
(`gateway-tls-mycure-md`) that does not exist yet. Without it:

- The listener has `InvalidCertificateRef` and is not programmed in the Envoy data plane
- The `api.mycure.md` hostname on the hapihub HTTPRoute only works on the HTTPS listener
  once the certificate is provisioned
- The EnvoyPatchPolicy for max request headers cannot be applied to `https-mycure`

### Why HTTP-01 doesn't work

Envoy Gateway v1.2.0 has a limitation where additional HTTP listeners (port 80) with
different hostnames are not properly programmed in the Envoy data plane. Routes attached
to the `http-mycure` listener are accepted by the Gateway API controller but never
translated into Envoy route configs. This means cert-manager's HTTP-01 solver route
cannot serve the ACME challenge on port 80 for `api.mycure.md`.

## Solution 1: Add mycure.md to Cloudflare (recommended)

Add the `mycure.md` zone to the Cloudflare account used by the
`letsencrypt-mycure-cloudflare-prod` ClusterIssuer. This allows DNS-01 validation
without needing HTTP-01.

### Steps

1. Add `mycure.md` as a zone in Cloudflare (does not need to be the authoritative DNS;
   Cloudflare only needs to manage the `_acme-challenge` TXT records)

2. Revert the certificate config to use `additionalDomains` instead of
   `additionalCertificates` in `values/infrastructure/main.yaml`:

   ```yaml
   # Under tls.certManager:
   additionalDomains:
     # ... existing domains ...
     - api.mycure.md
   ```

3. Remove `tlsSecretName` from the `https-mycure` listener so it uses the shared
   `gateway-tls` secret:

   ```yaml
   - name: https-mycure
     port: 443
     protocol: HTTPS
     hostname: "*.mycure.md"
     # no tlsSecretName — uses gateway-tls
   ```

4. Revert the gateway chart template change (remove per-listener `tlsSecretName`
   support) since all listeners can share the same certificate.

5. Add `https-mycure` back to the `envoyPatchPolicy.listeners` list.

6. Remove `additionalCertificates` section and the
   `charts/gateway/templates/additional-certificates.yaml` template.

7. Commit, push, and verify ArgoCD syncs the certificate with `api.mycure.md` included.

## Solution 2: Upgrade Envoy Gateway

Upgrade Envoy Gateway to a version that fixes HTTP listener merging for additional
listeners. This would allow cert-manager's HTTP-01 solver to work on port 80 for
`api.mycure.md`.

### Steps

1. Check the Envoy Gateway changelog for fixes related to HTTP listener merging or
   multi-hostname HTTP listener support. The current version is v1.2.0.

2. Update the Envoy Gateway version in `values/infrastructure/main.yaml`:

   ```yaml
   envoyGateway:
     enabled: true
     version: <new-version>
   ```

3. After upgrading, test that HTTP routes on additional listeners (e.g., `http-mycure`)
   are properly programmed in the Envoy data plane.

4. Once confirmed working, the `additionalCertificates` config and
   `additional-certificates.yaml` template will work as designed — cert-manager will
   use the `letsencrypt-prod` HTTP-01 ClusterIssuer to provision `gateway-tls-mycure-md`.

5. Add `https-mycure` back to the `envoyPatchPolicy.listeners` list.

## Current state of uncommitted changes

The following files have uncommitted changes related to this issue:

- `charts/gateway/templates/gateway.yaml` — per-listener `tlsSecretName` support
- `charts/gateway/templates/additional-certificates.yaml` — new template (untracked)
- `values/infrastructure/main.yaml` — `tlsSecretName`, `additionalCertificates`,
  `https-mycure` removed from envoyPatchPolicy

These changes are correct but inert until a TLS secret is provisioned.

---

# FIXME: Gateway NetworkPolicies in security-baseline should move to app charts

## Problem

Gateway ingress NetworkPolicies are centralized in
`charts/security-baseline/templates/allow-gateway-to-apps.yaml` with a hardcoded
list of apps and ports. This has two issues:

1. **Doesn't scale** — adding a new app requires editing the security-baseline chart
   instead of the app's own chart. `dentalemon-website` was missing entirely.
2. **Single gateway assumption** — all policies hardcode
   `kubernetes.io/metadata.name: envoy-gateway-system`. Apps routed through a
   different gateway (e.g., NGINX Gateway Fabric in `nginx-gateway-system`) need
   separate policies.

## Current state

- `dentalemon-website` now has its own `networkpolicy.yaml` template that derives
  the gateway namespace from `gateway.gatewayNamespace` (works for both Envoy and
  NGINX gateways).
- All other apps (`api`, `hapihub`, `mycure`, `account`, `minio`, `api-worker`)
  still rely on the centralized `allow-gateway-to-apps.yaml`.

## Fix

For each app in `allow-gateway-to-apps.yaml`:

1. Add a `templates/networkpolicy.yaml` to the app's chart (use
   `charts/dentalemon-website/templates/networkpolicy.yaml` as the pattern)
2. Use the app's gateway namespace helper (or `global.gateway.namespace`) for
   the `namespaceSelector` so it works regardless of which gateway routes to it
3. Enable `networkPolicy.enabled: true` in the deployment values
4. Remove the app's entry from `allow-gateway-to-apps.yaml`
5. Once all apps are migrated, delete `allow-gateway-to-apps.yaml`
