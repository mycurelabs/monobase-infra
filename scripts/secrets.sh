#!/usr/bin/env bash
# Secrets Management Script
# Manages infrastructure secrets for TLS certificates and other sensitive data
# Supports multiple secret providers: SOPS, AWS, Azure, GCP, Manual

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

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found"
        log_info "Install it with: mise install"
        return 1
    fi
    return 0
}

check_kubeconfig() {
    if [ -z "${KUBECONFIG:-}" ]; then
        log_error "KUBECONFIG not set"
        log_info "Set it with: export KUBECONFIG=/path/to/kubeconfig"
        return 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    log_success "Connected to cluster: $(kubectl config current-context)"
    return 0
}

# ==============================================================================
# Provider Selection
# ==============================================================================

show_provider_menu() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Secrets Management - Provider Selection"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Choose your secrets provider:"
    echo
    echo "  1) SOPS + age (Recommended - Free, Git-encrypted)"
    echo "  2) AWS Secrets Manager (Requires AWS account)"
    echo "  3) Azure Key Vault (Requires Azure subscription)"
    echo "  4) GCP Secret Manager (Requires GCP project)"
    echo "  5) Manual (Plain K8s secrets - Testing only)"
    echo "  6) Exit"
    echo
    read -rp "Enter choice [1-6]: " choice
    echo

    case $choice in
        1) setup_sops ;;
        2) setup_aws ;;
        3) setup_azure ;;
        4) setup_gcp ;;
        5) setup_manual ;;
        6) exit 0 ;;
        *) log_error "Invalid choice"; show_provider_menu ;;
    esac
}

# ==============================================================================
# SOPS + age Setup
# ==============================================================================

setup_sops() {
    log_info "Setting up SOPS + age encryption..."

    # Check required commands
    check_command sops || return 1
    check_command age || return 1
    check_kubeconfig || return 1

    # Check if age key exists
    AGE_KEY_FILE="${REPO_ROOT}/age.agekey"

    if [ -f "$AGE_KEY_FILE" ]; then
        log_warn "Age key already exists at: $AGE_KEY_FILE"
        read -rp "Use existing key? (y/n): " use_existing
        if [[ ! "$use_existing" =~ ^[Yy]$ ]]; then
            log_info "Generating new age keypair..."
            age-keygen -o "$AGE_KEY_FILE"
            log_success "Generated new age keypair"
        fi
    else
        log_info "Generating age keypair..."
        age-keygen -o "$AGE_KEY_FILE"
        log_success "Generated age keypair at: $AGE_KEY_FILE"
    fi

    # Extract public key
    AGE_PUBLIC_KEY=$(grep "# public key:" "$AGE_KEY_FILE" | cut -d: -f2 | tr -d ' ')
    log_info "Age public key: $AGE_PUBLIC_KEY"

    # Update .sops.yaml
    log_info "Updating .sops.yaml with age public key..."
    sed -i "s/AGE_PUBLIC_KEY_PLACEHOLDER/$AGE_PUBLIC_KEY/g" "${REPO_ROOT}/.sops.yaml"
    log_success "Updated .sops.yaml"

    # Collect TLS configuration
    collect_tls_config

    # Create bootstrap secret in cluster
    log_info "Creating sops-age-key secret in cert-manager namespace..."
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic sops-age-key \
        --from-file=age.agekey="$AGE_KEY_FILE" \
        --namespace=cert-manager \
        --dry-run=client -o yaml | kubectl apply -f -
    log_success "Created sops-age-key secret"

    # Encrypt Cloudflare token
    encrypt_cloudflare_token_sops

    # Update ExternalSecrets configuration
    log_info "Updating External Secrets configuration for SOPS..."
    update_infrastructure_values "sops"

    # Template ClusterIssuers
    template_clusterissuers

    log_success "SOPS setup complete!"
    show_next_steps_sops
}

collect_tls_config() {
    echo
    log_info "TLS Certificate Configuration"
    echo

    read -rp "Enter your email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
    read -rp "Enter your DNS zone (e.g., mycureapp.com): " DNS_ZONE
    read -rsp "Enter your Cloudflare API token: " CLOUDFLARE_API_TOKEN
    echo

    export LETSENCRYPT_EMAIL DNS_ZONE CLOUDFLARE_API_TOKEN
}

encrypt_cloudflare_token_sops() {
    log_info "Encrypting Cloudflare API token..."

    # Create plaintext secret
    TEMP_SECRET="/tmp/cloudflare-token-plaintext.yaml"
    cat > "$TEMP_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "${CLOUDFLARE_API_TOKEN}"
EOF

    # Encrypt with SOPS
    sops --encrypt "$TEMP_SECRET" > "${REPO_ROOT}/infrastructure/tls/cloudflare-token.enc.yaml"
    rm "$TEMP_SECRET"

    log_success "Encrypted Cloudflare API token"
}

