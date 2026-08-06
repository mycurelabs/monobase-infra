# Falco Resources Helm Chart

Custom Falco runtime security detection rules for Monobase applications.

## Overview

This chart deploys custom Falco rules that extend the default Falco ruleset with application-specific detection logic for:

- **API Applications**: Detects suspicious activity in Monobase API containers
- **PostgreSQL Databases**: Monitors database containers for unauthorized access and tampering

## Prerequisites

- Falco installed in cluster (creates Falco CRDs and runs DaemonSet)
- Kubernetes 1.19+
- Helm 3.0+

## Installation

```bash
# Install with default settings (all rules enabled)
helm install falco-resources ./charts/falco-resources

# Install with specific rules disabled
helm install falco-resources ./charts/falco-resources \
  --set rules.database.enabled=false
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `namespace` | Namespace where Falco is deployed | `falco` |
| `rules.api.enabled` | Enable API security rules | `true` |
| `rules.database.enabled` | Enable PostgreSQL security rules | `true` |

See [values.yaml](values.yaml) for full configuration options.

## Rule Sets

### API Security Rules (8 rules)

Monitors Monobase API containers for:

1. **Database Credentials Access**: Alerts when `.env` or credential files are read
2. **API Config Modification**: Detects unauthorized changes to configuration files
3. **Unexpected Processes**: Alerts when non-Node.js processes spawn in API containers
4. **Sensitive Directory Access**: Monitors access to `/app/secrets` and similar directories
5. **Package Manager in Production**: Detects `npm install` in production (immutable containers)
6. **Binary Modification**: Alerts on changes to `node_modules` or libraries (potential backdoor)
7. **Unexpected Outbound Connections**: Detects API connecting to non-whitelisted hosts
8. **Authentication Brute Force**: High volume of failed authentication attempts

### PostgreSQL Security Rules (10 rules)

Monitors PostgreSQL containers for:

1. **Direct Data File Access**: Detects file-level access bypassing postgres process (data theft)
2. **Config File Modification**: Alerts on changes to `postgresql.conf` or `pg_hba.conf`
3. **Unexpected Processes**: Non-postgres processes spawning in database container
4. **Backup Tampering**: Modification or deletion of backup files
5. **Wrong User**: PostgreSQL process running as non-postgres user
6. **Data Directory Changes**: Creation/deletion of directories in data directory
7. **Port Scanning**: Multiple rapid connections to port 5432
8. **Superuser Creation**: New PostgreSQL superuser accounts created
9. **Replication Config Modified**: Changes to replication configuration
10. **Connection Brute Force**: High volume of failed authentication attempts

## Usage with ArgoCD

Deployed automatically via ArgoCD when `falco.enabled=true`:

```yaml
# charts/argocd-infrastructure/templates/falco-rules.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: falco-rules
spec:
  source:
    chart: falco-resources
    path: charts/falco-resources
  helm:
    values: |
      namespace: {{ .Values.falco.namespace }}
      rules:
        api:
          enabled: {{ .Values.falco.rules.api.enabled }}
        database:
          enabled: {{ .Values.falco.rules.database.enabled }}
```

## Testing Rules

### Test API Rules

```bash
# Test Rule 1: Database Credentials Access
kubectl exec -it <api-pod> -- cat /app/.env

# Test Rule 5: Package Manager in Production
kubectl exec -it <api-pod> -- npm install malicious-package

# Test Rule 6: Binary Modification
kubectl exec -it <api-pod> -- echo "backdoor" >> /app/node_modules/express/index.js
```

### Test PostgreSQL Rules

```bash
# Test Rule 1: Direct Data File Access
kubectl exec -it postgresql-0 -- cat /var/lib/postgresql/data/base/16384/1234

# Test Rule 2: Config Modification
kubectl exec -it postgresql-0 -- echo "malicious=true" >> /var/lib/postgresql/data/postgresql.conf

# Test Rule 4: Backup Tampering
kubectl exec -it postgresql-0 -- rm /backups/daily-backup.sql

# Test Rule 8: Superuser Creation
kubectl exec -it postgresql-0 -- psql -U postgres -c "CREATE USER hacker SUPERUSER PASSWORD 'backdoor';"
```

## Viewing Alerts

```bash
# View Falco alerts in real-time
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Search for specific alert types
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Database credentials accessed"
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "PostgreSQL data file"
```

## Customization

To add custom rules or modify existing ones:

1. Edit templates in `charts/falco-resources/templates/`
2. Add new rule sets by creating additional template files
3. Update `values.yaml` to add enable/disable flags for new rules
4. Test with `helm template` before deploying

## Development

```bash
# Lint chart
helm lint ./charts/falco-resources

# Dry-run installation
helm install --dry-run --debug falco-resources ./charts/falco-resources

# Template
helm template falco-resources ./charts/falco-resources
```

## Troubleshooting

### Rules Not Loading

Check Falco logs for syntax errors:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep -i error
```

### Too Many False Positives

Disable specific rules or adjust conditions in template files. Common adjustments:

- Add processes to whitelist (e.g., `known_api_processes`)
- Modify thresholds (e.g., `evt.count > 10` → `evt.count > 20`)
- Add exceptions for specific namespaces or containers

## References

- [Falco Documentation](https://falco.org/docs/)
- [Falco Rules Syntax](https://falco.org/docs/rules/)
- [Falco Default Rules](https://github.com/falcosecurity/rules)
