# Gateway Stale-Endpoint Runbook

Diagnosing and fixing **intermittent ~50% `504`/timeouts through the shared nginx gateway to a specific backend after that backend's pod restarts.**

## Symptom

Requests through the shared gateway (`nginx-gateway-system/nginx-shared-gateway`, LB `104.248.98.161`) to one backend intermittently **hang → `000`/`504`** at a roughly **50% rate**. The pattern is binary and interleaved per request (a fast `200` or a full timeout, alternating), not time-clustered.

Tell-tale scoping:
- The backend is **100% healthy when hit directly** (`port-forward` to the pod, or `wget` from an nginx pod to the pod IP).
- **Other hostnames on the same gateway are 100% fine** — e.g. a static frontend, or the same service in a *different namespace whose pods have not restarted*.
- The affected backend recently **restarted** (new pod IP), or was redeployed.

## Root cause

The gateway data plane is **two** `nginx-shared-gateway-nginx-*` pods behind a DigitalOcean `REGIONAL_NETWORK` load balancer that round-robins ~50/50 between them. nginx-gateway-fabric's **controller** (`nginx-gateway-system/nginx-gateway-fabric`) pushes rendered config to each data-plane pod's **nginx-agent** over a gRPC stream.

When the controller crashes/restarts, an **agent stream can wedge** — that data-plane pod's `/etc/nginx/conf.d/http.conf` **freezes** and stops receiving endpoint updates. After a backend's pod IP changes, the wedged pod keeps routing to the **dead old IP**, so the ~50% of client traffic the LB sends to that pod hangs. The healthy pod has the live IP, so the other ~50% works — producing the exact 50% signature.

A backend in a namespace whose pods have **not** changed IP is immune even with a stale config (the old IP is still valid), which is why an unaffected environment on the same gateway stays 100% — this is the fastest way to confirm the diagnosis.

## Diagnose

**Step 1 — Confirm it is stale endpoints, not the gateway/LB (do this first).**
```bash
# Same LB, compare an unaffected env/host vs the failing one. If the unaffected host is
# 100% while the failing one is ~50%, it is stale endpoints for the restarted backend —
# NOT the LB, DNS, keepalive, or capacity.
for h in hapihub.demo.localfirsthealth.com hapihub.preprod.localfirsthealth.com; do
  ok=0; fail=0
  for i in $(seq 1 15); do
    c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "https://$h/.well-known/oauth-authorization-server")
    [ "$c" = 200 ] && ok=$((ok+1)) || fail=$((fail+1))
  done
  echo "$h -> ok=$ok fail=$fail"
done
```

**Step 2 — Find the wedged data-plane pod.** Diff each pod's rendered upstream IP against the live endpoint.
```bash
NS=mycure-preprod SVC=hapihub PORT=7500
LIVE=$(kubectl -n "$NS" get endpointslices -l kubernetes.io/service-name="$SVC" \
  -o jsonpath='{.items[0].endpoints[0].addresses[0]}')
echo "live $SVC = $LIVE"

for p in $(kubectl -n nginx-gateway-system get pods \
    -l gateway.networking.k8s.io/gateway-name=nginx-shared-gateway -o name); do
  ip=$(kubectl -n nginx-gateway-system exec "${p#pod/}" -c nginx -- \
    awk "/upstream ${NS}_${SVC}_${PORT}/{f=1} f{print} /^}/{if(f)exit}" \
    /etc/nginx/conf.d/http.conf | grep -oE "server [0-9.]+:${PORT}")
  ts=$(kubectl -n nginx-gateway-system exec "${p#pod/}" -c nginx -- \
    stat -c '%y' /etc/nginx/conf.d/http.conf)
  echo "$p  upstream=[$ip]  cfg_mtime=$ts"
done
```
A pod whose `upstream` IP `!=` `$LIVE`, or whose `cfg_mtime` is frozen well in the past, is the wedged pod.

## Fix

Delete the wedged data-plane pod. The deployment recreates it; the fresh pod reconnects and pulls current config. The other pod keeps serving throughout.
```bash
kubectl -n nginx-gateway-system delete pod <wedged-pod>
# verify both pods now agree with $LIVE, then re-measure — should be 0% failures
```

For durability, restart the controller to re-establish clean agent streams. **This does not interrupt serving** — the data-plane pods keep serving their current config while the controller is down; only new config pushes pause for ~30-60s.
```bash
kubectl -n nginx-gateway-system rollout restart deploy/nginx-gateway-fabric
```

## Recurrence

This returns whenever a backend restarts while a data-plane agent is wedged. The underlying trigger is **controller instability** (repeated controller crashes break agent streams). If it recurs, investigate why `nginx-gateway-fabric` (controller) is restarting (`kubectl -n nginx-gateway-system describe pod <controller>` / its logs) and address that root cause rather than only cycling data-plane pods.

## Red herrings (ruled out — do not re-chase)

| Suspected | Why it is not the cause |
|-----------|-------------------------|
| DO LB / `externalTrafficPolicy: Local` | An unaffected host on the *same* LB is 100%; the LB fans correctly. |
| DNS | Error is `504` (backend reached), not resolution failure. Note: PodSecurity `restricted` blocks throwaway debug pods in app namespaces, so a "DNS 100% fail" from such a pod is a **test artifact**, not real. |
| nginx upstream keepalive (`UpstreamSettingsPolicy`) | Setting `keepAlive.timeout`/`connections` does not help. A fresh `wget` from an nginx pod to the backend is 100% because it dodges the LB round-robin to the wedged pod, not because of keepalive. |
| Node-pool saturation / nginx CPU | A fresh nginx pod at low CPU on adequate capacity still fails ~50%. |
| Falco | Not installed in this cluster. |
| Cilium drops | `TTL exceeded` counters are historical (zero live delta); no active path drops. |

## History

First diagnosed 2026-07-30 (preprod). A data-plane pod's config had been frozen for hours after the controller crashed 30×; it routed `mycure-preprod` traffic to dead `hapihub`/`cade` pod IPs after those backends were restarted, giving a steady ~50% failure that survived keepalive tuning and a node-pool bump. The demo-vs-preprod same-gateway comparison isolated it; deleting the wedged pod restored 0% failures immediately.
