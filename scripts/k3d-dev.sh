#!/usr/bin/env bash
# k3d Local Development Environment Manager
# Creates and manages a local k3d cluster for testing Monobase Infrastructure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="monobase-dev"
NAMESPACE="monobase-dev"
AGENTS=2
VALUES_FILE="config/k3d-local/values-development.yaml"
HTTP_PORT=8080   # Use alternative port to avoid conflict with production k8s
HTTPS_PORT=8443  # Use alternative port to avoid conflict with production k8s

# Hosts entries
HOSTS_ENTRIES=(
  "api.local.test"
  "app.local.test"
  "sync.local.test"
)

# Functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

check_prerequisites() {
  log_info "Checking prerequisites..."

  local missing=()

  if ! command -v k3d &> /dev/null; then
    missing+=("k3d")
  fi

  if ! command -v kubectl &> /dev/null; then
    missing+=("kubectl")
  fi

  if ! command -v helm &> /dev/null; then
    missing+=("helm")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing required tools: ${missing[*]}"
    echo ""
    echo "Install instructions:"
    echo "  macOS:   brew install k3d kubectl helm"
    echo "  Linux:   https://k3d.io | https://kubernetes.io/docs/tasks/tools/"
    return 1
  fi

  # Check for Ubuntu 24.04 AppArmor restriction
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]; then
      local userns_restriction=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo "unknown")
      if [ "$userns_restriction" == "1" ]; then
        log_warning "Ubuntu 24.04 detected with AppArmor user namespace restriction"
        echo ""
        echo -e "${YELLOW}k3d loadbalancer will fail without fixing this!${NC}"
        echo ""
        echo "Fix (run once):"
        echo "  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/20-apparmor-donotrestrict.conf"
        echo "  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0"
        echo ""
        echo "See docs/K3D_TROUBLESHOOTING.md for details"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          log_error "Aborted. Apply the fix above and try again."
          return 1
        fi
      fi

      # Check inotify limits (critical for k3d/k3s on Ubuntu 24.04)
      local inotify_instances=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo "0")
      if [ "$inotify_instances" -lt 512 ]; then
        log_warning "Ubuntu 24.04 detected with insufficient inotify limits"
        echo ""
        echo -e "${YELLOW}k3d nodes will fail to register without fixing this!${NC}"
        echo ""
        echo "Current: fs.inotify.max_user_instances = $inotify_instances"
        echo "Required: 512 or higher"
        echo ""
        echo "Fix (run once):"
        echo "  sudo sysctl fs.inotify.max_user_instances=512"
        echo "  echo 'fs.inotify.max_user_instances = 512' | sudo tee /etc/sysctl.d/30-inotify-k3d.conf"
        echo ""
        echo "See docs/K3D_TROUBLESHOOTING.md for details"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          log_error "Aborted. Apply the fix above and try again."
          return 1
        fi
      fi
    fi
  fi

  log_success "All prerequisites installed"
}

cluster_exists() {
  k3d cluster list | grep -q "^$CLUSTER_NAME"
}

create_cluster() {
  log_info "Creating k3d cluster '$CLUSTER_NAME'..."

  if cluster_exists; then
    log_warning "Cluster '$CLUSTER_NAME' already exists"
    return 0
  fi

  k3d cluster create "$CLUSTER_NAME" \
    --agents $AGENTS \
    --port "${HTTP_PORT}:80@loadbalancer" \
    --port "${HTTPS_PORT}:443@loadbalancer" \
    --volume /tmp/k3d-storage:/var/lib/rancher/k3s/storage@all \
    --k3s-arg "--disable=traefik@server:0" \
    --wait

  log_success "Cluster created successfully"
}

wait_for_cluster() {
  log_info "Waiting for cluster to be ready..."

  # Switch kubectl context to k3d cluster
  k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context &> /dev/null

  local retries=30
  local count=0

  while [ $count -lt $retries ]; do
    if kubectl cluster-info &> /dev/null; then
      log_success "Cluster is ready"
      return 0
    fi
    count=$((count + 1))
    sleep 2
  done

  log_error "Cluster failed to become ready"
  return 1
}

deploy_gateway_api() {
  log_info "Installing Gateway API CRDs..."

  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml &> /dev/null

  log_success "Gateway API CRDs installed"
}

deploy_apps() {
  log_info "Deploying applications via bootstrap script..."

  if [ ! -f "$VALUES_FILE" ]; then
    log_error "Values file not found: $VALUES_FILE"
    return 1
  fi

  # Get script directory
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Use bootstrap script to deploy everything
  "$script_dir/bootstrap.sh" \
    --client monobase \
    --env dev \
    --values "$VALUES_FILE" \
    --k3d \
    &> /dev/null

  log_success "Applications deployed via bootstrap"
}

