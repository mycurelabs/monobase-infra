# k3d Troubleshooting Guide

## Critical Fix for Ubuntu 24.04 Users 🔥

### Ubuntu 24.04 AppArmor Restriction Breaks k3d

**Symptom:**
```
k3d-lfh-dev-serverlb container stays in "Created" state
Cluster creation fails with agent nodes timing out
Logs show: ERROR stat /etc/confd/values.yaml: no such file or directory
```

**Root Cause:**
Ubuntu 24.04 introduced `kernel.apparmor_restrict_unprivileged_userns=1` by default, which prevents Docker containers from using unprivileged user namespaces. This breaks k3d's loadbalancer and many other containerized applications.

**The Fix (Recommended):**

Create a persistent sysctl configuration to allow unprivileged user namespaces:

```bash
# Create persistent config
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/20-apparmor-donotrestrict.conf

# Apply immediately (no reboot needed)
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

# Verify it's applied
sysctl kernel.apparmor_restrict_unprivileged_userns  # Should show: = 0
```

After applying this fix, `mise run dev-up` should work perfectly!

**Security Note:** This makes your system equivalent to Ubuntu 22.04 (which didn't have this restriction). The security impact is minimal for development environments.

**Alternative Fix (Temporary):**
Run before each reboot:
```bash
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

---

## Other Known Issues

### Loadbalancer Fails to Start (Legacy Issue)

**Symptom:**
```
k3d-lfh-dev-serverlb container stays in "Created" state
Logs show: ERROR stat /etc/confd/values.yaml: no such file or directory
```

**Cause:**
This is a known k3d issue (https://github.com/k3d-io/k3d/issues/1326) related to:
- Docker security policies (AppArmor/SELinux)
- Docker version incompatibilities
- File system permissions in containerized environments

**Note:** On Ubuntu 24.04, this is usually caused by the AppArmor restriction above. Try that fix first!

**Impact:**
- Cluster API server is accessible
- kubectl works fine
- **Gateway API/Ingress won't work** (no external access point)
- Applications can't be accessed from outside the cluster

**Workarounds:**

#### Option 1: Port Forwarding (Recommended for Development)
```bash
# Forward ports directly from services
kubectl port-forward -n lfh-dev svc/hapihub-svc 7500:7500
kubectl port-forward -n lfh-dev svc/syncd-svc 7800:7800

# Access at:
# http://localhost:7500  (HapiHub)
# http://localhost:7800  (Syncd)
```

#### Option 2: Use NodePort Services
Modify Helm values to use NodePort instead of ClusterIP:
```yaml
# config/k3d-local/values-development.yaml
hapihub:
  service:
    type: NodePort
    nodePort: 30750
```

#### Option 3: Use Kind or Minikube Instead
If you need full ingress/loadbalancer functionality locally:
```bash
# Kind (Kubernetes in Docker)
kind create cluster --config kind-config.yaml

# Minikube
minikube start
minikube tunnel  # Enables LoadBalancer services
```

#### Option 4: Try Older k3d Version
Some users report success with k3d v5.4.x or v5.6.x:
```bash
# In .tool-versions
k3d 5.6.0
```

## Current Configuration

The `k3d-dev.sh` script is configured to:
- Use alternative ports (8080/8443) to avoid conflicts with production k8s
- Create cluster with loadbalancer enabled
- Auto-switch kubectl context

**If loadbalancer fails**, use port-forwarding as shown in Option 1 above.

## Verification

Check if loadbalancer is running:
```bash
docker ps --filter "name=k3d-lfh-dev-serverlb"
```

Expected output for working loadbalancer:
```
NAME                   STATUS    PORTS
k3d-lfh-dev-serverlb   Up        0.0.0.0:8080->80/tcp, 0.0.0.0:8443->443/tcp
```

If status shows "Created" instead of "Up", loadbalancer has failed to start.
