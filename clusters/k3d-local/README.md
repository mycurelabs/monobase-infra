# k3d Local Development Cluster

This directory contains the Terraform configuration for a local k3d cluster used for development and testing.

## Prerequisites

### Required Tools

```bash
# macOS
brew install k3d kubectl

# Linux
# See: https://k3d.io/#installation
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

### Platform-Specific Requirements

#### Ubuntu 24.04

Ubuntu 24.04 requires two system configuration changes:

```bash
# 1. Disable AppArmor user namespace restriction (for k3d loadbalancer)
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/20-apparmor-donotrestrict.conf
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

# 2. Increase inotify limits (for k3s file watching)
sudo sysctl fs.inotify.max_user_instances=512
echo 'fs.inotify.max_user_instances = 512' | sudo tee /etc/sysctl.d/30-inotify-k3d.conf
```

See [Troubleshooting](#troubleshooting) for details.

## Usage

### Provision Cluster

```bash
# From repository root
./scripts/provision.sh --cluster k3d-local
```

This will:
1. Create k3d cluster with 1 server and 2 agent nodes
2. Install Gateway API CRDs
3. Configure kubectl context
4. Save kubeconfig to `~/.kube/k3d-local`

### Bootstrap Applications

After provisioning, deploy applications via GitOps:

```bash
./scripts/bootstrap.sh --client monobase --env dev
```

### Access Services

Services are exposed on alternative ports to avoid conflicts:

- HTTP: `http://localhost:8080`
- HTTPS: `https://localhost:8443`

### Optional: Configure Local Domains

For friendly local domains (*.local.test):

```bash
echo "127.0.0.1 api.local.test app.local.test sync.local.test" | sudo tee -a /etc/hosts
```

Then access via:
- `http://api.local.test:8080`
- `http://app.local.test:8080`

### Destroy Cluster

```bash
k3d cluster delete monobase-dev
```

## Configuration

Edit `terraform.tfvars` to customize:

```hcl
cluster_name         = "monobase-dev"
k3s_version          = "v1.28.3-k3s1"
servers              = 1
agents               = 2
http_port            = 8080   # Alternative to 80
https_port           = 8443   # Alternative to 443
disable_traefik      = true   # Use Envoy Gateway instead
install_gateway_api  = true
```

## Troubleshooting

### LoadBalancer Fails to Start (Ubuntu 24.04)

**Symptom:** k3d loadbalancer container fails with permission errors

**Cause:** Ubuntu 24.04 restricts unprivileged user namespaces by default

**Fix:**
```bash
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

### k3s Nodes Not Registering (Ubuntu 24.04)

**Symptom:** k3d cluster creates but nodes show NotReady or fail to join

**Cause:** Insufficient inotify limits for k3s file watching

**Fix:**
```bash
sudo sysctl fs.inotify.max_user_instances=512
```

### Port Already in Use

**Symptom:** Terraform fails with "port already allocated"

**Cause:** Port 8080 or 8443 already in use

**Fix:** Change ports in `terraform.tfvars`:
```hcl
http_port  = 8090
https_port = 8453
```

## Architecture

```
┌─────────────────────────────────────┐
│  Host (localhost)                   │
│  ┌───────────────────────────────┐  │
│  │  k3d Cluster (monobase-dev)   │  │
│  │  ┌─────────┐  ┌─────────────┐ │  │
│  │  │ Server  │  │   Agents    │ │  │
│  │  │  Node   │  │   (x2)      │ │  │
│  │  └─────────┘  └─────────────┘ │  │
│  │         ▲                      │  │
│  │         │                      │  │
│  │  ┌──────┴────────┐             │  │
│  │  │ LoadBalancer  │             │  │
│  │  └───────────────┘             │  │
│  └──────────┬────────────────────┘  │
│             │                        │
│  8080:80 ───┤                        │
│  8443:443───┘                        │
└─────────────────────────────────────┘
```

## Files

- `main.tf` - Cluster configuration using local-k3d module
- `variables.tf` - Input variables
- `terraform.tfvars` - Default values
- `outputs.tf` - Cluster information and next steps
- `README.md` - This file
