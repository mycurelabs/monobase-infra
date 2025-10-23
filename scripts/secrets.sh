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

# Command-line arguments (defaults to empty, will trigger interactive mode)
OPT_PROVIDER=""
OPT_KUBECONFIG=""
OPT_GCP_PROJECT=""

# ==============================================================================
# Helper Functions
# ==============================================================================

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Manage infrastructure secrets for TLS certificates and cloud KMS integration.

OPTIONS:
    --provider <gcp|aws|azure>    Cloud provider for secret management
    --kubeconfig <path>           Path to kubeconfig file (or use KUBECONFIG env var)
    --project <project-id>        GCP project ID (only for --provider gcp)
    -h, --help                    Show this help message

ENVIRONMENT VARIABLES (for non-interactive mode):
    LETSENCRYPT_EMAIL             Email for Let's Encrypt certificate notifications
    DNS_ZONE                      Your DNS zone (e.g., mycureapp.com)
    CLOUDFLARE_API_TOKEN          Cloudflare API token for DNS-01 challenge

EXAMPLES:
    # Interactive mode (prompts for all choices including TLS config)
    ./secrets.sh

    # Non-interactive GCP setup (will prompt for TLS config interactively)
    ./secrets.sh --provider gcp --kubeconfig ~/.kube/mycure-doks-main --project mc-v4-prod

    # Fully non-interactive with environment variables
    export LETSENCRYPT_EMAIL='admin@example.com'
    export DNS_ZONE='example.com'
    export CLOUDFLARE_API_TOKEN='your-token-here'
    ./secrets.sh --provider gcp --kubeconfig ~/.kube/mycure-doks-main --project mc-v4-prod

    # Use KUBECONFIG environment variable
    KUBECONFIG=~/.kube/mycure-doks-main ./secrets.sh --provider gcp --project mc-v4-prod

PROVIDERS:
    gcp     GCP Secret Manager (Recommended - Free tier available)
    aws     AWS Secrets Manager (Not yet implemented)
    azure   Azure Key Vault (Not yet implemented)

