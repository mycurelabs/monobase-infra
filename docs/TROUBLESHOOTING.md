# Troubleshooting Guide

Common issues and solutions for Monobase Infrastructure.

## Quick Diagnostics

```bash
# Check all pods
kubectl get pods -A | grep -v Running

# Check events
kubectl get events -n myclient-prod --sort-by='.lastTimestamp' | tail -20

# Check logs
kubectl logs -n myclient-prod deployment/api --tail=100
```

##Common Issues

### Pods Not Starting

**Issue:** Pods stuck in Pending, ImagePullBackOff, or CrashLoopBackOff

**Diagnostics:**
```bash
kubectl describe pod <pod-name> -n myclient-prod
kubectl logs <pod-name> -n myclient-prod
```

**Solutions:**
- **Pending:** Check resources, PVC binding, node selector
- **ImagePullBackOff:** Check image name, registry credentials
- **CrashLoopBackOff:** Check logs, environment variables, secrets

### Secrets Not Syncing

```bash
# Check ExternalSecret
kubectl get externalsecrets -n myclient-prod
kubectl describe externalsecret api-secrets -n myclient-prod

# Common fixes:
# 1. Check SecretStore exists
# 2. Verify KMS permissions (IAM/RBAC)
# 3. Check secret exists in KMS
# 4. Verify External Secrets Operator running
```

### Gateway Not Working

```bash
# Check Gateway status
kubectl get gateway -n gateway-system
kubectl describe gateway shared-gateway -n gateway-system

# Check HTTPRoutes
kubectl get httproute -A

# Test routing
curl -v https://api.myclient.com
```

### Storage Issues

```bash
# PVC stuck Pending
kubectl describe pvc postgresql-data -n myclient-prod
# Check: StorageClass exists, Longhorn healthy

# Volume degraded
kubectl get volumes.longhorn.io -n longhorn-system
# Check Longhorn UI for details
```

### Backup Failures

```bash
# Check Velero backups
velero backup get

# Check logs
velero backup logs <backup-name>

# Common issues:
# - S3 permissions
# - Disk space
# - Timeout (increase in schedule)
```

## Emergency Procedures

### Complete Outage

```bash
# 1. Check cluster
kubectl cluster-info

# 2. Check critical pods
kubectl get pods -n gateway-system
kubectl get pods -n myclient-prod

# 3. If Gateway down, restart
kubectl rollout restart deployment -n gateway-system

# 4. If database down, check Longhorn
kubectl get pods -n longhorn-system
```

### Roll Back Deployment

```bash
# Via Helm
helm rollback api -n myclient-prod

# Via ArgoCD
argocd app rollback myclient-prod-api
```

## Getting Help

- **Documentation:** docs/ directory
- **Issues:** GitHub Issues
- **Support:** support@example.com
