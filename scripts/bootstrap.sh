#!/usr/bin/env bash
# Bootstrap Script: Empty Cluster → GitOps Auto-Discovery
#
# This script automates the complete GitOps setup from an empty Kubernetes cluster.
# After bootstrap, ArgoCD automatically discovers and deploys all client/env configurations
# from the deployments/ directory.
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
AUTO_APPROVE=false
TARGET_CONTEXT=""

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

# Security functions for context selection and confirmation
select_kubectl_context() {
    print_step "Interactive Context Selection"
    
    # Get current context
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
    
    if [[ -z "$CURRENT_CONTEXT" ]]; then
        print_error "No kubectl context is currently set"
        exit 1
    fi
    
    # Get all contexts
    echo ""
    print_info "Available kubectl contexts:"
    kubectl config get-contexts
    
    echo ""
    print_info "Current context: ${GREEN}${CURRENT_CONTEXT}${NC}"
    
    # Show cluster details
    CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${CURRENT_CONTEXT}')].context.cluster}")')].cluster.server}" 2>/dev/null || echo "unknown")
    echo "Cluster server: $CLUSTER_SERVER"
    
    echo ""
    print_warning "Select a context:"
    echo "  1. Use current context: ${CURRENT_CONTEXT}"
    echo "  2. Switch to different context"
    echo "  3. Cancel bootstrap"
    
    read -p "Choice (1-3): " CHOICE
    
    case $CHOICE in
        1)
            TARGET_CONTEXT="$CURRENT_CONTEXT"
            ;;
        2)
            echo ""
            print_info "Enter context name to switch to:"
            read -p "> " NEW_CONTEXT
            
            if kubectl config use-context "$NEW_CONTEXT" &>/dev/null; then
                TARGET_CONTEXT="$NEW_CONTEXT"
                print_success "Switched to context: $TARGET_CONTEXT"
            else
                print_error "Invalid context: $NEW_CONTEXT"
                exit 1
            fi
            ;;
        3)
            print_info "Bootstrap cancelled"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

confirm_cluster_target() {
    print_step "Confirm Cluster Target"
    
    # Get cluster details
    CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${TARGET_CONTEXT}')].context.cluster}")')].cluster.server}" 2>/dev/null || echo "unknown")
    NAMESPACE=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${TARGET_CONTEXT}')].context.namespace}" 2>/dev/null || echo "default")
    
    echo ""
    print_warning "⚠️  You are about to bootstrap this cluster:"
    echo "  Context: ${TARGET_CONTEXT}"
    echo "  Cluster: ${CLUSTER_SERVER}"
    echo "  Namespace: ${NAMESPACE}"
    
    # Try to get cluster info
    if K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | cut -d: -f2 | tr -d ' '); then
        echo "  Kubernetes: ${K8S_VERSION}"
    fi
    
    if NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l); then
        echo "  Nodes: ${NODE_COUNT}"
    fi
    
    echo ""
    print_error "⚠️  WARNING: This will install ArgoCD and enable GitOps on this cluster!"
    echo ""
    print_warning "Type the exact context name '${TARGET_CONTEXT}' to confirm:"
    read -p "> " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "$TARGET_CONTEXT" ]]; then
        print_error "Confirmation failed - context name did not match"
        echo "Aborted."
        exit 1
    fi
}

confirm_bootstrap_action() {
    print_step "Confirm Bootstrap Action"
    
    echo ""
    print_warning "You are about to perform the following actions:"
    echo "  • Install ArgoCD in namespace 'argocd'"
    echo "  • Deploy infrastructure root Application"
    echo "  • Deploy ApplicationSet for auto-discovery"
    echo "  • Enable GitOps management for this cluster"
    echo ""
    print_error "⚠️  This will begin managing the cluster via Git!"
    echo ""
    print_warning "Type 'BOOTSTRAP' to proceed:"
    read -p "> " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "BOOTSTRAP" ]]; then
        print_error "Confirmation failed"
        echo "Aborted."
        exit 1
    fi
    
    print_success "Confirmation received - proceeding with bootstrap"
}

# Function to show usage
usage() {
    cat <<EOF
Bootstrap Script: GitOps Auto-Discovery Setup

DESCRIPTION:
    This script performs ONE-TIME setup of ArgoCD with auto-discovery.
    After bootstrap, ArgoCD automatically detects all client/environment configurations
    in deployments/ directory and deploys them via GitOps.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --kubeconfig FILE       Path to kubeconfig (default: \$KUBECONFIG or ~/.kube/config)
    --context NAME          Target kubectl context (still requires confirmation)
    --wait                  Wait for ApplicationSet to be synced (default: false)
    --skip-argocd           Skip ArgoCD installation (assume already installed)
    --yes                   Skip interactive confirmations (use with caution!)
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
    4. Deploy Infrastructure Root Application (cluster-wide GitOps)
    5. Deploy ApplicationSet for per-client auto-discovery
    6. Output ArgoCD access information
    7. (Optional) Wait for ApplicationSet to sync

TRUE GITOPS WORKFLOW (After Bootstrap):
    # Add new client/environment
    mkdir deployments/newclient-prod
    cp deployments/templates/production-base.yaml deployments/newclient-prod/values-production.yaml
    # Edit deployments/newclient-prod/values-production.yaml
    git add deployments/newclient-prod/
    git commit -m "Add newclient-prod"
    git push
    # ✓ ArgoCD auto-detects and deploys!

    # Update existing client
    vim deployments/myclient/values-production.yaml
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
        --context)
            TARGET_CONTEXT="$2"
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
        --yes)
            AUTO_APPROVE=true
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

