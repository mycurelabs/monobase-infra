#!/usr/bin/env bash
# Manual Provider for Secrets Management
# Creates plain Kubernetes secrets (Testing only - NOT for production!)

set -euo pipefail

# This script is sourced by secrets.sh, which provides:
# - SCRIPT_DIR, REPO_ROOT
# - log_* functions
# - check_command, select_kubeconfig, check_kubeconfig
# - collect_tls_config, template_clusterissuers, update_infrastructure_values

setup_manual() {
    log_warn "Manual setup creates plain Kubernetes secrets"
    log_warn "This is NOT recommended for production!"
    log_warn "Secrets will NOT be backed up in Git"
    echo
    read -rp "Continue? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 1
    fi

    # Select cluster
    select_kubeconfig || return 1
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
