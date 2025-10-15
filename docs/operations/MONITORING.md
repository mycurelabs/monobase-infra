# Monitoring Guide

Complete guide for optional Prometheus + Grafana monitoring stack.

## When to Enable Monitoring

**Enable monitoring when:**
- ✅ Production environment
- ✅ >100 active users
- ✅ Business-critical service
- ✅ Need visibility into system health
- ✅ Want proactive alerting

**Skip monitoring when:**
- ❌ Dev/staging environment
- ❌ <100 users (overhead not justified)
- ❌ Resource-constrained cluster
- ❌ Just starting out

## Resource Overhead

**Monitoring Stack Footprint:**
- CPU: ~850m (Prometheus 500m, Grafana 100m, others 250m)
- Memory: ~1.5Gi (Prometheus 1Gi, Grafana 150Mi, others 350Mi)
- Storage: ~62Gi (Prometheus 50Gi, Grafana 10Gi, Alertmanager 2Gi)
- **Total: ~3-5% overhead** for <500 users

## Enable Monitoring

### In Configuration

```yaml
# config/myclient/values-production.yaml
monitoring:
  enabled: true  # Enable the stack
  
  prometheus:
    retention: 15d  # Adjust based on needs
    storage: 50Gi
  
  alertmanager:
    enabled: true
    config:
      receivers:
        - name: slack
          slackWebhook: ""  # From External Secrets
```

### Deploy

```bash
# Via ArgoCD (automatic when monitoring.enabled: true)
argocd app sync myclient-prod-monitoring

# Or via Helm directly
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f infrastructure/monitoring/helm-values.yaml
```

## Access Grafana

```bash
# Via Gateway (production)
open https://grafana.myclient.com

# Via port-forward (quick access)
./scripts/admin-access.sh grafana

# Login
Username: admin
Password: (from External Secrets or initial secret)
```

## Pre-Configured Dashboards

**Automatically provisioned:**
1. Kubernetes Cluster (ID: 7249)
2. Kubernetes Pods (ID: 6417)
3. PostgreSQL (ID: 2583)
4. Node Exporter (ID: 1860)
5. MinIO (ID: 13502)

## Custom Alerts

**Configured in prometheus-rules.yaml:**
- Monobase API down
- High error rate
- High latency
- PostgreSQL replication lag
- MinIO disk offline
- Velero backup failures
- Storage filling up

## Alert Routing

```yaml
# Configure in values
alertmanager:
  config:
    receivers:
      - name: slack-critical
        slack_configs:
          - api_url: <webhook-url>
            channel: '#alerts-critical'
      
      - name: pagerduty
        pagerduty_configs:
          - service_key: <pagerduty-key>
```

## Scaling Monitoring

**For >1000 users or >10TB data:**
- Add Thanos for long-term storage
- Add Loki for log aggregation
- Consider managed Prometheus (AWS AMP, GCP Cloud Monitoring)

See [SCALING-GUIDE.md](SCALING-GUIDE.md) for details.