configure_hosts() {
  log_info "Configuring /etc/hosts..."

  local hosts_line="127.0.0.1 ${HOSTS_ENTRIES[*]}"

  # Check if entries already exist
  if grep -q "${HOSTS_ENTRIES[0]}" /etc/hosts 2>/dev/null; then
    log_warning "Hosts entries already exist"
    return 0
  fi

  # Try to add entries
  if [ "$(uname)" = "Darwin" ]; then
    # macOS
    echo "$hosts_line" | sudo tee -a /etc/hosts > /dev/null
  else
    # Linux
    echo "$hosts_line" | sudo tee -a /etc/hosts > /dev/null
  fi

  log_success "Hosts configured"
}

show_status() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  k3d Development Environment Status${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  if ! cluster_exists; then
    log_warning "Cluster is not running"
    echo ""
    echo "Start with: $0 up"
    return 0
  fi

  log_success "Cluster '$CLUSTER_NAME' is running"
  echo ""

  # Show nodes
  echo "Nodes:"
  kubectl get nodes -o wide 2>/dev/null || log_error "Cannot connect to cluster"
  echo ""

  # Show pods
  echo "Pods in namespace '$NAMESPACE':"
  kubectl get pods -n "$NAMESPACE" 2>/dev/null || log_warning "Namespace not found"
  echo ""

  # Show services
  echo "Services:"
  kubectl get svc -n "$NAMESPACE" 2>/dev/null
  echo ""

  # Show access URLs
  echo -e "${GREEN}Access URLs:${NC}"
  for host in "${HOSTS_ENTRIES[@]}"; do
    echo "  http://$host:${HTTP_PORT}"
  done
  echo ""
}

cleanup_hosts() {
  log_info "Cleaning up /etc/hosts entries..."

  if [ "$(uname)" = "Darwin" ]; then
    # macOS
    sudo sed -i.bak "/local.test/d" /etc/hosts 2>/dev/null || true
  else
    # Linux
    sudo sed -i.bak "/local.test/d" /etc/hosts 2>/dev/null || true
  fi

  log_success "Hosts entries removed"
}

delete_cluster() {
  log_info "Deleting k3d cluster..."

  if ! cluster_exists; then
    log_warning "Cluster does not exist"
    return 0
  fi

  k3d cluster delete "$CLUSTER_NAME"

  log_success "Cluster deleted"
}

setup_forgejo() {
  log_info "Installing Forgejo (local Git server)..."

  # Create git namespace
  kubectl create namespace git --dry-run=client -o yaml | kubectl apply -f - &> /dev/null

  # Add Forgejo Helm repo (OCI)
  log_info "Installing Forgejo via Helm..."

  # Install Forgejo with minimal config
  helm upgrade --install forgejo oci://code.forgejo.org/forgejo-helm/forgejo \
    --namespace git \
    --set gitea.admin.username=gitea_admin \
    --set gitea.admin.password=gitea_admin \
    --set gitea.admin.email=admin@local.test \
    --set service.http.type=ClusterIP \
    --set service.http.port=3000 \
    --set persistence.size=1Gi \
    --set resources.requests.cpu=100m \
    --set resources.requests.memory=256Mi \
    --set resources.limits.cpu=500m \
    --set resources.limits.memory=512Mi \
    --wait \
    --timeout=5m &> /dev/null

  log_success "Forgejo installed"

  # Wait for Forgejo to be ready
  log_info "Waiting for Forgejo to be ready..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=forgejo -n git --timeout=120s &> /dev/null

  log_success "Forgejo is ready at http://forgejo-http.git.svc.cluster.local:3000"
}

mirror_to_forgejo() {
  log_info "Mirroring repository to Forgejo..."

  # Get Forgejo pod name
  local forgejo_pod=$(kubectl get pod -n git -l app.kubernetes.io/name=forgejo -o jsonpath='{.items[0].metadata.name}')

  # Create repository via Forgejo API
  log_info "Creating repository in Forgejo..."

  # Port-forward temporarily to create repo
  kubectl port-forward -n git svc/forgejo-http 3000:3000 &> /dev/null &
  local pf_pid=$!
  sleep 3

  # Create repo via API
  curl -X POST "http://localhost:3000/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -u "gitea_admin:gitea_admin" \
    -d '{"name":"monobase-infra","private":false,"auto_init":false}' &> /dev/null || true

  # Kill port-forward
  kill $pf_pid 2>/dev/null || true

  # Add Forgejo as git remote and push
  log_info "Pushing current branch to Forgejo..."

  # Remove existing remote if present
  git remote remove forgejo &> /dev/null || true

  # Add new remote (using kubectl port-forward)
  git remote add forgejo http://gitea_admin:gitea_admin@localhost:3000/gitea_admin/monobase-infra.git

  # Port-forward again for git push
  kubectl port-forward -n git svc/forgejo-http 3000:3000 &> /dev/null &
  local pf_pid=$!
  sleep 2

  # Push current branch
  git push forgejo HEAD:main --force &> /dev/null || log_warning "Failed to push to Forgejo"

  # Kill port-forward
  kill $pf_pid 2>/dev/null || true

  # Remove the remote (we'll use cluster-internal URL for ArgoCD)
  git remote remove forgejo &> /dev/null || true

  log_success "Repository mirrored to Forgejo"
}

