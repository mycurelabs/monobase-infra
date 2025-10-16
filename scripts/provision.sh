#!/usr/bin/env bash
# Cluster Provisioning Script: Idempotent Infrastructure Provisioning
#
# This script provisions Kubernetes clusters using Terraform/OpenTofu.
# It is fully idempotent - safe to run multiple times on the same cluster.
#
# Usage:
#   ./scripts/provision.sh --cluster myclient-prod
#   ./scripts/provision.sh --cluster myclient-prod --dry-run
#   ./scripts/provision.sh --cluster myclient-prod --auto-approve
#   ./scripts/provision.sh --help

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
CLUSTER_NAME=""
DRY_RUN=false
AUTO_APPROVE=false
MERGE_KUBECONFIG=false
TERRAFORM_CMD="terraform"

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
Cluster Provisioning Script: Idempotent Infrastructure Provisioning

USAGE:
    $0 --cluster CLUSTER_NAME [OPTIONS]

REQUIRED:
    --cluster NAME          Cluster name (must match directory in tofu/clusters/)

OPTIONS:
    --dry-run               Show what would be done without making changes
    --auto-approve          Skip confirmation prompts (use with caution)
    --merge-kubeconfig      Merge kubeconfig into ~/.kube/config and switch context
    --help                  Show this help message

EXAMPLES:
    # Provision cluster (interactive, separate kubeconfig)
    $0 --cluster mycure-doks-main

    # Provision and auto-merge kubeconfig
    $0 --cluster k3d-local --merge-kubeconfig

    # Dry run (preview changes)
    $0 --cluster mycure-doks-main --dry-run

    # Auto-approve with kubeconfig merge
    $0 --cluster mycure-doks-main --auto-approve --merge-kubeconfig

IDEMPOTENCY:
    This script is fully idempotent and safe to run multiple times:
    - First run: Creates cluster infrastructure
    - Subsequent runs: Updates only what changed (or does nothing)
    - Uses Terraform state to track existing resources
    - Kubeconfig merge: Only merges if context doesn't exist, otherwise just switches

WORKFLOW:
    1. Validate prerequisites (terraform/tofu, kubectl)
    2. Check cluster directory exists
    3. Run terraform init (idempotent)
    4. Run terraform plan (shows changes)
    5. Run terraform apply (with confirmation unless --auto-approve)
    6. Extract kubeconfig → ~/.kube/{cluster-name}
    7. (Optional) Merge kubeconfig into ~/.kube/config (--merge-kubeconfig)
    8. Test cluster connectivity
    9. Display access information

PREREQUISITES:
    - Cluster config directory exists: tofu/clusters/{cluster-name}
    - terraform or tofu installed
    - kubectl installed
    - Cloud provider credentials configured (DO_TOKEN, AWS, etc.)

NEXT STEPS:
    After provisioning, bootstrap applications with:
    ./scripts/bootstrap.sh --client myclient --env production

EOF
    exit 0
}

# Parse command line arguments
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
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --merge-kubeconfig)
            MERGE_KUBECONFIG=true
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
if [[ -z "$CLUSTER_NAME" ]]; then
    print_error "Missing required argument: --cluster"
    echo "Use --help for usage information"
    exit 1
fi

print_step "Provisioning Configuration"
print_info "Cluster: $CLUSTER_NAME"
print_info "Dry run: $DRY_RUN"
print_info "Auto approve: $AUTO_APPROVE"
print_info "Merge kubeconfig: $MERGE_KUBECONFIG"

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

# Check terraform/tofu
if command -v tofu &> /dev/null; then
    TERRAFORM_CMD="tofu"
    print_success "OpenTofu found: $(tofu version | head -n1)"
elif command -v terraform &> /dev/null; then
    TERRAFORM_CMD="terraform"
    print_success "Terraform found: $(terraform version | head -n1)"
else
    print_error "Neither terraform nor tofu found in PATH"
    exit 1
fi

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found in PATH"
    exit 1
fi
print_success "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

# Check cluster directory
CLUSTER_DIR="${REPO_ROOT}/tofu/clusters/${CLUSTER_NAME}"
if [[ ! -d "$CLUSTER_DIR" ]]; then
    print_error "Cluster directory not found: $CLUSTER_DIR"
    echo ""
    print_info "Create cluster configuration first with:"
    echo "  ./scripts/new-cluster-config.sh $CLUSTER_NAME"
    exit 1
fi
print_success "Cluster directory exists: $CLUSTER_DIR"

# Check required files
if [[ ! -f "$CLUSTER_DIR/main.tf" ]]; then
    print_error "main.tf not found in $CLUSTER_DIR"
    exit 1
fi

