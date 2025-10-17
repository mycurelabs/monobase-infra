#!/usr/bin/env bash
# AWS Secrets Manager Provider for Secrets Management
# Integrates with AWS Secrets Manager for secret storage

set -euo pipefail

# This script is sourced by secrets.sh, which provides:
# - SCRIPT_DIR, REPO_ROOT
# - log_* functions
# - check_command, select_kubeconfig, check_kubeconfig
# - collect_tls_config, template_clusterissuers, update_infrastructure_values

setup_aws() {
    log_warn "AWS Secrets Manager setup not yet implemented"
    log_info "This will be implemented in a future update"
    log_info "For now, use SOPS + age or Manual setup"
    echo
    log_info "Planned features:"
    echo "  • Auto-detect AWS region"
    echo "  • Create secret in AWS Secrets Manager"
    echo "  • Configure IRSA (IAM Roles for Service Accounts)"
    echo "  • Deploy ExternalSecret with AWS provider"
    echo
    read -rp "Press Enter to return to main menu..."
    return 1
}
