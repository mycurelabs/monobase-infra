# Backup & Disaster Recovery Guide

Complete backup procedures, restore operations, and disaster recovery plans.

## 3-Tier Backup Strategy

| Tier | Frequency | Retention | Storage | RTO | RPO | Use Case |
|------|-----------|-----------|---------|-----|-----|----------|
| **1** | Hourly | 72h | Longhorn (local) | 5 min | 1h | Quick rollback |
| **2** | Daily | 30d | S3 (off-cluster) | 1h | 24h | Recent recovery |
| **3** | Weekly | 90d | S3 Glacier (archive) | 4h | 1w | Compliance, DR |

---

## Backup Operations

### Manual Backup (Velero)

```bash
# Full namespace backup
velero backup create manual-$(date +%Y%m%d-%H%M%S) \\
  --include-namespaces myclient-prod \\
  --snapshot-volumes \\
  --default-volumes-to-fs-backup \\
  --wait

# Selective backup (specific resources)
velero backup create mongodb-only \\
  --include-namespaces myclient-prod \\
  --include-resources statefulsets,persistentvolumeclaims \\
  --selector app.kubernetes.io/name=mongodb

# Backup with hooks (MongoDB consistency)
velero backup create consistent-backup \\
  --include-namespaces myclient-prod \\
  --snapshot-volumes \\
  --wait

# List backups
velero backup get

# Describe backup
velero backup describe manual-20250115-120000

# Download backup logs
velero backup logs manual-20250115-120000
```

### Monitor Backup Status

```bash
# Check scheduled backups
velero schedule get

# Check backup completion
velero backup get | grep Completed

# Check for failures
velero backup get | grep -E 'Failed|PartiallyFailed'

# Verify backup in S3
aws s3 ls s3://myclient-prod-backups/velero/backups/
```

---

## Restore Operations

### Full Namespace Restore

```bash
# Restore everything from backup
velero restore create restore-$(date +%Y%m%d) \\
  --from-backup daily-full-20250115020000 \\
  --wait

# Monitor restore
velero restore describe restore-20250115

# Check restore logs
velero restore logs restore-20250115
```

### Selective Restore

```bash
# Restore only specific resources
velero restore create restore-deployments \\
  --from-backup daily-full-20250115020000 \\
  --include-resources deployments,services,configmaps

# Restore single application
velero restore create restore-hapihub \\
  --from-backup daily-full-20250115020000 \\
  --selector app.kubernetes.io/name=hapihub
```

### Restore to Different Namespace

```bash
# Disaster recovery to new namespace
velero restore create restore-to-dr \\
  --from-backup daily-full-20250115020000 \\
  --namespace-mappings myclient-prod:myclient-dr

# Or restore to completely new cluster
# 1. Install Velero in new cluster
# 2. Point to same S3 bucket
# 3. Run restore command
velero restore create cluster-migration \\
  --from-backup weekly-archive-20250115030000
```

---

## Disaster Recovery Scenarios

### Scenario 1: Accidental Data Deletion

**RTO:** 1 hour | **RPO:** 24 hours

```bash
# 1. Identify last good backup
velero backup get | grep Completed | tail -5

# 2. Restore from daily backup
velero restore create deleted-data-recovery \\
  --from-backup daily-full-20250115020000 \\
  --include-resources persistentvolumeclaims,statefulsets

# 3. Verify data restored
kubectl exec -it mongodb-0 -n myclient-prod -- mongosh
# Check collections

# 4. Resume operations
```

### Scenario 2: Database Corruption

**RTO:** 2 hours | **RPO:** 24 hours

```bash
# 1. Stop write operations
kubectl scale deployment hapihub --replicas=0 -n myclient-prod

# 2. Backup current state (corrupted)
velero backup create corrupted-state-$(date +%Y%m%d) \\
  --include-namespaces myclient-prod

# 3. Delete corrupted database
kubectl delete statefulset mongodb -n myclient-prod
kubectl delete pvc -l app.kubernetes.io/name=mongodb -n myclient-prod

# 4. Restore from backup
velero restore create corruption-recovery \\
  --from-backup daily-full-20250114020000 \\
  --include-resources statefulsets,persistentvolumeclaims \\
  --selector app.kubernetes.io/name=mongodb

# 5. Wait for MongoDB ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mongodb \\
  -n myclient-prod --timeout=600s

# 6. Restart HapiHub
kubectl scale deployment hapihub --replicas=3 -n myclient-prod

# 7. Verify
curl https://api.myclient.com/health
```

### Scenario 3: Complete Cluster Failure

**RTO:** 4 hours | **RPO:** 1 week

