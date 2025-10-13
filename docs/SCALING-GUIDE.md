# Scaling Guide

Horizontal pod autoscaling, storage expansion, and capacity planning.

## Horizontal Pod Autoscaling (HPA)

### Enable HPA

```yaml
# In config/myclient/values-production.yaml
autoscaling:
  enabled: true
  
  hapihub:
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Monitor HPA

```bash
# Check HPA status
kubectl get hpa -n myclient-prod

# HPA details
kubectl describe hpa hapihub -n myclient-prod

# Watch scaling events
kubectl get events -n myclient-prod --field-selector involvedObject.name=hapihub --watch
```

### Manual Scaling

```bash
# Scale deployment manually
kubectl scale deployment hapihub --replicas=5 -n myclient-prod

# Disable HPA temporarily
kubectl patch hpa hapihub -n myclient-prod \\
  --patch '{"spec":{"maxReplicas":3,"minReplicas":3}}'
```

## Storage Expansion

### Expand PVC (StatefulSet)

```bash
# Automated (Phase 6 script)
./scripts/resize-statefulset-storage.sh mongodb myclient-prod 200Gi

# Manual steps:
# 1. Edit all PVCs
for i in 0 1 2; do
  kubectl patch pvc mongodb-data-mongodb-$i -n myclient-prod \\
    --patch '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
done

# 2. Delete StatefulSet (keeps pods)
kubectl delete sts mongodb -n myclient-prod --cascade=orphan

# 3. Update values and redeploy
# Or manually recreate StatefulSet with new volumeClaimTemplates

# 4. Rolling restart
kubectl delete pod mongodb-0 -n myclient-prod
# Wait for ready, then repeat for mongodb-1, mongodb-2
```

## Capacity Planning

### Monitor Resource Usage

```bash
# CPU/Memory usage
kubectl top pods -n myclient-prod
kubectl top nodes

# Storage usage
kubectl exec -it mongodb-0 -n myclient-prod -- df -h

# MinIO storage
mc du myminio/hapihub-files
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
| HapiHub | 10 pods | MongoDB connections | Add MongoDB read replicas |
| MongoDB | 5 nodes | Replication lag | Implement sharding |
| MinIO | 16 nodes | Erasure coding | Use external S3 |
| Storage | 5TB/node | Longhorn limit | Add nodes or use cloud storage |

## Summary

**Scaling Options:**
- ✅ HPA for pod autoscaling
- ✅ PVC expansion for storage
- ✅ Node addition for capacity
- ✅ MongoDB sharding (advanced)

For storage operations, see [STORAGE.md](STORAGE.md).