if [[ ! -f "$CLUSTER_DIR/variables.tf" ]]; then
    print_error "variables.tf not found in $CLUSTER_DIR"
    exit 1
fi

if [[ ! -f "$CLUSTER_DIR/terraform.tfvars" ]]; then
    print_error "terraform.tfvars not found in $CLUSTER_DIR"
    exit 1
fi

print_success "All required files present"

# Initialize Terraform
print_step "Step 2: Initialize Terraform"
print_info "Running terraform init (idempotent)..."

if [[ "$DRY_RUN" == "false" ]]; then
    cd "$CLUSTER_DIR"
    $TERRAFORM_CMD init
    print_success "Terraform initialized"
else
    print_info "[DRY-RUN] Would run: cd $CLUSTER_DIR && $TERRAFORM_CMD init"
fi

# Run terraform plan
print_step "Step 3: Plan Infrastructure Changes"
print_info "Running terraform plan..."

if [[ "$DRY_RUN" == "false" ]]; then
    cd "$CLUSTER_DIR"

    # Check if this is first run (no state file)
    if [[ ! -f "terraform.tfstate" ]]; then
        print_info "No state file found - this appears to be the first provisioning"
    else
        print_info "State file exists - checking for changes to existing infrastructure"
    fi

    # Save plan to file for review
    $TERRAFORM_CMD plan -out=tfplan

    # Show summary
    echo ""
    print_info "Plan saved to tfplan"
    echo ""
else
    print_info "[DRY-RUN] Would run: cd $CLUSTER_DIR && $TERRAFORM_CMD plan -out=tfplan"
fi

# Apply terraform changes
print_step "Step 4: Apply Infrastructure Changes"

if [[ "$DRY_RUN" == "false" ]]; then
    cd "$CLUSTER_DIR"

    if [[ "$AUTO_APPROVE" == "true" ]]; then
        print_info "Auto-approve enabled, applying changes..."
        $TERRAFORM_CMD apply tfplan
    else
        echo ""
        print_warning "Review the plan above carefully"
        echo ""
        read -p "Do you want to apply these changes? (yes/no): " -r
        echo ""

        if [[ "$REPLY" == "yes" ]]; then
            print_info "Applying changes..."
            $TERRAFORM_CMD apply tfplan
        else
            print_warning "Aborted by user"
            rm -f tfplan
            exit 0
        fi
    fi

    # Clean up plan file
    rm -f tfplan

    print_success "Infrastructure provisioned successfully"
else
    print_info "[DRY-RUN] Would apply terraform changes with confirmation"
fi

# Extract kubeconfig
print_step "Step 5: Extract Kubeconfig"

KUBECONFIG_PATH="$HOME/.kube/${CLUSTER_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
    cd "$CLUSTER_DIR"

    # Check if kubeconfig output exists
    if $TERRAFORM_CMD output kubeconfig &> /dev/null; then
        print_info "Extracting kubeconfig to $KUBECONFIG_PATH..."

        # Create .kube directory if it doesn't exist
        mkdir -p "$HOME/.kube"

        # Extract kubeconfig
        $TERRAFORM_CMD output -raw kubeconfig > "$KUBECONFIG_PATH"

        # Set correct permissions
        chmod 600 "$KUBECONFIG_PATH"

        print_success "Kubeconfig saved to $KUBECONFIG_PATH"
    else
        print_warning "No kubeconfig output found (may not be applicable for this cluster type)"
        KUBECONFIG_PATH=""
    fi
else
    print_info "[DRY-RUN] Would extract kubeconfig to $KUBECONFIG_PATH"
fi