EOF
    exit 0
}

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
    # If kubeconfig provided via flag, use it directly
    if [ -n "$OPT_KUBECONFIG" ]; then
        if [ ! -f "$OPT_KUBECONFIG" ]; then
            log_error "Kubeconfig file not found: $OPT_KUBECONFIG"
            return 1
        fi
        export KUBECONFIG="$OPT_KUBECONFIG"
        log_info "Using kubeconfig: $KUBECONFIG"
        return 0
    fi
    
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

    # Check if fzf is available
    if command -v fzf &>/dev/null; then
        # Build display list with current KUBECONFIG marker
        local display_list=()
        local current_kubeconfig="${KUBECONFIG:-${HOME}/.kube/config}"
        
        for i in "${!kubeconfigs[@]}"; do
            local marker="  "
            if [ "${kubeconfig_paths[$i]}" = "$current_kubeconfig" ]; then
                marker="* "
            fi
            display_list+=("${marker}${kubeconfigs[$i]}")
        done
        
        # Add special options
        display_list+=("  Use current KUBECONFIG (${KUBECONFIG:-not set})")
        display_list+=("  Exit")
        
        # Use fzf for selection
        local selected
        selected=$(printf '%s\n' "${display_list[@]}" | fzf \
            --height=15 \
            --border \
            --prompt="Select Kubeconfig: " \
            --header="* = current | TAB to select | ESC to cancel" \
            --ansi)
        
        if [ -z "$selected" ]; then
            log_error "No kubeconfig selected"
            return 1
        fi
        
        # Handle selection
        if [[ "$selected" == *"Exit"* ]]; then
            exit 0
        elif [[ "$selected" == *"Use current KUBECONFIG"* ]]; then
            if [ -z "${KUBECONFIG:-}" ]; then
                log_warn "KUBECONFIG not set, using kubectl default"
            fi
        else
            # Extract kubeconfig name (remove marker)
            local selected_name="${selected:2}"
            
            # Find matching kubeconfig path
            for i in "${!kubeconfigs[@]}"; do
                if [ "${kubeconfigs[$i]}" = "$selected_name" ]; then
                    export KUBECONFIG="${kubeconfig_paths[$i]}"
                    log_info "Using kubeconfig: ${KUBECONFIG}"
                    break
                fi
            done
        fi
        
    else
        # Fallback to numbered menu if fzf not available
        log_warn "fzf not found. Using numbered menu. Install with: mise install fzf"
        echo
        
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

    # Try to extract from existing ClusterIssuer files (idempotent)
    ISSUER_FILE="${REPO_ROOT}/infrastructure/tls/clusterissuer-prod.yaml"
    
    if [ -f "$ISSUER_FILE" ]; then
        # Extract email and DNS zone from existing configuration
        EXISTING_EMAIL=$(grep "email:" "$ISSUER_FILE" | head -1 | sed 's/.*email: *"\?\([^"]*\)"\?.*/\1/' | tr -d ' ')
        EXISTING_ZONE=$(grep -A1 "dnsZones:" "$ISSUER_FILE" | tail -1 | sed 's/.*- *"\?\([^"]*\)"\?.*/\1/' | tr -d ' ')
        
        # Check if values are real (not templates like {{ LETSENCRYPT_EMAIL }})
        if [[ ! "$EXISTING_EMAIL" =~ "{{" ]] && [ -n "$EXISTING_EMAIL" ] && [ "$EXISTING_EMAIL" != "email:" ]; then
            export LETSENCRYPT_EMAIL="$EXISTING_EMAIL"
            log_success "Using existing Let's Encrypt email: $LETSENCRYPT_EMAIL"
        fi
        
        if [[ ! "$EXISTING_ZONE" =~ "{{" ]] && [ -n "$EXISTING_ZONE" ] && [ "$EXISTING_ZONE" != "dnsZones:" ]; then
            export DNS_ZONE="$EXISTING_ZONE"
            log_success "Using existing DNS zone: $DNS_ZONE"
        fi
    fi

    # Check if running in non-interactive mode (no TTY)
    if [ ! -t 0 ]; then
        # In non-interactive mode, we need email and DNS zone for ClusterIssuer
        if [ -z "${LETSENCRYPT_EMAIL:-}" ] || [ -z "${DNS_ZONE:-}" ]; then
            log_error "Running in non-interactive mode but TLS configuration is incomplete"
            log_info ""
            log_info "Missing configuration:"
            [ -z "${LETSENCRYPT_EMAIL:-}" ] && log_info "  - Let's Encrypt email"
            [ -z "${DNS_ZONE:-}" ] && log_info "  - DNS zone"
            log_info ""
            log_info "To run interactively:"
            log_info "  bash scripts/secrets.sh"
            log_info ""
            log_info "Or pre-configure missing values as environment variables:"
            log_info "  export LETSENCRYPT_EMAIL='your@email.com'"
            log_info "  export DNS_ZONE='yourdomain.com'"
            log_info "  bash scripts/secrets.sh --provider gcp --kubeconfig <path> --project <project-id>"
            return 1
        else
            # All values present from existing config or env vars
            log_success "TLS configuration complete (using existing/environment values)"
            return 0
        fi
    fi

    # Interactive mode - use environment variables if set, otherwise prompt for missing values
    if [ -z "${LETSENCRYPT_EMAIL:-}" ]; then
        read -rp "Enter your email for Let's Encrypt notifications: " LETSENCRYPT_EMAIL
    else
        log_info "Using LETSENCRYPT_EMAIL from environment: $LETSENCRYPT_EMAIL"
    fi
    
    if [ -z "${DNS_ZONE:-}" ]; then
        read -rp "Enter your DNS zone (e.g., mycureapp.com): " DNS_ZONE
    else
        log_info "Using DNS_ZONE from environment: $DNS_ZONE"
    fi

    export LETSENCRYPT_EMAIL DNS_ZONE
}

template_clusterissuers() {
    # Check if templates still exist (idempotent)
    local needs_templating=false
    
    if grep -q "{{ LETSENCRYPT_EMAIL }}" "${REPO_ROOT}/infrastructure/tls/clusterissuer-prod.yaml" 2>/dev/null; then
        needs_templating=true
    fi
    
    if [ "$needs_templating" = false ]; then
        log_success "ClusterIssuers already configured, skipping templating"
        return 0
    fi
    
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

    log_success "Templated ClusterIssuer manifests"
}