template_clusterissuers() {
    log_info "Templating ClusterIssuer manifests..."

    # Update staging issuer
    sed -i "s|{{ LETSENCRYPT_EMAIL }}|${LETSENCRYPT_EMAIL}|g" \
        "${REPO_ROOT}/infrastructure/tls/clusterissuer-staging.yaml"
    sed -i "s|{{ DNS_ZONE }}|${DNS_ZONE}|g" \
        "${REPO_ROOT}/infrastructure/tls/clusterissuer-staging.yaml"

    # Update production issuer
    sed -i "s|{{ LETSENCRYPT_EMAIL }}|${LETSENCRYPT_EMAIL}|g" \
        "${REPO_ROOT}/infrastructure/tls/clusterissuer-prod.yaml"
    sed -i "s|{{ DNS_ZONE }}|${DNS_ZONE}|g" \
        "${REPO_ROOT}/infrastructure/tls/clusterissuer-prod.yaml"

    # Update ExternalSecret
    sed -i "s|{{ SECRET_STORE_NAME }}|sops-secretstore|g" \
        "${REPO_ROOT}/infrastructure/tls/externalsecret-cloudflare.yaml"
    sed -i "s|{{ SECRET_KEY }}|cloudflare-token|g" \
        "${REPO_ROOT}/infrastructure/tls/externalsecret-cloudflare.yaml"

    log_success "Templated ClusterIssuer manifests"
}

update_infrastructure_values() {
    PROVIDER=$1
    log_info "Updating infrastructure values..."

    # Enable certManagerIssuers
    sed -i "s|enabled: false  # Enable after running scripts/secrets.sh|enabled: true|" \
        "${REPO_ROOT}/argocd/infrastructure/values.yaml"
    sed -i "s|email: \"\"  # Email for Let's Encrypt|email: \"${LETSENCRYPT_EMAIL}\"|" \
        "${REPO_ROOT}/argocd/infrastructure/values.yaml"
    sed -i "s|dnsZone: \"\"  # DNS zone|dnsZone: \"${DNS_ZONE}\"|" \
        "${REPO_ROOT}/argocd/infrastructure/values.yaml"

    # Update external secrets provider
    sed -i "s|provider: aws|provider: ${PROVIDER}|" \
        "${REPO_ROOT}/argocd/infrastructure/values.yaml"

    log_success "Updated infrastructure values"
}

show_next_steps_sops() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Next Steps"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_success "SOPS setup complete!"
    echo
    echo "1. Backup your age private key securely:"
    echo "   ${AGE_KEY_FILE}"
    echo
    echo "2. Commit the encrypted files to Git:"
    echo "   git add ."
    echo "   git commit -m \"feat: Add TLS certificate automation with SOPS\""
    echo "   git push"
    echo
    echo "3. Wait for ArgoCD to sync (or trigger manually)"
    echo
    echo "4. Verify ClusterIssuer is ready:"
    echo "   kubectl get clusterissuer"
    echo
    echo "5. Check certificate provisioning:"
    echo "   kubectl get certificate -n gateway-system"
    echo
}

# ==============================================================================
# Placeholder functions for other providers
# ==============================================================================

setup_aws() {
    log_warn "AWS Secrets Manager setup not yet implemented"
    log_info "This will be implemented in a future update"
    log_info "For now, use SOPS + age or Manual setup"
    show_provider_menu
}

setup_azure() {
    log_warn "Azure Key Vault setup not yet implemented"
    log_info "This will be implemented in a future update"
    log_info "For now, use SOPS + age or Manual setup"
    show_provider_menu
}

setup_gcp() {
    log_warn "GCP Secret Manager setup not yet implemented"
    log_info "This will be implemented in a future update"
    log_info "For now, use SOPS + age or Manual setup"
    show_provider_menu
}

setup_manual() {
    log_warn "Manual setup creates plain Kubernetes secrets"
    log_warn "This is NOT recommended for production!"
    log_warn "Secrets will NOT be backed up in Git"
    echo
    read -rp "Continue? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        show_provider_menu
        return
    fi

    check_kubeconfig || return 1
    collect_tls_config

    log_info "Creating plain Kubernetes secret..."
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic cloudflare-api-token \
        --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
        --namespace=cert-manager \
        --dry-run=client -o yaml | kubectl apply -f -

    # Template ClusterIssuers
    template_clusterissuers
    update_infrastructure_values "manual"

    log_success "Manual setup complete"
    log_warn "Remember: Your secrets are NOT backed up!"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    echo
    echo "╔════════════════════════════════════════════╗"
    echo "║   Infrastructure Secrets Management        ║"
    echo "║   TLS Certificates & External Secrets      ║"
    echo "╚════════════════════════════════════════════╝"

    show_provider_menu
}

main "$@"
