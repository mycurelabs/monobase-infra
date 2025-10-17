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

select_kubeconfig() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Select Kubernetes Cluster"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Find all kubeconfig files
    local kubeconfigs=()
    local kubeconfig_paths=()

    # Check default location
    if [ -f "${HOME}/.kube/config" ]; then
        kubeconfigs+=("Default (~/.kube/config)")
        kubeconfig_paths+=("${HOME}/.kube/config")
    fi

    # Check ~/.kube/ directory for other configs
    if [ -d "${HOME}/.kube" ]; then
        while IFS= read -r file; do
            local basename=$(basename "$file")
            # Skip default config (already added), directories, and backup files
            if [ "$file" != "${HOME}/.kube/config" ] && [ -f "$file" ] && [[ ! "$basename" =~ \.backup\. ]]; then
                kubeconfigs+=("$basename")
                kubeconfig_paths+=("$file")
            fi
        done < <(find "${HOME}/.kube" -maxdepth 1 -type f 2>/dev/null | sort)
    fi

    if [ ${#kubeconfigs[@]} -eq 0 ]; then
        log_error "No kubeconfig files found"
        log_info "Create a cluster first with: mise run provision"
        return 1
    fi

    # Display options
    echo "Available clusters:"
    echo
    for i in "${!kubeconfigs[@]}"; do
        echo "  $((i+1))) ${kubeconfigs[$i]}"
    done
    echo "  $((${#kubeconfigs[@]}+1))) Use current KUBECONFIG (${KUBECONFIG:-not set})"
    echo "  $((${#kubeconfigs[@]}+2))) Exit"
    echo

    read -rp "Enter choice [1-$((${#kubeconfigs[@]}+2))]: " choice
    echo

    if [ "$choice" -eq "$((${#kubeconfigs[@]}+2))" ] 2>/dev/null; then
        exit 0
    elif [ "$choice" -eq "$((${#kubeconfigs[@]}+1))" ] 2>/dev/null; then
        if [ -z "${KUBECONFIG:-}" ]; then
            log_warn "KUBECONFIG not set, using kubectl default"
        fi
    elif [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#kubeconfigs[@]}" ]; then
        export KUBECONFIG="${kubeconfig_paths[$((choice-1))]}"
        log_info "Using kubeconfig: ${KUBECONFIG}"
    else
        log_error "Invalid choice"
        select_kubeconfig
        return $?
    fi
}

check_kubeconfig() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    log_success "Connected to cluster: $(kubectl config current-context)"
    return 0
}

# ==============================================================================
# Shared TLS Functions
# ==============================================================================

collect_tls_config() {
    echo
    log_info "TLS Certificate Configuration"
    echo

    read -rp "Enter your email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
    read -rp "Enter your DNS zone (e.g., mycureapp.com): " DNS_ZONE
    read -rp "Enter your Cloudflare API token: " CLOUDFLARE_API_TOKEN

    export LETSENCRYPT_EMAIL DNS_ZONE CLOUDFLARE_API_TOKEN
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
        1) source "${SCRIPT_DIR}/secrets-sops.sh" && setup_sops ;;
        2) source "${SCRIPT_DIR}/secrets-aws.sh" && setup_aws && show_provider_menu ;;
        3) source "${SCRIPT_DIR}/secrets-azure.sh" && setup_azure && show_provider_menu ;;
        4) source "${SCRIPT_DIR}/secrets-gcp.sh" && setup_gcp && show_provider_menu ;;
        5) source "${SCRIPT_DIR}/secrets-manual.sh" && setup_manual ;;
        6) exit 0 ;;
        *) log_error "Invalid choice"; show_provider_menu ;;
    esac
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
