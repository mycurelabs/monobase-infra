# AWS EKS Module - Variables
# All configurable parameters for EKS cluster

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = []  # Auto-detected if empty
}

variable "enable_private_endpoint" {
  description = "Enable private API endpoint (more secure, requires VPN/bastion)"
  type        = bool
  default     = false
}

variable "enable_public_endpoint" {
  description = "Enable public API endpoint"
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "EKS managed node group configurations"
  type = map(object({
    instance_types = list(string)
    desired_size   = number
    max_size       = number
    min_size       = number
    disk_size      = optional(number, 100)
    labels         = optional(map(string), {})
    taints         = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    general = {
      instance_types = ["m6i.2xlarge"]
      desired_size   = 5
      max_size       = 20
      min_size       = 3
      disk_size      = 100
    }
  }
}

variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI driver addon (required for storage)"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (required for External Secrets)"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
