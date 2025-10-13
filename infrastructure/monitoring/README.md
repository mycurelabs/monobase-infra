# Monitoring Stack (Optional)

Production-grade monitoring with Prometheus, Grafana, and Alertmanager.

## When to Enable

✅ **Production environments** - Visibility into system health
✅ **After initial deployment** - Once baseline established
✅ **>100 users** - When monitoring overhead is justified

❌ **Dev/staging** - Usually disabled to save resources
❌ **<100 users** - Overhead may outweigh benefits

## Stack Components

- **Prometheus** - Metrics collection and storage (15d retention)
- **Grafana** - Dashboards and visualization
- **Alertmanager** - Alert routing to Slack/PagerDuty/Email
- **Node Exporter** - Node-level metrics
- **Kube State Metrics** - Kubernetes object metrics

## Installation

```bash
# Install kube-prometheus-stack (includes everything)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \\
  --namespace monitoring \\
  --create-namespace \\
  --values helm-values.yaml
```

## Files

- `helm-values.yaml` - kube-prometheus-stack configuration
- `prometheus-rules.yaml` - Alert rules (HapiHub, MongoDB, MinIO)
- `grafana-dashboards/` - Pre-configured dashboards
- `httproute.yaml.template` - Grafana UI access via Gateway

## Pre-Configured Dashboards

1. **Kubernetes Cluster** - Overall cluster health
2. **HapiHub** - Application metrics
3. **MongoDB** - Database performance
4. **MinIO** - Storage metrics
5. **Longhorn** - Storage health

## Resource Overhead

```
Component            | CPU   | Memory | Storage
---------------------|-------|--------|--------
Prometheus           | 500m  | 1Gi    | 50Gi
Grafana              | 100m  | 150Mi  | 10Gi
Alertmanager         | 50m   | 50Mi   | 2Gi
Node Exporter (×3)   | 150m  | 150Mi  | -
Kube State Metrics   | 50m   | 100Mi  | -
---------------------|-------|--------|--------
Total                | ~850m | ~1.5Gi | ~62Gi
```

**Decision:** ~3-5% overhead for <500 users is acceptable for production.

## Access Grafana

```bash
# Port-forward
kubectl port-forward -n monitoring svc/monitoring-grafana 8080:80

# Get admin password
kubectl -n monitoring get secret monitoring-grafana \\
  -o jsonpath="{.data.admin-password}" | base64 -d

# Open http://localhost:8080
```

## Phase 3 Implementation

Full implementation includes:
- Complete Helm values with HA
- Custom alert rules for HapiHub
- Pre-configured Grafana dashboards
- Integration with Slack/PagerDuty
- Backup monitoring alerts (Velero)
- Security metrics and alerts