# Warning for auto-approve mode
if [[ "$AUTO_APPROVE" == "true" ]]; then
    echo ""
    print_error "⚠️  Auto-approve mode enabled (--yes)"
    print_error "⚠️  Skipping interactive confirmations"
    print_error "⚠️  Use with caution in production environments"
    echo ""
    sleep 2
fi

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

# Interactive security guards (unless auto-approved or dry-run)
if [[ "$AUTO_APPROVE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
    # If no context specified via CLI, prompt for selection
    if [[ -z "$TARGET_CONTEXT" ]]; then
        select_kubectl_context
    else
        # Context specified via --context flag, but still needs confirmation
        print_info "Target context specified: $TARGET_CONTEXT"
        # Switch to specified context if not already active
        CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "")
        if [[ "$CURRENT_CTX" != "$TARGET_CONTEXT" ]]; then
            if kubectl config use-context "$TARGET_CONTEXT" &>/dev/null; then
                print_success "Switched to context: $TARGET_CONTEXT"
            else
                print_error "Invalid context: $TARGET_CONTEXT"
                exit 1
            fi
        fi
    fi
    
    # Confirm cluster target
    confirm_cluster_target
    
    # Confirm bootstrap action
    confirm_bootstrap_action
else
    # Auto-approve or dry-run mode - use current context
    TARGET_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ -z "$TARGET_CONTEXT" ]]; then
        print_error "No kubectl context is currently set"
        exit 1
    fi
    if [[ "$DRY_RUN" == "false" ]]; then
        print_warning "Using current context: $TARGET_CONTEXT (auto-approve mode)"
    fi
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

# Deploy Infrastructure Root Application
print_step "Step 3: Deploy Cluster Infrastructure"
INFRASTRUCTURE_ROOT="${REPO_ROOT}/argocd/bootstrap/infrastructure-root.yaml"

if [[ ! -f "$INFRASTRUCTURE_ROOT" ]]; then
    print_error "Infrastructure root not found: $INFRASTRUCTURE_ROOT"
    exit 1
fi

print_info "Deploying cluster-wide infrastructure via GitOps..."
print_info "This will deploy: cert-manager, envoy-gateway, external-secrets, velero, etc."
execute kubectl --kubeconfig="$KUBECONFIG" apply -f "$INFRASTRUCTURE_ROOT"
print_success "Infrastructure root deployed - ArgoCD managing cluster infrastructure!"

# Deploy ApplicationSet for auto-discovery
print_step "Step 4: Deploy ApplicationSet for Per-Client Apps"
APPLICATIONSET="${REPO_ROOT}/argocd/bootstrap/applicationset-auto-discover.yaml"

if [[ ! -f "$APPLICATIONSET" ]]; then
    print_error "ApplicationSet not found: $APPLICATIONSET"
    exit 1
fi

print_info "Deploying ApplicationSet for auto-discovery..."
print_info "This will scan deployments/ directory and create applications for all client/env configs"
execute kubectl --kubeconfig="$KUBECONFIG" apply -f "$APPLICATIONSET"
print_success "ApplicationSet deployed - ArgoCD will now auto-discover all configs in deployments/"

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

# Wait for ApplicationSet to sync
if [[ "$WAIT_FOR_SYNC" == "true" ]]; then
    print_step "Step 6: Wait for ApplicationSet to Sync"

    if [[ "$DRY_RUN" == "false" ]]; then
        print_info "Waiting for ApplicationSet to discover and create applications..."

        # Wait for ApplicationSet to create applications
        sleep 15

        # Get all application names created by ApplicationSet
        APP_NAMES=$(kubectl --kubeconfig="$KUBECONFIG" get applications -n argocd \
            -l managed-by=applicationset \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

        if [[ -z "$APP_NAMES" ]]; then
            print_warning "No applications found yet - check that deployments/ directory has valid configs"
            print_info "ApplicationSet scans: deployments/*/ (excluding deployments/templates and deployments/example-prod and deployments/example-staging)"
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
echo "  - ArgoCD scans deployments/ directory for client/env configurations"
echo "  - Creates applications automatically for each config found"
echo "  - Syncs applications based on Git repository state"
echo ""
print_info "True GitOps workflow:"
echo ""
echo "  # Add new client/environment"
echo "  mkdir deployments/newclient-prod"
echo "  cp deployments/templates/production-base.yaml deployments/newclient-prod/values-production.yaml"
echo "  vim deployments/newclient-prod/values-production.yaml  # Edit domain, namespace, etc."
echo "  git add deployments/newclient-prod/"
echo "  git commit -m 'Add newclient-prod'"
echo "  git push"
echo "  # ✓ ArgoCD auto-detects and deploys!"
echo ""
echo "  # Update existing client"
echo "  vim deployments/yourclient/values-production.yaml"
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
