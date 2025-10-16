# Azure AKS Cluster Module

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "system"
    vm_size             = "Standard_D4s_v3"
    node_count          = 3
    enable_auto_scaling = false
    os_disk_size_gb     = 100
    vnet_subnet_id      = azurerm_subnet.nodes.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
  }

  workload_identity_enabled = var.enable_workload_identity
  oidc_issuer_enabled       = var.enable_workload_identity

  tags = var.tags
}

# User node pools
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  node_count            = each.value.node_count
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  enable_auto_scaling   = true
  os_disk_size_gb       = each.value.os_disk_size
  vnet_subnet_id        = azurerm_subnet.nodes.id

  tags = var.tags
}

# Managed Identity for External Secrets
resource "azurerm_user_assigned_identity" "external_secrets" {
  count = var.enable_workload_identity ? 1 : 0

  name                = "${var.cluster_name}-external-secrets"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = var.tags
}

# Federated Identity Credential
resource "azurerm_federated_identity_credential" "external_secrets" {
  count = var.enable_workload_identity ? 1 : 0

  name                = "${var.cluster_name}-external-secrets"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.external_secrets[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets-system:external-secrets"
}
