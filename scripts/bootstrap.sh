#!/usr/bin/env bash
# Bootstrap Script: Empty Cluster → GitOps Auto-Discovery
#
# This script automates the complete GitOps setup from an empty Kubernetes cluster.
# After bootstrap, ArgoCD automatically discovers and deploys all client/env configurations
# from the config/ directory.
#
# Usage:
#   ./scripts/bootstrap.sh
#   ./scripts/bootstrap.sh --skip-argocd
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
Bootstrap Script: GitOps Auto-Discovery Setup

DESCRIPTION:
    This script performs ONE-TIME setup of ArgoCD with auto-discovery.
    After bootstrap, ArgoCD automatically detects all client/environment configurations
    in config/ directory and deploys them via GitOps.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --kubeconfig FILE       Path to kubeconfig (default: \$KUBECONFIG or ~/.kube/config)
    --wait                  Wait for ApplicationSet to be synced (default: false)
    --skip-argocd           Skip ArgoCD installation (assume already installed)
    --dry-run               Print commands without executing
    --help                  Show this help message

EXAMPLES:
    # Bootstrap new cluster (installs ArgoCD + ApplicationSet)
    $0

    # Bootstrap with existing ArgoCD
    $0 --skip-argocd

    # Bootstrap and wait for sync
    $0 --wait

WORKFLOW:
    1. Validate prerequisites (kubectl, helm, cluster connectivity)
    2. Install ArgoCD (if not present)
    3. Wait for ArgoCD to be ready
    4. Deploy ApplicationSet for auto-discovery
    5. Output ArgoCD access information
    6. (Optional) Wait for ApplicationSet to sync

TRUE GITOPS WORKFLOW (After Bootstrap):
    # Add new client/environment
    mkdir config/newclient-prod
    cp config/profiles/production-base.yaml config/newclient-prod/values-production.yaml
    # Edit config/newclient-prod/values-production.yaml
    git add config/newclient-prod/
    git commit -m "Add newclient-prod"
    git push
    # ✓ ArgoCD auto-detects and deploys!

    # Update existing client
    vim config/myclient/values-production.yaml
    git commit -m "Update myclient-prod: increase replicas"
    git push
    # ✓ ArgoCD auto-syncs only myclient-prod

RESULT:
    Empty cluster → ArgoCD with auto-discovery → Git-driven deployments

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

print_step "Bootstrap Configuration"
print_info "Kubeconfig: $KUBECONFIG"
print_info "Wait for sync: $WAIT_FOR_SYNC"
print_info "Skip ArgoCD: $SKIP_ARGOCD"
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
            --values "${REPO_ROOT}/infrastructure/argocd/helm-values.yaml" \
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

# Deploy ApplicationSet for auto-discovery
print_step "Step 3: Deploy ApplicationSet"
APPLICATIONSET="${REPO_ROOT}/argocd/bootstrap/applicationset-auto-discover.yaml"

if [[ ! -f "$APPLICATIONSET" ]]; then
    print_error "ApplicationSet not found: $APPLICATIONSET"
    exit 1
fi

print_info "Deploying ApplicationSet for auto-discovery..."
print_info "This will scan config/ directory and create applications for all client/env configs"
execute kubectl --kubeconfig="$KUBECONFIG" apply -f "$APPLICATIONSET"
print_success "ApplicationSet deployed - ArgoCD will now auto-discover all configs in config/"

# Output ArgoCD access information
print_step "Step 4: ArgoCD Access Information"

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

# Wait for ApplicationSet to sync
if [[ "$WAIT_FOR_SYNC" == "true" ]]; then
    print_step "Step 5: Wait for ApplicationSet to Sync"

    if [[ "$DRY_RUN" == "false" ]]; then
        print_info "Waiting for ApplicationSet to discover and create applications..."

        # Wait for ApplicationSet to create applications
        sleep 15

        # Get all application names created by ApplicationSet
        APP_NAMES=$(kubectl --kubeconfig="$KUBECONFIG" get applications -n argocd \
            -l managed-by=applicationset \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

        if [[ -z "$APP_NAMES" ]]; then
            print_warning "No applications found yet - check that config/ directory has valid configs"
            print_info "ApplicationSet scans: config/*/ (excluding config/profiles and config/example.com)"
        else
            print_success "ApplicationSet discovered applications: $APP_NAMES"

            # Wait for each application to sync
            for APP in $APP_NAMES; do
                print_info "Waiting for $APP to sync..."
                kubectl --kubeconfig="$KUBECONFIG" wait --for=condition=Synced \
                    application "$APP" \
                    -n argocd \
                    --timeout=600s || print_warning "$APP sync timeout (may still be syncing)"
            done

            print_success "All applications synced (or timed out)"
        fi
    else
        print_info "[DRY-RUN] Would wait for ApplicationSet to sync"
    fi
fi

# Final summary
print_step "Bootstrap Complete!"
echo ""
print_success "GitOps auto-discovery enabled!"
echo ""
print_info "What happens now:"
echo "  - ArgoCD scans config/ directory for client/env configurations"
echo "  - Creates applications automatically for each config found"
echo "  - Syncs applications based on Git repository state"
echo ""
print_info "True GitOps workflow:"
echo ""
echo "  # Add new client/environment"
echo "  mkdir config/newclient-prod"
echo "  cp config/profiles/production-base.yaml config/newclient-prod/values-production.yaml"
echo "  vim config/newclient-prod/values-production.yaml  # Edit domain, namespace, etc."
echo "  git add config/newclient-prod/"
echo "  git commit -m 'Add newclient-prod'"
echo "  git push"
echo "  # ✓ ArgoCD auto-detects and deploys!"
echo ""
echo "  # Update existing client"
echo "  vim config/yourclient/values-production.yaml"
echo "  git commit -am 'Update yourclient: increase replicas'"
echo "  git push"
echo "  # ✓ ArgoCD auto-syncs only yourclient"
echo ""
print_info "Monitor deployments:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get applicationsets -n argocd"
echo ""
print_info "View discovered configs:"
echo "  kubectl get applications -n argocd -l managed-by=applicationset"
echo ""
