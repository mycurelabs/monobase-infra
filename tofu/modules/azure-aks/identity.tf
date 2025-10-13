# Azure Identities for Workload Identity

# Managed Identity for Velero
resource "azurerm_user_assigned_identity" "velero" {
  count = var.enable_workload_identity ? 1 : 0

  name                = "${var.cluster_name}-velero"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "velero" {
  count = var.enable_workload_identity ? 1 : 0

  name                = "${var.cluster_name}-velero"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.velero[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:velero:velero"
}

# Managed Identity for cert-manager
resource "azurerm_user_assigned_identity" "cert_manager" {
  count = var.enable_workload_identity ? 1 : 0

  name                = "${var.cluster_name}-cert-manager"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  count = var.enable_workload_identity ? 1 : 0

  name                = "${var.cluster_name}-cert-manager"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.cert_manager[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}
