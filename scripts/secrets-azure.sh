#!/usr/bin/env bash
# Azure Key Vault Provider for Secrets Management
# Integrates with Azure Key Vault for secret storage

set -euo pipefail

# This script is sourced by secrets.sh, which provides:
# - SCRIPT_DIR, REPO_ROOT
# - log_* functions
# - check_command, select_kubeconfig, check_kubeconfig
# - collect_tls_config, template_clusterissuers, update_infrastructure_values

setup_azure() {
    log_warn "Azure Key Vault setup not yet implemented"
    log_info "This will be implemented in a future update"
    log_info "For now, use SOPS + age or Manual setup"
    echo
    log_info "Planned features:"
    echo "  • Auto-detect Azure subscription"
    echo "  • Create secret in Azure Key Vault"
    echo "  • Configure Workload Identity"
    echo "  • Deploy ExternalSecret with Azure provider"
    echo
    read -rp "Press Enter to return to main menu..."
    return 1
}