update_infrastructure_values() {
    PROVIDER=$1
    log_info "Updating infrastructure values..."

    # Enable certManagerIssuers
    sed -i "s|enabled: false  # Enable after running scripts/secrets.sh|enabled: true  # Enable after running scripts/secrets.sh|" \
        "${REPO_ROOT}/argocd/infrastructure/values.yaml"
    sed -i "s|email: \"\"|email: \"${LETSENCRYPT_EMAIL}\"|" \
        "${REPO_ROOT}/argocd/infrastructure/values.yaml"
    sed -i "s|dnsZone: \"\"|dnsZone: \"${DNS_ZONE}\"|" \
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
    # Auto-detect provider from existing ClusterSecretStore files (idempotent)
    if [ -f "${REPO_ROOT}/infrastructure/external-secrets/gcp-secretstore.yaml" ]; then
        log_success "Detected existing GCP ClusterSecretStore"
        source "${SCRIPT_DIR}/secrets-gcp.sh" && setup_gcp
        return 0
    elif [ -f "${REPO_ROOT}/infrastructure/external-secrets/aws-secretstore.yaml" ]; then
        log_success "Detected existing AWS ClusterSecretStore"
        source "${SCRIPT_DIR}/secrets-aws.sh" && setup_aws
        return 0
    elif [ -f "${REPO_ROOT}/infrastructure/external-secrets/azure-secretstore.yaml" ]; then
        log_success "Detected existing Azure ClusterSecretStore"
        source "${SCRIPT_DIR}/secrets-azure.sh" && setup_azure
        return 0
    fi
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Secrets Management - Cloud KMS Provider"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Check if fzf is available
    if command -v fzf &>/dev/null; then
        # Build provider list for fzf
        local providers=(
            "* GCP Secret Manager (Recommended - Free tier)"
            "  AWS Secrets Manager (Not yet implemented)"
            "  Azure Key Vault (Not yet implemented)"
            "  Exit"
        )
        
        # Use fzf for selection
        local selected
        selected=$(printf '%s\n' "${providers[@]}" | fzf \
            --height=10 \
            --border \
            --prompt="Select Provider: " \
            --header="* = recommended | TAB to select | ESC to cancel" \
            --ansi)
        
        if [ -z "$selected" ]; then
            log_error "No provider selected"
            exit 1
        fi
        
        # Handle selection
        if [[ "$selected" == *"GCP"* ]]; then
            source "${SCRIPT_DIR}/secrets-gcp.sh" && setup_gcp
        elif [[ "$selected" == *"AWS"* ]]; then
            source "${SCRIPT_DIR}/secrets-aws.sh" && setup_aws && show_provider_menu
        elif [[ "$selected" == *"Azure"* ]]; then
            source "${SCRIPT_DIR}/secrets-azure.sh" && setup_azure && show_provider_menu
        elif [[ "$selected" == *"Exit"* ]]; then
            exit 0
        fi
        
    else
        # Fallback to numbered menu if fzf not available
        log_warn "fzf not found. Using numbered menu. Install with: mise install fzf"
        echo
        
        echo "Choose your cloud secrets provider:"
        echo
        echo "  1) GCP Secret Manager (Recommended - Free tier)"
        echo "  2) AWS Secrets Manager (Not yet implemented)"
        echo "  3) Azure Key Vault (Not yet implemented)"
        echo "  4) Exit"
        echo
        read -rp "Enter choice [1-4]: " choice
        echo

        case $choice in
            1) source "${SCRIPT_DIR}/secrets-gcp.sh" && setup_gcp ;;
            2) source "${SCRIPT_DIR}/secrets-aws.sh" && setup_aws && show_provider_menu ;;
            3) source "${SCRIPT_DIR}/secrets-azure.sh" && setup_azure && show_provider_menu ;;
            4) exit 0 ;;
            *) log_error "Invalid choice"; show_provider_menu ;;
        esac
    fi
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --provider)
                OPT_PROVIDER="$2"
                shift 2
                ;;
            --kubeconfig)
                OPT_KUBECONFIG="$2"
                shift 2
                ;;
            --project)
                OPT_GCP_PROJECT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    # Parse command-line arguments
    parse_args "$@"
    
    echo
    echo "╔════════════════════════════════════════════╗"
    echo "║   Infrastructure Secrets Management        ║"
    echo "║   TLS Certificates & External Secrets      ║"
    echo "╚════════════════════════════════════════════╝"

    # If provider specified via flag, skip menu and go directly to provider setup
    if [ -n "$OPT_PROVIDER" ]; then
        case "$OPT_PROVIDER" in
            gcp)
                source "${SCRIPT_DIR}/secrets-gcp.sh" && setup_gcp
                ;;
            aws)
                source "${SCRIPT_DIR}/secrets-aws.sh" && setup_aws
                ;;
            azure)
                source "${SCRIPT_DIR}/secrets-azure.sh" && setup_azure
                ;;
            *)
                log_error "Invalid provider: $OPT_PROVIDER"
                log_info "Valid providers: gcp, aws, azure"
                exit 1
                ;;
        esac
    else
        # Interactive mode - show provider menu
        show_provider_menu
    fi
}

main "$@"