# Merge kubeconfig (optional, idempotent)
if [[ "$MERGE_KUBECONFIG" == "true" ]] && [[ -n "$KUBECONFIG_PATH" ]]; then
    print_step "Step 5.5: Merge Kubeconfig"

    if [[ "$DRY_RUN" == "false" ]]; then
        # Get context name from the new kubeconfig
        CONTEXT_NAME=$(kubectl --kubeconfig="$KUBECONFIG_PATH" config current-context 2>/dev/null || echo "")

        if [[ -z "$CONTEXT_NAME" ]]; then
            print_warning "Could not determine context name from kubeconfig, skipping merge"
        else
            # Check if context already exists in default kubeconfig (idempotency)
            if [[ -f "$HOME/.kube/config" ]] && kubectl config get-contexts "$CONTEXT_NAME" &> /dev/null; then
                print_info "Context '$CONTEXT_NAME' already exists in ~/.kube/config"
                print_info "Switching to existing context (idempotent)"
                kubectl config use-context "$CONTEXT_NAME"
                print_success "Switched to context: $CONTEXT_NAME"
            else
                # Context doesn't exist, perform merge
                print_info "Merging kubeconfig into ~/.kube/config..."

                # Backup existing config
                if [[ -f "$HOME/.kube/config" ]]; then
                    BACKUP_PATH="$HOME/.kube/config.backup.$(date +%s)"
                    cp "$HOME/.kube/config" "$BACKUP_PATH"
                    print_info "Backed up existing config to $BACKUP_PATH"
                fi

                # Create .kube directory if it doesn't exist
                mkdir -p "$HOME/.kube"

                # Merge configs
                if [[ -f "$HOME/.kube/config" ]]; then
                    # Merge with existing config
                    KUBECONFIG="$HOME/.kube/config:$KUBECONFIG_PATH" kubectl config view --flatten > "$HOME/.kube/config.tmp"
                else
                    # No existing config, just copy
                    cp "$KUBECONFIG_PATH" "$HOME/.kube/config.tmp"
                fi

                mv "$HOME/.kube/config.tmp" "$HOME/.kube/config"
                chmod 600 "$HOME/.kube/config"

                # Switch to new context
                kubectl config use-context "$CONTEXT_NAME"

                print_success "Kubeconfig merged into ~/.kube/config"
                print_success "Switched to context: $CONTEXT_NAME"
            fi
        fi
    else
        print_info "[DRY-RUN] Would merge kubeconfig into ~/.kube/config (if context doesn't exist)"
    fi
fi

# Test cluster connectivity
if [[ -n "$KUBECONFIG_PATH" ]]; then
    print_step "Step 6: Verify Cluster Connectivity"

    if [[ "$DRY_RUN" == "false" ]]; then
        print_info "Testing cluster connection..."

        if kubectl --kubeconfig="$KUBECONFIG_PATH" cluster-info &> /dev/null; then
            CLUSTER_VERSION=$(kubectl --kubeconfig="$KUBECONFIG_PATH" version --short 2>/dev/null | grep "Server Version" || echo "Unknown")
            print_success "Cluster is accessible: $CLUSTER_VERSION"

            # Show node status
            echo ""
            print_info "Cluster nodes:"
            kubectl --kubeconfig="$KUBECONFIG_PATH" get nodes -o wide
            echo ""
        else
            print_warning "Cluster not yet accessible (may still be initializing)"
            print_info "Wait a few minutes and test manually with:"
            echo "  export KUBECONFIG=$KUBECONFIG_PATH"
            echo "  kubectl get nodes"
        fi
    else
        print_info "[DRY-RUN] Would test cluster connectivity"
    fi
fi

# Final summary
print_step "Provisioning Complete!"
echo ""
print_success "Cluster '$CLUSTER_NAME' provisioned successfully"
print_info "Cluster directory: $CLUSTER_DIR"

if [[ -n "$KUBECONFIG_PATH" ]]; then
    print_info "Kubeconfig: $KUBECONFIG_PATH"
fi

# Show terraform outputs
if [[ "$DRY_RUN" == "false" ]]; then
    cd "$CLUSTER_DIR"

    echo ""
    print_info "Terraform Outputs:"
    $TERRAFORM_CMD output
fi

echo ""
print_info "Next steps:"
echo ""

if [[ "$MERGE_KUBECONFIG" == "true" ]] && [[ -n "$KUBECONFIG_PATH" ]]; then
    echo "1. Kubeconfig already merged and context switched"
    echo "   kubectl get nodes  # Should work immediately"
    echo ""
    echo "2. Create client configuration:"
    echo "   ./scripts/new-client-config.sh myclient myclient.com"
    echo "   # Then edit config/myclient/values-production.yaml"
    echo ""
    echo "3. Bootstrap applications via GitOps:"
    echo "   ./scripts/bootstrap.sh --client myclient --env production"
else
    echo "1. Set kubeconfig environment variable:"
    if [[ -n "$KUBECONFIG_PATH" ]]; then
        echo "   export KUBECONFIG=$KUBECONFIG_PATH"
        echo ""
        echo "   Or merge into default kubeconfig:"
        echo "   ./scripts/provision.sh --cluster $CLUSTER_NAME --merge-kubeconfig"
    else
        echo "   (Configure kubeconfig manually for this cluster type)"
    fi
    echo ""
    echo "2. Verify cluster access:"
    echo "   kubectl get nodes"
    echo "   kubectl cluster-info"
    echo ""
    echo "3. Create client configuration:"
    echo "   ./scripts/new-client-config.sh myclient myclient.com"
    echo "   # Then edit config/myclient/values-production.yaml"
    echo ""
    echo "4. Bootstrap applications via GitOps:"
    echo "   ./scripts/bootstrap.sh --client myclient --env production"
fi

echo ""
echo "IDEMPOTENCY: You can re-run this script anytime to update the cluster"
echo "             or verify current state. Terraform only changes what's needed."
echo ""
