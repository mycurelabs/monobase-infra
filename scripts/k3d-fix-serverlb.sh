#!/usr/bin/env bash
# k3d Serverlb Fix Script
# Workaround for k3d issue #1326: serverlb missing /etc/confd/values.yaml
# This script injects the required configuration file into the serverlb container

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-monobase-dev}"
SERVERLB_CONTAINER="k3d-${CLUSTER_NAME}-serverlb"
SERVER_NODE="k3d-${CLUSTER_NAME}-server-0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# Check if serverlb container exists
if ! docker ps -a --filter "name=${SERVERLB_CONTAINER}" --format '{{.Names}}' | grep -q "${SERVERLB_CONTAINER}"; then
  log_error "Serverlb container '${SERVERLB_CONTAINER}' not found"
  exit 1
fi

log_info "Applying k3d serverlb fix for cluster '${CLUSTER_NAME}'..."

# Stop the serverlb container if running
if docker ps --filter "name=${SERVERLB_CONTAINER}" --format '{{.Names}}' | grep -q "${SERVERLB_CONTAINER}"; then
  log_info "Stopping serverlb container..."
  docker stop "${SERVERLB_CONTAINER}" > /dev/null
fi

# Create temporary values.yaml file
TEMP_VALUES=$(mktemp)
cat > "${TEMP_VALUES}" << EOF
ports:
  6443.tcp:
    - ${SERVER_NODE}
  80.tcp:
    - ${SERVER_NODE}
  443.tcp:
    - ${SERVER_NODE}
settings:
  workerConnections: 1024
  defaultProxyTimeout: 600
EOF

log_info "Injecting values.yaml into serverlb container..."
docker cp "${TEMP_VALUES}" "${SERVERLB_CONTAINER}:/etc/confd/values.yaml"
rm -f "${TEMP_VALUES}"

log_info "Starting serverlb container..."
docker start "${SERVERLB_CONTAINER}" > /dev/null

# Wait for serverlb to be ready
log_info "Waiting for serverlb to start..."
sleep 3

# Check if it's running
if docker ps --filter "name=${SERVERLB_CONTAINER}" --filter "status=running" --format '{{.Names}}' | grep -q "${SERVERLB_CONTAINER}"; then
  log_success "Serverlb is running!"

  # Show port mappings
  echo ""
  echo "Port mappings:"
  docker port "${SERVERLB_CONTAINER}"

  # Check for errors in logs
  if docker logs "${SERVERLB_CONTAINER}" 2>&1 | tail -5 | grep -qi "error"; then
    echo ""
    log_error "Serverlb has errors (may be non-fatal):"
    docker logs "${SERVERLB_CONTAINER}" 2>&1 | grep -i "error" | tail -3
  fi
else
  log_error "Serverlb failed to start"
  echo ""
  echo "Recent logs:"
  docker logs "${SERVERLB_CONTAINER}" 2>&1 | tail -10
  exit 1
fi

log_success "k3d serverlb fix applied successfully!"
