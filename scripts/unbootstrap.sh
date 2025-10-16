#!/bin/bash
#
# unbootstrap.sh - Remove GitOps/ArgoCD installation
#
# Description:
#   Removes ArgoCD and managed Applications (reverse of bootstrap.sh).
#   Provides options for handling deployed resources.
#
# Usage:
#   ./unbootstrap.sh [options]
#
# Options:
#   --mode <cascade|orphan|argocd-only>  Deletion mode (required)
#   --namespace <name>                   ArgoCD namespace (default: argocd)
#   --dry-run                           Show what would be deleted
#   --help                              Show this help message
#
# Modes:
#   cascade       - Delete Applications AND all deployed resources (DESTRUCTIVE)
#   orphan        - Delete Applications but keep resources running
#   argocd-only   - Only uninstall ArgoCD (keep Applications)
#
# Examples:
#   ./unbootstrap.sh --mode cascade
#   ./unbootstrap.sh --mode orphan
#   ./unbootstrap.sh --mode argocd-only --dry-run
#
# ⚠️  WARNING: This script is ATTENDED-ONLY and requires confirmation
#
# What this script does (mode dependent):
#   CASCADE mode:
#     1. Lists all ArgoCD Applications
#     2. Requires typing "DELETE" to confirm
#     3. Backs up Application manifests
#     4. Deletes Applications (cascades to deployed resources)
#     5. Uninstalls ArgoCD
#
#   ORPHAN mode:
#     1. Lists all ArgoCD Applications
#     2. Requires typing "DELETE" to confirm
#     3. Backs up Application manifests
#     4. Removes finalizers from Applications
#     5. Deletes Applications (resources remain)
#     6. Uninstalls ArgoCD
#
#   ARGOCD-ONLY mode:
#     1. Shows ArgoCD deployment
#     2. Requires confirmation
#     3. Uninstalls ArgoCD helm release
#     4. Keeps all Applications and resources
#
# Prerequisites:
#   - kubectl configured for target cluster
#   - ArgoCD installed
#   - Helm (for argocd-only mode)
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

#=============================================================================
# Functions
#=============================================================================

print_header() {
    echo -e "\n${BLUE}===================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================================${NC}\n"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

show_usage() {
    cat << EOF
Usage: $0 --mode <cascade|orphan|argocd-only> [options]

Remove GitOps/ArgoCD installation (reverse of bootstrap.sh)

Modes:
  cascade       Delete Applications AND all deployed resources (DESTRUCTIVE)
  orphan        Delete Applications but keep resources running
  argocd-only   Only uninstall ArgoCD (keep Applications)

Options:
  --mode <mode>          Deletion mode (required)
  --namespace <name>     ArgoCD namespace (default: argocd)
  --dry-run             Show what would be deleted
  --help                Show this help message

Examples:
  $0 --mode cascade
  $0 --mode orphan --namespace custom-argocd
  $0 --mode argocd-only --dry-run

⚠️  WARNING: CASCADE mode will DELETE all deployed infrastructure!
EOF
}

#=============================================================================
# Argument Parsing
#=============================================================================

MODE=""
ARGOCD_NAMESPACE="argocd"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --namespace)
            ARGOCD_NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

#=============================================================================
# Validation
#=============================================================================

# Require mode
if [[ -z "$MODE" ]]; then
    print_error "Mode is required"
    show_usage
    exit 1
fi

# Validate mode
if [[ ! "$MODE" =~ ^(cascade|orphan|argocd-only)$ ]]; then
    print_error "Invalid mode: $MODE (must be cascade, orphan, or argocd-only)"
    show_usage
    exit 1
fi

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found in PATH"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    echo "Please ensure kubectl is configured correctly"
    exit 1
fi

# Check ArgoCD namespace exists
if ! kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
    print_error "ArgoCD namespace not found: $ARGOCD_NAMESPACE"
    echo "ArgoCD may not be installed or namespace name is incorrect"
    exit 1
fi

# Check helm (required for argocd-only mode)
if [[ "$MODE" == "argocd-only" ]]; then
    if ! command -v helm &> /dev/null; then
        print_error "helm not found in PATH (required for argocd-only mode)"
        exit 1
    fi
fi

#=============================================================================
# Mode-specific functions
#=============================================================================

