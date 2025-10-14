#!/usr/bin/env bash
# k3d Local Development Environment Manager
# Creates and manages a local k3d cluster for testing LFH Infrastructure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="lfh-dev"
NAMESPACE="lfh-dev"
AGENTS=2
VALUES_FILE="config/k3d-local/values-development.yaml"

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
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --volume /tmp/k3d-storage:/var/lib/rancher/k3s/storage@all \
    --k3s-arg "--disable=traefik@server:0" \
    --wait

  log_success "Cluster created successfully"
}

wait_for_cluster() {
  log_info "Waiting for cluster to be ready..."

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
  log_info "Deploying applications..."

  if [ ! -f "$VALUES_FILE" ]; then
    log_error "Values file not found: $VALUES_FILE"
    return 1
  fi

  # Create namespace
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - &> /dev/null

  # Install HapiHub (which includes dependencies)
  helm upgrade --install hapihub charts/hapihub \
    -f "$VALUES_FILE" \
    -n "$NAMESPACE" \
    --wait \
    --timeout 5m \
    &> /dev/null

  log_success "Applications deployed"
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
    echo "  http://$host"
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

cmd_up() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  Starting k3d Development Environment${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  check_prerequisites
  create_cluster
  wait_for_cluster
  deploy_gateway_api
  deploy_apps
  configure_hosts

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✓ Development environment ready!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "Access your applications:"
  for host in "${HOSTS_ENTRIES[@]}"; do
    echo "  http://$host"
  done
  echo ""
  echo "Useful commands:"
  echo "  kubectl get pods -n $NAMESPACE --watch"
  echo "  kubectl logs -n $NAMESPACE <pod-name> -f"
  echo "  $0 status"
  echo ""
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
    cmd_up
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
    echo "  up      - Create cluster and deploy applications"
    echo "  down    - Delete cluster and cleanup"
    echo "  reset   - Delete and recreate everything (fresh start)"
    echo "  status  - Show current environment status"
    echo ""
    echo "Examples:"
    echo "  $0 up       # Start local development environment"
    echo "  $0 status   # Check what's running"
    echo "  $0 down     # Stop and cleanup"
    exit 1
    ;;
esac
