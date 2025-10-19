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
    log_info "This feature will be implemented in a future update"
    log_info "For now, please use GCP Secret Manager (fully supported)"
    echo
    log_info "Planned features for AWS:"
    echo "  • Auto-detect AWS region and account"
    echo "  • Create secrets in AWS Secrets Manager"
    echo "  • Configure IRSA (IAM Roles for Service Accounts)"
    echo "  • Generate ClusterSecretStore with AWS provider"
    echo "  • Create ExternalSecret manifests"
    echo
    log_info "Implementation similar to GCP Secret Manager"
    log_info "See scripts/secrets-gcp.sh for reference"
    echo
    read -rp "Press Enter to return to main menu..."
    return 1
}