setup_gitops_deployment() {
  log_info "Deploying via GitOps (ArgoCD + root-app)..."

  if [ ! -f "$VALUES_FILE" ]; then
    log_error "Values file not found: $VALUES_FILE"
    return 1
  fi

  # Get script directory
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Use bootstrap script to deploy everything via GitOps
  # This will:
  # 1. Install ArgoCD (if not present)
  # 2. Render templates
  # 3. Deploy root-app (App-of-Apps pattern)
  "$script_dir/bootstrap.sh" \
    --client monobase \
    --env dev \
    --values "$VALUES_FILE" \
    --k3d \
    &> /dev/null

  log_success "GitOps deployment complete"
}

# deploy_apps_gitops function removed - now handled by setup_gitops_deployment via bootstrap.sh

show_gitops_status() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  GitOps Environment Info${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  echo "Forgejo Git Server:"
  echo "  Username: gitea_admin"
  echo "  Password: gitea_admin"
  echo "  Access: kubectl port-forward -n git svc/forgejo-http 3000:3000"
  echo "  Then open: http://localhost:3000"
  echo ""

  echo "ArgoCD UI:"
  echo "  Access: kubectl port-forward -n argocd svc/argocd-server 8080:443"
  echo "  Then open: https://localhost:8080"
  echo "  Username: admin"
  echo "  Password: \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
  echo ""

  echo "ArgoCD Applications:"
  kubectl get applications -n argocd 2>/dev/null || echo "  (checking...)"
  echo ""

  echo "Fast Iteration Workflow:"
  echo "  1. Make changes to charts/values"
  echo "  2. git add . && git commit -m 'update'"
  echo "  3. Push to Forgejo:"
  echo "     kubectl port-forward -n git svc/forgejo-http 3000:3000 &"
  echo "     git push http://gitea_admin:gitea_admin@localhost:3000/gitea_admin/monobase-infra.git HEAD:main"
  echo "  4. ArgoCD syncs automatically!"
  echo ""
}

cmd_up() {
  local GITOPS_MODE=false

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --gitops)
        GITOPS_MODE=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  if [ "$GITOPS_MODE" = true ]; then
    echo -e "${BLUE}  Starting k3d GitOps Environment${NC}"
  else
    echo -e "${BLUE}  Starting k3d Development Environment${NC}"
  fi
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  check_prerequisites
  create_cluster
  wait_for_cluster
  deploy_gateway_api

  if [ "$GITOPS_MODE" = true ]; then
    setup_forgejo
    mirror_to_forgejo
    setup_gitops_deployment
  else
    deploy_apps
  fi

  configure_hosts

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  if [ "$GITOPS_MODE" = true ]; then
    echo -e "${GREEN}✓ GitOps environment ready!${NC}"
  else
    echo -e "${GREEN}✓ Development environment ready!${NC}"
  fi
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  if [ "$GITOPS_MODE" = true ]; then
    show_gitops_status
  else
    echo ""
    echo "Access your applications:"
    for host in "${HOSTS_ENTRIES[@]}"; do
      echo "  http://$host:${HTTP_PORT}"
    done
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods -n $NAMESPACE --watch"
    echo "  kubectl logs -n $NAMESPACE <pod-name> -f"
    echo "  $0 status"
    echo ""
  fi
}

cmd_down() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  Stopping k3d Development Environment${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  delete_cluster
  cleanup_hosts

  echo ""
  log_success "Development environment stopped"
  echo ""
}

cmd_reset() {
  log_info "Resetting development environment..."
  echo ""

  cmd_down
  echo ""
  cmd_up
}

cmd_status() {
  show_status
}

# Main
case "${1:-}" in
  up)
    shift  # Remove 'up' from arguments
    cmd_up "$@"  # Pass remaining arguments (e.g., --gitops)
    ;;
  down)
    cmd_down
    ;;
  reset)
    cmd_reset
    ;;
  status)
    cmd_status
    ;;
  *)
    echo "Usage: $0 {up|down|reset|status}"
    echo ""
    echo "Commands:"
    echo "  up [--gitops]  - Create cluster and deploy applications"
    echo "                   --gitops: Use GitOps workflow with Forgejo + ArgoCD"
    echo "  down           - Delete cluster and cleanup"
    echo "  reset          - Delete and recreate everything (fresh start)"
    echo "  status         - Show current environment status"
    echo ""
    echo "Examples:"
    echo "  $0 up           # Start local development environment (Helm mode)"
    echo "  $0 up --gitops  # Start with GitOps workflow (Forgejo + ArgoCD)"
    echo "  $0 status       # Check what's running"
    echo "  $0 down         # Stop and cleanup"
    exit 1
    ;;
esac
