#!/bin/bash
#
# teardown.sh - Destroy Kubernetes cluster infrastructure
#
# Description:
#   Destroys cluster infrastructure provisioned by provision.sh.
#   This is a DESTRUCTIVE operation that removes all cloud resources.
#
# Usage:
#   ./teardown.sh --cluster <cluster-name> [options]
#
# Options:
#   --cluster <name>        Cluster directory name (required)
#   --dry-run              Show destroy plan without executing
#   --keep-kubeconfig      Don't remove kubeconfig files
#   --help                 Show this help message
#
# Examples:
#   ./teardown.sh --cluster myclient-prod
#   ./teardown.sh --cluster myclient-staging --dry-run
#   ./teardown.sh --cluster myclient-dev --keep-kubeconfig
#
# ⚠️  WARNING: This script is ATTENDED-ONLY and requires confirmation
#
# What this script does:
#   1. Shows terraform destroy plan
#   2. Requires typing exact cluster name to confirm
#   3. Backs up terraform.tfstate before destruction
#   4. Destroys all cluster infrastructure
#   5. Removes kubeconfig files (unless --keep-kubeconfig)
#
# Prerequisites:
#   - terraform or tofu installed
#   - Valid cluster directory in clusters/
#   - AWS/Azure/GCP/DO credentials configured
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
Usage: $0 --cluster <cluster-name> [options]

Destroy Kubernetes cluster infrastructure (reverse of provision.sh)

Options:
  --cluster <name>        Cluster directory name (required)
  --dry-run              Show destroy plan without executing
  --keep-kubeconfig      Don't remove kubeconfig files
  --help                 Show this help message

Examples:
  $0 --cluster myclient-prod
  $0 --cluster myclient-staging --dry-run
  $0 --cluster myclient-dev --keep-kubeconfig

⚠️  WARNING: This is a DESTRUCTIVE operation requiring confirmation
EOF
}

#=============================================================================
# Argument Parsing
#=============================================================================

CLUSTER_NAME=""
DRY_RUN=false
KEEP_KUBECONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-kubeconfig)
            KEEP_KUBECONFIG=true
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

# Require cluster name
if [[ -z "$CLUSTER_NAME" ]]; then
    print_error "Cluster name is required"
    show_usage
    exit 1
fi

# Check terraform/tofu
if command -v tofu &> /dev/null; then
    TF_CMD="tofu"
elif command -v terraform &> /dev/null; then
    TF_CMD="terraform"
else
    print_error "Neither terraform nor tofu found in PATH"
    exit 1
fi

# Check cluster directory exists
CLUSTER_DIR="$PROJECT_ROOT/clusters/$CLUSTER_NAME"
if [[ ! -d "$CLUSTER_DIR" ]]; then
    print_error "Cluster directory not found: $CLUSTER_DIR"
    exit 1
fi

# Check terraform state exists
if [[ ! -f "$CLUSTER_DIR/terraform.tfstate" ]]; then
    print_warning "No terraform.tfstate found in $CLUSTER_DIR"
    echo "This cluster may already be destroyed or was never provisioned."
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [[ "$CONTINUE" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

#=============================================================================
# Main Execution
#=============================================================================

print_header "CLUSTER TEARDOWN - $CLUSTER_NAME"

echo "Cluster directory: $CLUSTER_DIR"
echo "Terraform command: $TF_CMD"
echo "Dry run: $DRY_RUN"
echo "Keep kubeconfig: $KEEP_KUBECONFIG"
echo ""

cd "$CLUSTER_DIR"

# Step 1: Initialize terraform
print_header "Step 1: Initialize Terraform"
$TF_CMD init

# Step 2: Show destroy plan
print_header "Step 2: Destroy Plan Preview"
print_warning "The following resources will be DESTROYED:"
echo ""
$TF_CMD plan -destroy

# Dry run mode - exit here
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    print_success "Dry run complete - no resources were destroyed"
    exit 0
fi

# Step 3: Confirmation prompt
print_header "Step 3: Confirmation Required"
print_error "⚠️  WARNING: This will PERMANENTLY DESTROY all cluster infrastructure!"
echo ""
echo "This action will:"
echo "  • Delete the Kubernetes cluster"
echo "  • Destroy all cloud resources (VMs, load balancers, storage, networking)"
echo "  • Remove all data and persistent volumes"
echo "  • This operation CANNOT be undone"
echo ""
print_warning "Type the exact cluster name to confirm: $CLUSTER_NAME"
read -p "> " CONFIRMATION

if [[ "$CONFIRMATION" != "$CLUSTER_NAME" ]]; then
    print_error "Confirmation failed - cluster name did not match"
    echo "Aborted."
    exit 1
fi

# Step 4: Final confirmation
echo ""
print_warning "Final confirmation - are you absolutely sure? (type 'DESTROY' to proceed)"
read -p "> " FINAL_CONFIRMATION

if [[ "$FINAL_CONFIRMATION" != "DESTROY" ]]; then
    print_error "Final confirmation failed"
    echo "Aborted."
    exit 1
fi

# Step 5: Backup terraform state
print_header "Step 4: Backup Terraform State"
BACKUP_DIR="$PROJECT_ROOT/backups/terraform-state"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${CLUSTER_NAME}-${TIMESTAMP}.tfstate"

if [[ -f "terraform.tfstate" ]]; then
    cp terraform.tfstate "$BACKUP_FILE"
    print_success "State backed up to: $BACKUP_FILE"
else
    print_warning "No state file to backup"
fi

# Step 6: Destroy infrastructure
print_header "Step 5: Destroying Infrastructure"
print_warning "Destroying cluster infrastructure..."
echo ""

if $TF_CMD destroy -auto-approve; then
    print_success "Cluster infrastructure destroyed successfully"
else
    print_error "Terraform destroy failed"
    echo ""
    echo "State backup available at: $BACKUP_FILE"
    exit 1
fi

# Step 7: Clean up kubeconfig
if [[ "$KEEP_KUBECONFIG" == false ]]; then
    print_header "Step 6: Cleaning Up Kubeconfig"
    
    KUBECONFIG_FILE="$HOME/.kube/$CLUSTER_NAME"
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        rm -f "$KUBECONFIG_FILE"
        print_success "Removed kubeconfig: $KUBECONFIG_FILE"
    else
        print_warning "Kubeconfig not found: $KUBECONFIG_FILE"
    fi
    
    # Offer to remove context from merged config
    if grep -q "$CLUSTER_NAME" "$HOME/.kube/config" 2>/dev/null; then
        echo ""
        print_warning "Cluster context still exists in ~/.kube/config"
        read -p "Remove context from ~/.kube/config? (yes/no): " REMOVE_CONTEXT
        
        if [[ "$REMOVE_CONTEXT" == "yes" ]]; then
            kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
            kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
            kubectl config unset "users.$CLUSTER_NAME" 2>/dev/null || true
            print_success "Removed context from ~/.kube/config"
        fi
    fi
else
    print_warning "Keeping kubeconfig files (--keep-kubeconfig specified)"
fi

# Final summary
print_header "TEARDOWN COMPLETE"
echo "Cluster: $CLUSTER_NAME"
echo "Status: DESTROYED"
echo ""
echo "State backup: $BACKUP_FILE"
echo ""
print_success "Cluster teardown completed successfully"
