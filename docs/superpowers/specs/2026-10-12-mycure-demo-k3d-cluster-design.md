# mycure-demo on a public k3d cluster (mycure-contabo-demo) — Design

**Date:** 2026-10-12
**Author:** jofftiquez (with Claude)
**Status:** Approved
**Supersedes:** `2026-05-31-mycure-demo-namespace-design.md` (DOKS, prod-key reuse, lean)

## Goal

A preprod-tier environment for client demos, sales and training, running on its own
k3d cluster on a public VPS rather than on vanaheim or DOKS.

## Decisions

| Decision | Choice |
|---|---|
| Env name | `mycure-demo`, domain `demo.localfirsthealth.com`, `global.environment: demo` (schema enum extended) |
| Cluster | `mycure-contabo-demo`, k3d on the VPS (1 server + 2 agents, k3s v1.33.4), own ArgoCD |
| Access | Public internet. VPS 80/443 + UDP 6472/7842 → k3d loadbalancer → servicelb → `nginx-public-gateway` |
| TLS / DNS | Let's Encrypt DNS-01 (Cloudflare); external-dns `upsert-only`, `txtOwnerId: mycure-contabo-demo`, A records → VPS IP |
| Footprint | Full prod shape (HA PG + read replica, API/worker split, roleSplit, HPA, cadence hub + relay, MinIO, mailpit) on prod image tags |
| Off | Medical AI (no GPU), tenzir, Loki, monitoring, velero, tailscale |
| Git ref | `main` (HEAD). Long-lived clusters track `main`; see "Revision" below |
| Secrets | Fresh `mycure-demo-*` keys; scoped SA `external-secrets-demo`; Google OAuth/Stripe stubbed |
| Data | Synthetic, seeded with `scripts/seed.ts --env demo` |
| Hardening | `strictGatewayIngress`, better-auth rate limits, no public route for mailpit or MinIO, apiserver bound to loopback |

## Notable mechanics

- **Source IP is lost** at the k3d loadbalancer, so the gateway Service uses
  `externalTrafficPolicy: Cluster` and the better-auth rate limit is one shared bucket.
- **Persistent PVs:** the `local-k3d` module gained `storage_path`; the demo uses
  `/var/lib/k3d/mycure-contabo-demo` so data survives reboots.
- **Module changes are vanaheim-safe:** new inputs (`storage_path`, `extra_port_mappings`,
  `api_port`) add trigger keys only when set, so vanaheim's plan stays a no-op.
- **nginx-gateway chart:** the per-gateway NginxProxy now also applies to the main
  `gateway` block and accepts `externalTrafficPolicy`. DOKS and vanaheim render unchanged.
- **DOKS guard:** `mycure-demo.yaml` is excluded in the DOKS bootstrap and the chart
  default. The DOKS AppSet must be re-applied before the overlay reaches `main`.

## Revision (2026-10-13): track `main`, not `cluster/demo`

The first draft pointed this cluster at a `cluster/demo` branch, copied from vanaheim.
That was wrong: `cluster/<name>` branches are throwaway refs for disposable dev clusters,
and the demo is long-lived. The cluster now tracks `main` (no `argocd.targetRevision`
override). Consequences: the demo only deploys once the PR merges to `main`, so the DOKS
exclude must be re-applied BEFORE that merge; and the ArgoCD repo-server timeouts moved
into `argocd/argocd.yaml` so `mise run bootstrap` covers the install end to end.

## Runbook

`values/clusters/mycure-contabo-demo/README.md`.

## Out of scope

Medley + Ollama, Loki, tenzir, logical backups, real Google OAuth/Stripe, automating
the manual ArgoCD seeds in `bootstrap.ts`.
