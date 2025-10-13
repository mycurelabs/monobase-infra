# GCP GKE Module - Variables

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "network_cidr" {
  description = "VPC network CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_pools" {
  description = "GKE node pool configurations"
  type = map(object({
    machine_type = string
    node_count   = number
    min_count    = number
    max_count    = number
    disk_size_gb = optional(number, 100)
  }))
  default = {
    general = {
      machine_type = "n2-standard-8"  # 8 vCPU, 32GB
      node_count   = 5
      min_count    = 3
      max_count    = 20
      disk_size_gb = 100
    }
  }
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Labels for all resources"
  type        = map(string)
  default     = {}
}
