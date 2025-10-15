# Grafana Dashboards

Pre-configured dashboards for monitoring the Monobase Infrastructure stack.

## Included Dashboards

The kube-prometheus-stack Helm chart automatically provisions these dashboards from Grafana.com:

1. **Kubernetes Cluster** (ID: 7249) - Overall cluster health
2. **Kubernetes Pods** (ID: 6417) - Pod-level metrics
3. **PostgreSQL** (ID: 2583) - Database performance
4. **Node Exporter** (ID: 1860) - Node-level system metrics
5. **MinIO** (ID: 13502) - Object storage metrics

These are configured in `infrastructure/monitoring/helm-values.yaml`:

```yaml
grafana:
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
      postgresql:
        gnetId: 2583
      # etc...
```

## Custom Dashboards

To add custom dashboards for Monobase API or other applications:

### Option 1: Import JSON (Recommended for custom dashboards)

1. Create dashboard JSON file in this directory
2. Add to Grafana helm values:

```yaml
grafana:
  dashboards:
    default:
      api-dashboard:
        json: |
          {{ .Files.Get "grafana-dashboards/api-dashboard.json" | indent 10 }}
```

### Option 2: ConfigMap (For existing dashboards)

```bash
# Create ConfigMap with dashboard JSON
kubectl create configmap api-dashboard \\
  --from-file=api-dashboard.json \\
  -n monitoring \\
  --dry-run=client -o yaml | kubectl label -f - grafana_dashboard=1 --local -o yaml | kubectl apply -f -

# Grafana sidecar automatically loads it
```

### Option 3: Grafana.com Dashboard IDs (Easiest)

Add to helm-values.yaml:

```yaml
grafana:
  dashboards:
    default:
      my-dashboard:
        gnetId: 12345  # Dashboard ID from grafana.com
        revision: 1
        datasource: Prometheus
```

## Creating Custom Monobase API Dashboard

Example metrics to visualize:

```promql
# Request rate
rate(http_requests_total{job="api"}[5m])

# Error rate
rate(http_requests_total{job="api",status=~"5.."}[5m])

# Latency (p50, p95, p99)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="api"}[5m]))

# Active connections
api_active_connections

# Database query duration
rate(api_db_query_duration_seconds_sum[5m]) / rate(api_db_query_duration_seconds_count[5m])
```

## Dashboard Development Workflow

1. **Create in Grafana UI**
   - Access: https://grafana.myclient.com
   - Create dashboard interactively
   - Test queries and visualizations

2. **Export JSON**
   - Dashboard Settings → JSON Model
   - Copy JSON

3. **Save to Git**
   - Create file in this directory
   - Update helm-values.yaml to include it

4. **Deploy via ArgoCD**
   - ArgoCD syncs changes
   - Dashboard appears automatically

## Dashboard Best Practices

1. **Use template variables** for flexibility (namespace, environment)
2. **Add annotations** for deployment events
3. **Set appropriate time ranges** and refresh intervals
4. **Organize panels** logically (overview → details)
5. **Use consistent naming** for metrics
6. **Document query rationale** in panel descriptions

## Available Dashboards from Grafana.com

- Kubernetes Cluster: 7249
- Kubernetes Pods: 6417
- PostgreSQL: 2583
- Node Exporter: 1860
- MinIO: 13502
- Envoy: 11022
- ArgoCD: 14584
- Longhorn: 13032
- Velero: 11055

Browse more: https://grafana.com/grafana/dashboards/

## Phase 7 Status

✅ Dashboard configuration in helm-values.yaml
✅ Automatic provisioning from Grafana.com
✅ README with instructions for custom dashboards
🔄 Custom JSON dashboards (create as needed)

For monitoring setup, see [../README.md](../README.md) and [../../docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md).
