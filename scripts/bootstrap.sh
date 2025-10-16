#!/usr/bin/env bash
# Bootstrap Script: Empty Cluster → Running GitOps Applications
#
# This script automates the complete deployment from an empty Kubernetes cluster
# to a fully running application stack via GitOps.
#
# Usage:
#   ./scripts/bootstrap.sh --client myclient --env production
#   ./scripts/bootstrap.sh --client myclient --env dev --k3d
#   ./scripts/bootstrap.sh --help

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
CLIENT=""
ENV=""
VALUES_FILE=""
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
WAIT_FOR_SYNC=false
SKIP_ARGOCD=false
DRY_RUN=false

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo ""
    echo -e "${BLUE}==>${NC} $1"
}

# Function to show usage
usage() {
    cat <<EOF
Bootstrap Script: Deploy Full Stack via GitOps

USAGE:
    $0 --client CLIENT --env ENVIRONMENT [OPTIONS]

REQUIRED:
    --client NAME           Client name (e.g., myclient)
    --env ENVIRONMENT       Environment (production, staging, dev)

OPTIONS:
    --values FILE           Path to values file (auto-detected if not provided)
    --kubeconfig FILE       Path to kubeconfig (default: \$KUBECONFIG or ~/.kube/config)
    --wait                  Wait for all applications to sync (default: false)
    --skip-argocd           Skip ArgoCD installation (assume already installed)
    --dry-run               Print commands without executing
    --help                  Show this help message

EXAMPLES:
    # Bootstrap production cluster
    $0 --client myclient --env production

    # Bootstrap staging with explicit values file
    $0 --client myclient --env staging --values config/myclient/values-staging.yaml

    # Bootstrap and wait for all apps to sync
    $0 --client myclient --env production --wait

WORKFLOW:
    1. Validate inputs (client config, kubeconfig, cluster connectivity)
    2. Install ArgoCD (if not present)
    3. Wait for ArgoCD to be ready
    4. Render Helm templates with client configuration
    5. Deploy root-app (App-of-Apps pattern)
    6. Output ArgoCD access information
    7. (Optional) Wait for all applications to sync

RESULT:
    Empty cluster → Fully deployed application stack via GitOps

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --client)
            CLIENT="$2"
            shift 2
            ;;
        --env)
            ENV="$2"
            shift 2
            ;;
        --values)
            VALUES_FILE="$2"
            shift 2
            ;;
        --kubeconfig)
            KUBECONFIG="$2"
            shift 2
            ;;
        --wait)
            WAIT_FOR_SYNC=true
            shift
            ;;
        --skip-argocd)
            SKIP_ARGOCD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$CLIENT" ]]; then
    print_error "Missing required argument: --client"
    echo "Use --help for usage information"
    exit 1
fi

if [[ -z "$ENV" ]]; then
    print_error "Missing required argument: --env"
    echo "Use --help for usage information"
    exit 1
fi

# Auto-detect values file if not provided
if [[ -z "$VALUES_FILE" ]]; then
    VALUES_FILE="${REPO_ROOT}/config/${CLIENT}/values-${ENV}.yaml"
fi

print_step "Bootstrap Configuration"
print_info "Client: $CLIENT"
print_info "Environment: $ENV"
print_info "Values file: $VALUES_FILE"
print_info "Kubeconfig: $KUBECONFIG"
print_info "Wait for sync: $WAIT_FOR_SYNC"
print_info "Dry run: $DRY_RUN"

# Function to execute command with dry-run support
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# Validate prerequisites
print_step "Step 1: Validate Prerequisites"

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
    print_error "Values file not found: $VALUES_FILE"
    exit 1
fi
print_success "Values file exists: $VALUES_FILE"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found in PATH"
    exit 1
fi
print_success "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

# Check helm
if ! command -v helm &> /dev/null; then
    print_error "helm not found in PATH"
    exit 1
fi
print_success "helm found: $(helm version --short)"

# Check cluster connectivity
if [[ "$DRY_RUN" == "false" ]]; then
    if ! kubectl --kubeconfig="$KUBECONFIG" cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Kubeconfig: $KUBECONFIG"
        exit 1
    fi
    CLUSTER_VERSION=$(kubectl --kubeconfig="$KUBECONFIG" version --short 2>/dev/null | grep "Server Version" || echo "Unknown")
    print_success "Connected to cluster: $CLUSTER_VERSION"
fi

