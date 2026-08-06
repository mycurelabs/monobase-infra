# Scaling Guide

Horizontal pod autoscaling, storage expansion, and capacity planning.

## Horizontal Pod Autoscaling (HPA)

### Enable HPA

```yaml
# In deployments/myclient/values-production.yaml
autoscaling:
  enabled: true
  
  api:
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Monitor HPA

```bash
# Check HPA status
kubectl get hpa -n myclient-prod

# HPA details
kubectl describe hpa api -n myclient-prod

# Watch scaling events
kubectl get events -n myclient-prod --field-selector involvedObject.name=api --watch
```

### Manual Scaling

```bash
# Scale deployment manually
kubectl scale deployment api --replicas=5 -n myclient-prod

# Disable HPA temporarily
kubectl patch hpa api -n myclient-prod \\
  --patch '{"spec":{"maxReplicas":3,"minReplicas":3}}'
```

## Storage Expansion

### Expand PVC (StatefulSet)

```bash
# Automated (Phase 6 script)
./scripts/resize-statefulset-storage.sh postgresql myclient-prod 200Gi

# Manual steps:
# 1. Edit all PVCs
for i in 0 1 2; do
  kubectl patch pvc postgresql-data-postgresql-$i -n myclient-prod \\
    --patch '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
done

# 2. Delete StatefulSet (keeps pods)
kubectl delete sts postgresql -n myclient-prod --cascade=orphan

# 3. Update values and redeploy
# Or manually recreate StatefulSet with new volumeClaimTemplates

# 4. Rolling restart
kubectl delete pod postgresql-0 -n myclient-prod
# Wait for ready, then repeat for postgresql-1, postgresql-2
```

## Capacity Planning

### Monitor Resource Usage

```bash
# CPU/Memory usage
kubectl top pods -n myclient-prod
kubectl top nodes

# Storage usage
kubectl exec -it postgresql-0 -n myclient-prod -- df -h

# MinIO storage
mc du myminio/api-files
```

### When to Scale

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU usage | >70% sustained | Enable HPA or increase limits |
| Memory usage | >80% | Increase memory limits |
| Storage | >70% full | Expand PVCs |
| Request latency | >2s p95 | Add replicas or optimize |
| Error rate | >1% | Investigate, may need scaling |

## Scaling Limits

### Current Architecture Limits

| Component | Current Max | Bottleneck | Solution if Exceeded |
|-----------|-------------|------------|----------------------|
| Monobase API | 10 pods | PostgreSQL connections | Add PostgreSQL read replicas |
| PostgreSQL | 5 nodes | Replication lag | Implement sharding |
| MinIO | 16 nodes | Erasure coding | Use external S3 |
| Storage | 5TB/node | Longhorn limit | Add nodes or use cloud storage |

## Node Pools (DOKS, 2026-08-06 restructure)

Role-based pools; taint key is `node-pool=<pool>:NoSchedule` and charts plumb it
via `global.nodePool` (per-component override: `postgresql.primary.nodePool`).

| Pool | Size | Autoscale | Taint | Hosts |
|------|------|-----------|-------|-------|
| prod-db | 1× g-4vcpu-16gb (dedicated CPU) | fixed 1 | yes | PG primary only |
| prod-apps | s-4vcpu-16gb-amd | 2–3 | yes | mycure-production (incl. PG read replica) |
| infra | 2× s-2vcpu-8gb-amd | fixed 2 | yes | nginx gateway, ArgoCD, ESO, cert-manager, external-dns |
| nonprod | s-4vcpu-8gb | 2–4 | **no** (default landing zone; CoreDNS/konnectivity can't tolerate custom taints) | mycure-preprod, monitoring, velero |

Notes:
- Taints are **placement/blast-radius** controls. Tenant isolation is
  NetworkPolicy + PodSecurity + RBAC at the namespace layer — never cite
  taints as the security boundary.
- ArgoCD is installed by `scripts/bootstrap.ts` (helm), not an Application.
  `values/infrastructure/argocd.yaml` is CANONICAL (reconciled with the live
  release 2026-08-06, chart 9.0.3, verified no-op upgrade). Changes to that
  file require the helm command in its header — merging alone does nothing.
- `kubectl exec` into the `velero` namespace reaches the privileged node-agent,
  which can read the PG data volume. Kopia repos are client-side encrypted and
  DO Spaces/volumes encrypt at rest; the human-access control is kubeconfig
  custody (cluster-admin), not RBAC.

### Runbook: prod-db node failure (unplanned)

The PG primary is a single pod on a single-node pool. Unplanned node loss =
**write outage ~6–12 min** (DOKS auto-replaces the node, PVC reattaches, WAL
replays). Reads keep serving from `postgresql-read-0` on prod-apps.

1. Confirm: `kubectl -n mycure-production get pods -o wide | grep postgresql`
   — primary Pending/ContainerCreating while the pool reprovisions is EXPECTED.
   Do nothing; it self-heals when the replacement node is Ready.
2. Only if the node is NOT being replaced (check `doctl kubernetes cluster
   node-pool get mycure-doks-main prod-db`) or RTO must be shortened:
   promote the replica —
   `kubectl -n mycure-production exec postgresql-read-0 -- pg_ctl promote`
   then repoint the `postgresql-primary` Service selector to the read pod.
   The old primary must then be re-cloned as a replica (see the 2026-06-25
   re-clone notes: startup probe already tolerates the ~90 min basebackup).
3. Planned maintenance instead: `kubectl cordon <prod-db-node>` then
   `kubectl drain <prod-db-node> --ignore-daemonsets --delete-emptydir-data`
   in an off-peak window — write pause ≈ 60–90 s (measured 2026-08-06).

## Summary

**Scaling Options:**
- ✅ HPA for pod autoscaling
- ✅ PVC expansion for storage
- ✅ Node addition for capacity
- ✅ PostgreSQL sharding (advanced)

For storage operations, see [STORAGE.md](STORAGE.md).