```bash
# 1. Provision new Kubernetes cluster
# (EKS, AKS, GKE, or self-hosted)

# 2. Deploy infrastructure
# Follow DEPLOYMENT.md steps 1-8

# 3. Install Velero pointing to same S3 bucket
helm install velero vmware-tanzu/velero \\
  --namespace velero \\
  --create-namespace \\
  --set configuration.backupStorageLocation[0].bucket=myclient-prod-backups \\
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \\
  --set credentials.existingSecret=velero-credentials

# 4. List available backups
velero backup get

# 5. Restore from weekly archive
velero restore create cluster-rebuild \\
  --from-backup weekly-archive-20250108030000 \\
  --wait

# 6. Verify all pods running
kubectl get pods -n myclient-prod

# 7. Update DNS to new LoadBalancer IP
GATEWAY_IP=$(kubectl get gateway shared-gateway -n gateway-system \\
  -o jsonpath='{.status.addresses[0].value}')

# 8. Verify endpoints
curl https://api.myclient.com/health

# 9. Resume operations
```

### Scenario 4: Ransomware Attack

**RTO:** 8 hours | **RPO:** 1 week

```bash
# 1. IMMEDIATELY isolate infected cluster
# - Disable all ingress (delete Gateway)
# - Block all egress (NetworkPolicies)

# 2. Document evidence (forensics)
velero backup create ransomware-evidence-$(date +%Y%m%d)
# Collect logs, audit trails

# 3. Build NEW cluster (do not restore to compromised cluster)

# 4. Restore from OLDEST uninfected backup
# - Check weekly archives
# - Verify backup integrity
# - Restore to new cluster

velero restore create ransomware-recovery \\
  --from-backup weekly-archive-20250101030000

# 5. Security hardening
# - Rotate ALL secrets
# - Patch vulnerabilities
# - Review access logs
# - Update security controls

# 6. Gradual service restoration
# - Test thoroughly before exposing to internet
# - Monitor for reinfection
# - Implement additional controls

# 7. Post-incident
# - Breach notification (HIPAA requirement if PHI accessed)
# - Security assessment
# - Update incident response plan
```

---

## Backup Testing

### Monthly Restore Test

**Test Procedure:**

```bash
# 1. Create test namespace
kubectl create namespace myclient-restore-test

# 2. Restore to test namespace
velero restore create monthly-test-$(date +%Y%m) \\
  --from-backup daily-full-latest \\
  --namespace-mappings myclient-prod:myclient-restore-test \\
  --wait

# 3. Verify data integrity
kubectl exec -it mongodb-0 -n myclient-restore-test -- mongosh

# 4. Test application functionality
kubectl port-forward -n myclient-restore-test svc/hapihub 7500:7500
curl http://localhost:7500/health

# 5. Document results
echo "Restore test $(date): SUCCESS" >> restore-test-log.txt

# 6. Cleanup
kubectl delete namespace myclient-restore-test
```

**Test Checklist:**
- [ ] Backup completes successfully
- [ ] Restore completes without errors
- [ ] All pods start correctly
- [ ] Database data intact
- [ ] Application functionality verified
- [ ] Performance acceptable
- [ ] Test documented

---

## Backup Retention Policy

### Compliance Requirements

**HIPAA:**
- Audit logs: 7 years minimum
- PHI: 6 years minimum
- Backups: 90 days minimum (Tier 3)

**Implementation:**

```yaml
# Tier 1: Hourly (72h retention)
ttl: 72h

# Tier 2: Daily (30d retention)
ttl: 720h

# Tier 3: Weekly (90d retention - HIPAA)
ttl: 2160h

# For longer retention:
# - Use S3 lifecycle policies
# - Transition to Glacier after 90 days
# - Delete after 7 years
```

### Backup Deletion Policy

**Automated Cleanup:**

```bash
# Velero automatically deletes expired backups
# Based on TTL in Schedule

# Manual deletion (if needed)
velero backup delete old-backup-20240115

# Delete multiple backups
velero backup delete --selector backup-schedule=daily-full \\
  --confirm
```

**S3 Lifecycle Policy:**

```json
{
  "Rules": [
    {
      "Id": "transition-to-glacier",
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 2555
      }
    }
  ]
}
```

---

## Recovery Time Objectives (RTO)

### By Component

| Component | Backup Method | RTO | Recovery Steps |
|-----------|--------------|-----|----------------|
| Application Pods | None | 0s | Auto-restart, HA replicas |
| MongoDB | Longhorn snapshot | 5 min | Restore from snapshot |
| MongoDB | Velero daily | 1h | Restore from daily backup |
| Full Namespace | Velero daily | 1-2h | Full namespace restore |
| Complete Cluster | Velero weekly | 4-8h | New cluster + restore |

---

## Summary

**Backup Strategy:**
- ✅ 3-tier protection (hourly, daily, weekly)
- ✅ Automated schedules
- ✅ Encrypted backups
- ✅ Off-cluster storage (S3)
- ✅ HIPAA-compliant retention (90 days+)

**Disaster Recovery:**
- ✅ Tested procedures
- ✅ RTO: 5min - 8h depending on scenario
- ✅ RPO: 1h - 1w depending on tier
- ✅ Cross-cluster restore capability
- ✅ Ransomware recovery plan

**Best Practices:**
- ✅ Monthly restore testing
- ✅ Automated backup monitoring
- ✅ Failure alerting
- ✅ Documentation maintained
- ✅ Team training

For storage operations, see [STORAGE.md](STORAGE.md).
