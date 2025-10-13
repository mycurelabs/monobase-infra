# Azure AKS Module - Variables

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "vnet_cidr" {
  description = "VNet CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_pools" {
  description = "AKS node pool configurations"
  type = map(object({
    vm_size      = string
    node_count   = number
    min_count    = number
    max_count    = number
    os_disk_size = optional(number, 100)
  }))
  default = {
    general = {
      vm_size      = "Standard_D8s_v3"  # 8 vCPU, 32GB
      node_count   = 5
      min_count    = 3
      max_count    = 20
      os_disk_size = 100
    }
  }
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for External Secrets"
  type        = bool
  default     = true
}

variable "enable_azure_disk_csi" {
  description = "Enable Azure Disk CSI driver"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default     = {}
}