cascade_delete() {
    print_header "CASCADE MODE - Delete Applications AND Resources"
    
    # List all Applications
    print_warning "The following Applications will be DELETED (including all deployed resources):"
    echo ""
    kubectl get applications -n "$ARGOCD_NAMESPACE" -o custom-columns=NAME:.metadata.name,NAMESPACE:.spec.destination.namespace,SYNC:.status.sync.status --no-headers
    
    APP_COUNT=$(kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l)
    echo ""
    echo "Total Applications: $APP_COUNT"
    echo ""
    
    if [[ $APP_COUNT -eq 0 ]]; then
        print_warning "No Applications found - skipping Application deletion"
        return
    fi
    
    # Show resource count estimate
    print_warning "Estimating deployed resources..."
    
    # Get list of managed namespaces
    MANAGED_NAMESPACES=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o jsonpath='{.items[*].spec.destination.namespace}' | tr ' ' '\n' | sort -u)
    
    echo "Managed namespaces:"
    echo "$MANAGED_NAMESPACES" | sed 's/^/  - /'
    echo ""
    
    # Dry run mode
    if [[ "$DRY_RUN" == true ]]; then
        print_success "Dry run complete - no resources were deleted"
        return
    fi
    
    # Confirmation
    print_error "⚠️  WARNING: This will PERMANENTLY DELETE all Applications and their resources!"
    echo ""
    echo "This includes:"
    echo "  • All ArgoCD Applications"
    echo "  • All deployed Kubernetes resources (Deployments, Services, ConfigMaps, etc.)"
    echo "  • Persistent data (if PVCs are managed by Applications)"
    echo "  • Infrastructure components (cert-manager, monitoring, ingress, etc.)"
    echo ""
    print_warning "Type 'DELETE' to confirm cascade deletion:"
    read -p "> " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "DELETE" ]]; then
        print_error "Confirmation failed"
        echo "Aborted."
        exit 1
    fi
    
    # Backup Application manifests
    print_header "Backing Up Application Manifests"
    BACKUP_DIR="$PROJECT_ROOT/backups/argocd-applications"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    
    BACKUP_FILE="$BACKUP_DIR/applications-${TIMESTAMP}.yaml"
    kubectl get applications -n "$ARGOCD_NAMESPACE" -o yaml > "$BACKUP_FILE"
    print_success "Applications backed up to: $BACKUP_FILE"
    
    # Delete Applications (cascade delete via finalizer)
    print_header "Deleting Applications"
    print_warning "Deleting Applications (this will cascade to deployed resources)..."
    
    kubectl delete applications --all -n "$ARGOCD_NAMESPACE" --wait=true
    
    print_success "Applications deleted (resources cascaded)"
}

orphan_delete() {
    print_header "ORPHAN MODE - Delete Applications, Keep Resources"
    
    # List all Applications
    print_warning "The following Applications will be DELETED (resources will be orphaned):"
    echo ""
    kubectl get applications -n "$ARGOCD_NAMESPACE" -o custom-columns=NAME:.metadata.name,NAMESPACE:.spec.destination.namespace,SYNC:.status.sync.status --no-headers
    
    APP_COUNT=$(kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l)
    echo ""
    echo "Total Applications: $APP_COUNT"
    echo ""
    
    if [[ $APP_COUNT -eq 0 ]]; then
        print_warning "No Applications found - skipping Application deletion"
        return
    fi
    
    # Show what will remain
    MANAGED_NAMESPACES=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o jsonpath='{.items[*].spec.destination.namespace}' | tr ' ' '\n' | sort -u)
    
    echo "Resources in these namespaces will remain running:"
    echo "$MANAGED_NAMESPACES" | sed 's/^/  - /'
    echo ""
    
    # Dry run mode
    if [[ "$DRY_RUN" == true ]]; then
        print_success "Dry run complete - no resources were deleted"
        return
    fi
    
    # Confirmation
    print_warning "⚠️  This will delete Applications but KEEP all deployed resources"
    echo ""
    echo "Resources will be orphaned (no longer managed by ArgoCD):"
    echo "  • Applications will be deleted from ArgoCD"
    echo "  • Deployed resources will continue running"
    echo "  • You'll need to manually delete resources later if needed"
    echo ""
    print_warning "Type 'DELETE' to confirm orphan deletion:"
    read -p "> " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "DELETE" ]]; then
        print_error "Confirmation failed"
        echo "Aborted."
        exit 1
    fi
    
    # Backup Application manifests
    print_header "Backing Up Application Manifests"
    BACKUP_DIR="$PROJECT_ROOT/backups/argocd-applications"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/applications-${TIMESTAMP}.yaml"
    kubectl get applications -n "$ARGOCD_NAMESPACE" -o yaml > "$BACKUP_FILE"
    print_success "Applications backed up to: $BACKUP_FILE"
    
    # Remove finalizers to prevent cascade delete
    print_header "Removing Finalizers"
    print_warning "Removing finalizers to orphan resources..."
    
    for app in $(kubectl get applications -n "$ARGOCD_NAMESPACE" -o name); do
        kubectl patch "$app" -n "$ARGOCD_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge
    done
    
    print_success "Finalizers removed"
    
    # Delete Applications (will NOT cascade)
    print_header "Deleting Applications"
    print_warning "Deleting Applications (resources will be orphaned)..."
    
    kubectl delete applications --all -n "$ARGOCD_NAMESPACE" --wait=false
    
    print_success "Applications deleted (resources orphaned)"
}

