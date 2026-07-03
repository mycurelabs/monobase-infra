# SigNoz on-prem PoC (#2096)

Runs **SigNoz on vanaheim** (Docker) and ships **DOKS cluster** metrics + logs (+ trace
capability) to it over Tailscale. Zero cloud cost, zero in-cluster ClickHouse — sidesteps
the ~$100/mo / capacity blocker from #2064. Monitoring is **non-continuous** (only while
vanaheim is up), which #2096 explicitly accepts.

## Architecture
```
DOKS pods ─▶ signoz-k8s-infra (OTel collector, ns signoz-poc)
              │ gRPC OTLP
              ▼
        signoz-otlp Service (ns tailscale)
              │  socat
              ▼
        signoz-egress pod (tailscale node + socat)  ──tailnet──▶  vanaheim
                                                                    │ :14317 (native host-net socat bridge)
                                                                    ▼
                                                            docker 127.0.0.1:4317 (SigNoz ingester)
                                                                    ▼
                                                            ClickHouse + SigNoz UI :8080
```

## Two non-obvious gotchas (baked into the scripts)
1. **Docker-published ports are NOT reachable over Tailscale** — only *native* listeners are
   (that's why Ollama's native `:11434` works). SigNoz's OTLP is docker-published, so a native
   host-network `socat` bridge re-exposes it on `:14317` for tailnet peers.
2. **SigNoz needs first-run org registration before it ingests anything** — until an admin/org
   exists, its opamp server logs `cannot create agent without orgId` and the collector never
   gets its OTLP receiver config (silent failure). `vanaheim/up.sh` registers it via API.

## Run it
```bash
# 1) vanaheim: SigNoz (Docker, latest via foundryctl) + tailnet bridge + onboarding
./vanaheim/up.sh          # idempotent; prints UI url + admin creds file

# 2) DOKS: tailscale egress + k8s-infra collector -> ships to vanaheim
./doks/up.sh
```
- **Team URL (share this):** **https://vanaheim.tail06ec7f.ts.net/** — HTTPS via `tailscale serve`,
  reachable by **tailnet members only** (private; prod telemetry is not on the public internet).
  Teammates just install Tailscale and join `tail06ec7f`. Local on the box: http://localhost:8080.
  - One-time tailnet setup (admin console): enable **DNS → HTTPS Certificates**, and on vanaheim
    `sudo tailscale set --operator=$USER`. `up.sh` then enables serve automatically.
  - **Team access to SigNoz:** invite teammates in **Settings → Members** (per-user accounts,
    recommended), or share the admin login from `vanaheim/.admin-creds` (gitignored).
- **Traces:** infra ships metrics+logs; to see traces, point any OTel-instrumented app at
  `100.120.88.93:14317` (verified with `telemetrygen`). Real app traces = monobase-mycure OTel SDK work.

## Verify
```bash
# cluster data landed (by node / cluster name):
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
 "SELECT resources_string['k8s.node.name'] n, count() FROM signoz_logs.distributed_logs_v2 \
  WHERE timestamp > now()-toIntervalMinute(10) GROUP BY n ORDER BY 2 DESC LIMIT 15"
# collector export health (0 = flowing):
kubectl logs -n signoz-poc -l app.kubernetes.io/component=otel-agent --since=1m | grep -c 'Exporting failed'
```

## Teardown
```bash
./doks/down.sh              # remove DOKS egress + collector + ns
./vanaheim/down.sh             # stop SigNoz + bridge   (add --purge to drop ClickHouse volumes)
```

## Notes / caveats
- Throwaway PoC — **not** GitOps/ArgoCD-managed. The dormant in-cluster SigNoz scaffolding from
  #2064 (`charts/signoz`, gated `signoz.enabled:false`) is separate and untouched.
- Reuses the `mycure-preprod-tailscale-ollama-authkey` GCP secret for the egress tailscale node.
- Non-HA / non-continuous by design (vanaheim workstation). Gaps when vanaheim or the tunnel is down.
