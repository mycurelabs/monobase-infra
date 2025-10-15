# Falco Custom Rules

Custom Falco rules specific to monobase-infra deployments.

## Rules Catalog

| Rule File | Purpose | Priority |
|-----------|---------|----------|
| **api-rules.yaml** | Monobase API specific detections | Warning-Critical |
| **database-rules.yaml** | PostgreSQL specific detections | Warning-Critical |

## Default Falco Rules

Falco ships with comprehensive default rules that cover:
- Shell spawning in containers
- Sensitive file access (/etc/shadow, SSH keys)
- Package manager execution (apt, yum, pip)
- Unexpected network activity
- File modifications in /bin, /sbin, /usr/bin
- Privilege escalation attempts
- Container drift detection

**These default rules are always active.**

## Custom Rules

### api-rules.yaml

Detections specific to Monobase API:
- Database credential file access
- API config file modifications
- Unexpected process spawning
- High-privilege API calls

### database-rules.yaml

Detections specific to PostgreSQL:
- Direct database file access (bypassing postgres process)
- Backup tampering
- Unauthorized DB connection attempts
- postgresql.conf modifications

## Applying Rules

### Deploy All Custom Rules

```bash
# Create ConfigMap from rules
kubectl create configmap falco-custom-rules \
  --from-file=. \
  -n falco

# Restart Falco to load new rules
kubectl rollout restart daemonset/falco -n falco
```

### Deploy Specific Rule

```bash
kubectl create configmap falco-custom-rules \
  --from-file=api-rules.yaml \
  -n falco \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart daemonset/falco -n falco
```

### Verify Rules Loaded

```bash
# List all active rules
kubectl exec -it -n falco \
  $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- falco --list

# Check for custom rules
kubectl exec -it -n falco \
  $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- falco --list | grep -E "API|Database"
```

## Testing Rules

### Test API Rules

```bash
# Trigger: Read database credentials
kubectl exec -it api-pod -- cat /app/.env

# Check Falco logs
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Database credential"
```

### Test Database Rules

```bash
# Trigger: Direct database file access
kubectl exec -it postgresql-0 -- cat /var/lib/postgresql/data/base/16384/1234

# Check Falco logs
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Direct database file"
```

## Rule Structure

Falco rules consist of:

**1. Lists** - Reusable sets of items
```yaml
- list: database_credentials_files
  items: [.env, database.yml, credentials.json]
```

**2. Macros** - Reusable conditions
```yaml
- macro: api_container
  condition: container.image.repository contains "monobase-api"
```

**3. Rules** - Actual detections
```yaml
- rule: Database Credentials Access
  desc: Detect access to database credential files
  condition: open_read and api_container and fd.name in (database_credentials_files)
  output: >
    Database credentials accessed
    (user=%user.name container=%container.name file=%fd.name)
  priority: WARNING
```

## Customizing Rules

### Adjust Priority

```yaml
# In rule definition
priority: NOTICE  # Was WARNING
```

**Priority levels:**
- DEBUG
- INFORMATIONAL
- NOTICE
- WARNING
- ERROR
- CRITICAL
- ALERT
- EMERGENCY

### Add Exclusions

```yaml
# Exclude known-good processes
- macro: known_credential_readers
  condition: proc.name in (vault-agent, secrets-init)

- rule: Database Credentials Access
  condition: >
    open_read and
    api_container and
    fd.name in (database_credentials_files) and
    not known_credential_readers
```

### Filter by Namespace

```yaml
# Only monitor production
- macro: production_namespace
  condition: k8s.ns.name glob "*-prod"

- rule: Database Credentials Access
  condition: >
    production_namespace and
    open_read and
    api_container and
    fd.name in (database_credentials_files)
```

## Rule Performance

### Check Rule Execution Time

```bash
# View Falco metrics
kubectl port-forward -n falco svc/falco-metrics 8765:8765
curl http://localhost:8765/metrics | grep falco_rules
```

### Optimize Slow Rules

**1. Use specific conditions first:**
```yaml
# Good: Check container first (fast)
condition: api_container and open_read and fd.name contains ".env"

# Bad: Check file first (slow - many files)
condition: fd.name contains ".env" and open_read and api_container
```

**2. Use lists instead of multiple ORs:**
```yaml
# Good
- list: credential_files
  items: [.env, credentials.json, database.yml]

condition: fd.name in (credential_files)

# Bad
condition: (fd.name=".env" or fd.name="credentials.json" or fd.name="database.yml")
```

## Troubleshooting

### Rule Not Triggering

**1. Check rule is loaded:**
```bash
kubectl exec -it -n falco \
  $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) \
  -- falco --list | grep "Your Rule Name"
```

**2. Test with simple trigger:**
```bash
# Known trigger
kubectl exec -it api-pod -- /bin/bash
```

**3. Check priority level:**
```yaml
# If priority is too low, it won't alert
falco:
  priority: warning  # Rule must be WARNING or higher
```

### Too Many False Positives

**1. Add process exclusions:**
```yaml
- list: known_safe_processes
  items: [healthcheck, metrics-collector]

condition: ... and not proc.name in (known_safe_processes)
```

**2. Lower priority:**
```yaml
priority: NOTICE  # Was WARNING
```

**3. Add time-based filtering:**
```yaml
# Only alert during business hours
- macro: business_hours
  condition: evt.time.h >= 9 and evt.time.h <= 17
```

## See Also

- [Falco Rules Reference](https://falco.org/docs/rules/)
- [Falco Rule Examples](https://github.com/falcosecurity/rules/tree/main/rules)
- [Falco Documentation](../README.md)
