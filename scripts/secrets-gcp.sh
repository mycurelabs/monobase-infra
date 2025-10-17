#!/usr/bin/env bash
# GCP Secret Manager Provider for Secrets Management
# Integrates with Google Cloud Secret Manager for secret storage

set -euo pipefail

# This script is sourced by secrets.sh, which provides:
# - SCRIPT_DIR, REPO_ROOT
# - log_* functions
# - check_command, select_kubeconfig, check_kubeconfig
# - collect_tls_config, template_clusterissuers, update_infrastructure_values

setup_gcp() {
    log_warn "GCP Secret Manager setup not yet implemented"
    log_info "This will be implemented in a future update"
    log_info "For now, use SOPS + age or Manual setup"
    echo
    log_info "Planned features:"
    echo "  • Auto-detect GCP project"
    echo "  • Create secret in GCP Secret Manager"
    echo "  • Configure Workload Identity"
    echo "  • Deploy ExternalSecret with GCP provider"
    echo
    read -rp "Press Enter to return to main menu..."
    return 1
}
