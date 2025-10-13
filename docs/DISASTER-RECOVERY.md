# Disaster Recovery Procedures

Complete disaster recovery runbooks for LFH Infrastructure.

## RTO/RPO Summary

| Scenario | RTO | RPO | Recovery Method |
|----------|-----|-----|-----------------|
| Pod failure | 0s | 0 | Kubernetes auto-restart |
| Node failure | <30s | 0 | Pod rescheduling |
| Database corruption | 1h | 24h | Velero daily backup |
| Namespace deletion | 2h | 24h | Velero restore |
| Complete cluster failure | 4h | 1w | New cluster + weekly archive |
| Region failure | 8h | 1w | Cross-region restore |
| Ransomware attack | 12h | 1w | Clean cluster + old backup |

## DR Scenario Runbooks

### Scenario 1: Accidental Namespace Deletion

**Detection:** Namespace and all resources deleted
**RTO:** 1-2 hours | **RPO:** 24 hours

```bash
# 1. Verify namespace deleted
kubectl get namespace myclient-prod
# Error: namespace "myclient-prod" not found

# 2. List recent backups
velero backup get | grep myclient-prod

# 3. Restore from latest daily backup
velero restore create emergency-restore-$(date +%Y%m%d) \
  --from-backup daily-full-20250115020000 \
  --wait

# 4. Monitor restore
velero restore describe emergency-restore-20250115
velero restore logs emergency-restore-20250115

# 5. Verify pods running
kubectl get pods -n myclient-prod

# 6. Test endpoints
curl https://api.myclient.com/health

# 7. Document incident
# - What was deleted
# - When detected
# - Restore time
# - Data loss assessment
```

### Scenario 2: Complete Cluster Failure

**Detection:** All nodes down, cluster unreachable
**RTO:** 4-8 hours | **RPO:** 1 week

```bash
# 1. Provision new Kubernetes cluster
# (Use same cloud provider for S3 access)

# 2. Deploy core infrastructure
kubectl apply -f infrastructure/longhorn/
kubectl apply -f infrastructure/envoy-gateway/
kubectl apply -f infrastructure/external-secrets-operator/
kubectl apply -f infrastructure/cert-manager/

# 3. Install Velero with SAME S3 bucket
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set configuration.backupStorageLocation[0].bucket=myclient-prod-backups \
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \
  --set credentials.existingSecret=velero-credentials

# 4. List available backups (from old cluster)
velero backup get

# 5. Restore from weekly archive
velero restore create cluster-rebuild-$(date +%Y%m%d) \
  --from-backup weekly-archive-20250108030000 \
  --wait

# 6. Verify all resources
kubectl get all -n myclient-prod

# 7. Get new LoadBalancer IP
kubectl get gateway shared-gateway -n gateway-system \
  -o jsonpath='{.status.addresses[0].value}'

# 8. Update DNS records
# Point all A records to new LoadBalancer IP

# 9. Test all endpoints
curl https://api.myclient.com/health
curl https://app.myclient.com

# 10. Notify stakeholders of recovery
```

### Scenario 3: Data Corruption in MongoDB

**Detection:** Invalid data, query errors
**RTO:** 2-3 hours | **RPO:** 24 hours

```bash
# 1. Stop write operations immediately
kubectl scale deployment hapihub --replicas=0 -n myclient-prod
kubectl scale deployment syncd --replicas=0 -n myclient-prod

# 2. Backup CURRENT state (corrupted)
velero backup create corruption-snapshot-$(date +%Y%m%d-%H%M) \
  --include-namespaces myclient-prod \
  --wait

# 3. Identify last known-good backup
velero backup get | grep Completed
# Review backup times, choose backup BEFORE corruption

# 4. Delete corrupted database
kubectl delete statefulset mongodb -n myclient-prod --cascade=false
kubectl delete pvc -l app.kubernetes.io/name=mongodb -n myclient-prod

# 5. Restore database from clean backup
velero restore create db-corruption-fix \
  --from-backup daily-full-20250114020000 \
  --include-resources statefulsets,persistentvolumeclaims \
  --selector app.kubernetes.io/name=mongodb \
  --wait

# 6. Wait for MongoDB ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=mongodb \
  -n myclient-prod \
  --timeout=600s

# 7. Verify database integrity
kubectl exec -it mongodb-0 -n myclient-prod -- mongosh --eval "db.stats()"

# 8. Restart applications
kubectl scale deployment hapihub --replicas=3 -n myclient-prod
kubectl scale deployment syncd --replicas=2 -n myclient-prod

# 9. Monitor for issues
kubectl logs -f deployment/hapihub -n myclient-prod

# 10. Assess data loss
# Compare current data with backup timestamp
# Notify affected users if needed
```

## DR Testing Schedule

### Monthly DR Test (Required)

```bash
# Run restore test to verify backups work
# See: infrastructure/velero/restore-examples.yaml
# Test procedure documented in BACKUP-RECOVERY.md

# 1. Restore to test namespace
# 2. Verify all pods start
# 3. Test application functionality
# 4. Document results
# 5. Cleanup test namespace
```

### Quarterly DR Drill (Recommended)

```bash
# Full disaster recovery simulation
# 1. Simulate cluster failure (drain all nodes)
# 2. Build new cluster
# 3. Restore from backup
# 4. Measure RTO
# 5. Verify RPO
# 6. Document lessons learned
```

## Backup Strategy (3-Tier)

**Tier 1: Hourly Snapshots (Fast Recovery)**
- Storage: Longhorn local
- Retention: 72 hours
- RTO: 5 minutes
- RPO: 1 hour

**Tier 2: Daily Backups (Medium Recovery)**
- Storage: S3
- Retention: 30 days
- RTO: 1 hour
- RPO: 24 hours

**Tier 3: Weekly Archives (Long-Term)**
- Storage: S3 Glacier
- Retention: 90+ days
- RTO: 4 hours
- RPO: 1 week

## Emergency Contacts

**Internal:**
- DevOps Team: devops@mycurelabs.com
- On-Call: See PagerDuty rotation
- Management: escalation@mycurelabs.com

**External:**
- Cloud Provider Support
- Managed Services (if applicable)

## Communication Plan

**During DR Event:**
1. Notify management immediately
2. Update status page
3. Email affected customers
4. Post updates every hour
5. Final incident report within 24h

For detailed backup procedures, see [BACKUP-RECOVERY.md](BACKUP-RECOVERY.md).
