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
    log_info "This feature will be implemented in a future update"
    log_info "For now, please use GCP Secret Manager (fully supported)"
    echo
    log_info "Planned features for Azure:"
    echo "  • Auto-detect Azure subscription and tenant"
    echo "  • Create secrets in Azure Key Vault"
    echo "  • Configure Workload Identity (AKS)"
    echo "  • Generate ClusterSecretStore with Azure provider"
    echo "  • Create ExternalSecret manifests"
    echo
    log_info "Implementation similar to GCP Secret Manager"
    log_info "See scripts/secrets-gcp.sh for reference"
    echo
    read -rp "Press Enter to return to main menu..."
    return 1
}