argocd_only_delete() {
    print_header "ARGOCD-ONLY MODE - Uninstall ArgoCD Only"
    
    # Show ArgoCD deployment
    print_warning "ArgoCD components that will be uninstalled:"
    echo ""
    kubectl get deployments,statefulsets -n "$ARGOCD_NAMESPACE" --no-headers
    echo ""
    
    # Check for existing Applications
    APP_COUNT=$(kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ $APP_COUNT -gt 0 ]]; then
        print_warning "Found $APP_COUNT Applications that will remain (not managed after ArgoCD removal)"
        kubectl get applications -n "$ARGOCD_NAMESPACE" -o custom-columns=NAME:.metadata.name --no-headers | sed 's/^/  - /'
        echo ""
    fi
    
    # Dry run mode
    if [[ "$DRY_RUN" == true ]]; then
        print_success "Dry run complete - ArgoCD would be uninstalled"
        return
    fi
    
    # Confirmation
    print_warning "This will uninstall ArgoCD but keep all Applications and resources"
    echo ""
    read -p "Continue? (yes/no): " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
    
    # Uninstall ArgoCD
    print_header "Uninstalling ArgoCD"
    
    # Check if installed via helm
    if helm list -n "$ARGOCD_NAMESPACE" | grep -q argocd; then
        print_warning "Uninstalling ArgoCD helm release..."
        helm uninstall argocd -n "$ARGOCD_NAMESPACE"
        print_success "ArgoCD helm release uninstalled"
    else
        print_warning "ArgoCD not found as helm release, using kubectl delete..."
        kubectl delete -n "$ARGOCD_NAMESPACE" all --all
    fi
    
    # Optionally delete namespace
    echo ""
    read -p "Delete ArgoCD namespace '$ARGOCD_NAMESPACE'? (yes/no): " DELETE_NS
    if [[ "$DELETE_NS" == "yes" ]]; then
        kubectl delete namespace "$ARGOCD_NAMESPACE"
        print_success "Namespace deleted"
    fi
}

#=============================================================================
# Main Execution
#=============================================================================

print_header "ARGOCD UNBOOTSTRAP"

echo "Mode: $MODE"
echo "ArgoCD namespace: $ARGOCD_NAMESPACE"
echo "Dry run: $DRY_RUN"
echo ""

# Execute based on mode
case $MODE in
    cascade)
        cascade_delete
        ;;
    orphan)
        orphan_delete
        ;;
    argocd-only)
        argocd_only_delete
        ;;
esac

# Uninstall ArgoCD (for cascade and orphan modes)
if [[ "$MODE" != "argocd-only" ]]; then
    print_header "Uninstalling ArgoCD"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "Dry run - ArgoCD would be uninstalled"
    else
        # Check if installed via helm
        if helm list -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -q argocd; then
            print_warning "Uninstalling ArgoCD helm release..."
            helm uninstall argocd -n "$ARGOCD_NAMESPACE"
            print_success "ArgoCD helm release uninstalled"
        else
            print_warning "ArgoCD not found as helm release, deleting namespace..."
        fi
        
        # Delete namespace
        kubectl delete namespace "$ARGOCD_NAMESPACE" --wait=true
        print_success "ArgoCD namespace deleted"
    fi
fi

# Final summary
if [[ "$DRY_RUN" == false ]]; then
    print_header "UNBOOTSTRAP COMPLETE"
    echo "Mode: $MODE"
    echo "Status: SUCCESS"
    echo ""
    print_success "GitOps/ArgoCD unbootstrap completed successfully"
fi