# Install ArgoCD if needed
if [[ "$SKIP_ARGOCD" == "false" ]]; then
    print_step "Step 2: Install ArgoCD"

    # Check if ArgoCD is already installed
    if kubectl --kubeconfig="$KUBECONFIG" get namespace argocd &> /dev/null && \
       kubectl --kubeconfig="$KUBECONFIG" get deployment argocd-server -n argocd &> /dev/null 2>&1; then
        print_info "ArgoCD already installed, skipping installation"
    else
        print_info "Installing ArgoCD via Helm..."

        # Add Helm repo
        execute helm repo add argo https://argoproj.github.io/argo-helm
        execute helm repo update

        # Install or upgrade ArgoCD (idempotent)
        execute helm upgrade --install argocd argo/argo-cd \
            --namespace argocd \
            --create-namespace \
            --values "${REPO_ROOT}/bootstrap/argocd/helm-values.yaml" \
            --wait \
            --timeout 5m

        print_success "ArgoCD installed successfully"
    fi

    # Wait for ArgoCD to be ready
    print_info "Waiting for ArgoCD to be ready..."
    if [[ "$DRY_RUN" == "false" ]]; then
        kubectl --kubeconfig="$KUBECONFIG" wait --for=condition=ready pod \
            -l app.kubernetes.io/name=argocd-server \
            -n argocd \
            --timeout=300s
    fi
    print_success "ArgoCD is ready"
else
    print_step "Step 2: Skip ArgoCD Installation"
    print_info "Assuming ArgoCD is already installed (--skip-argocd)"
fi

# Render templates
print_step "Step 3: Render Helm Templates"
OUTPUT_DIR="${REPO_ROOT}/rendered/${CLIENT}-${ENV}"

print_info "Rendering templates to: $OUTPUT_DIR"
execute "${SCRIPT_DIR}/render-templates.sh" \
    --values "$VALUES_FILE" \
    --output "$OUTPUT_DIR"

print_success "Templates rendered successfully"

# Deploy root-app
print_step "Step 4: Deploy Root Application"
ROOT_APP="${OUTPUT_DIR}/monobase/templates/root-app.yaml"

if [[ ! -f "$ROOT_APP" ]]; then
    print_error "Root app not found: $ROOT_APP"
    exit 1
fi

print_info "Deploying root-app (App-of-Apps)..."
execute kubectl --kubeconfig="$KUBECONFIG" apply -f "$ROOT_APP"
print_success "Root application deployed"

# Output ArgoCD access information
print_step "Step 5: ArgoCD Access Information"

if [[ "$DRY_RUN" == "false" ]] && [[ "$SKIP_ARGOCD" == "false" ]]; then
    # Get admin password
    ADMIN_PASSWORD=$(kubectl --kubeconfig="$KUBECONFIG" -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A")

    echo ""
    print_info "ArgoCD UI Access:"
    echo "  Username: admin"
    echo "  Password: $ADMIN_PASSWORD"
    echo ""
    print_info "Access ArgoCD UI:"
    echo "  kubectl --kubeconfig=$KUBECONFIG port-forward -n argocd svc/argocd-server 8080:443"
    echo "  Open: https://localhost:8080"
    echo ""
fi

# Wait for applications to sync
if [[ "$WAIT_FOR_SYNC" == "true" ]]; then
    print_step "Step 6: Wait for Applications to Sync"

    if [[ "$DRY_RUN" == "false" ]]; then
        print_info "Waiting for all applications to sync (this may take several minutes)..."

        # Wait for root-app to create child apps
        sleep 10

        # Get all application names
        APP_NAMES=$(kubectl --kubeconfig="$KUBECONFIG" get applications -n argocd \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

        if [[ -z "$APP_NAMES" ]]; then
            print_warning "No applications found yet, sync may still be in progress"
        else
            print_info "Found applications: $APP_NAMES"

            # Wait for each application
            for APP in $APP_NAMES; do
                print_info "Waiting for $APP to sync..."
                kubectl --kubeconfig="$KUBECONFIG" wait --for=condition=Synced \
                    application "$APP" \
                    -n argocd \
                    --timeout=600s || print_warning "$APP sync timeout (may still be syncing)"
            done
        fi

        print_success "All applications synced (or timed out)"
    else
        print_info "[DRY-RUN] Would wait for applications to sync"
    fi
fi

# Final summary
print_step "Bootstrap Complete!"
echo ""
print_success "Cluster bootstrapped successfully"
print_info "Client: $CLIENT"
print_info "Environment: $ENV"
print_info "Root app: $ROOT_APP"
echo ""
print_info "Next steps:"
echo "  1. Monitor deployment in ArgoCD UI"
echo "  2. Check application health: kubectl get applications -n argocd"
echo "  3. View pod status: kubectl get pods -n ${CLIENT}-${ENV}"
echo ""
