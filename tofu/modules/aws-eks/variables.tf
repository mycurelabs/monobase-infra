# AWS EKS Module - Variables
# All configurable parameters for EKS cluster

# Deployment Profile Presets
locals {
  profile_defaults = {
    small = {
      instance_types = ["m6i.xlarge"] # 4 vCPU, 16GB RAM
      min_size       = 3
      desired_size   = 3
      max_size       = 10
      disk_size      = 100
    }
    medium = {
      instance_types = ["m6i.xlarge"] # 4 vCPU, 16GB RAM
      min_size       = 5
      desired_size   = 5
      max_size       = 15
      disk_size      = 100
    }
    large = {
      instance_types = ["m6i.2xlarge"] # 8 vCPU, 32GB RAM
      min_size       = 5
      desired_size   = 5
      max_size       = 20
      disk_size      = 100
    }
  }

  # Use custom node_groups if provided, otherwise use profile defaults
  effective_node_groups = length(var.node_groups) > 0 ? var.node_groups : {
    general = merge(
      local.profile_defaults[var.deployment_profile],
      {
        labels = {}
        taints = []
      }
    )
  }
}

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
  default     = [] # Auto-detected if empty
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

variable "api_access_cidrs" {
  description = "CIDR blocks allowed to access EKS API when public endpoint is enabled"
  type        = list(string)
  default     = ["0.0.0.0/0"] # CHANGE IN PRODUCTION: Restrict to your IP ranges
}

variable "deployment_profile" {
  description = "Deployment size profile: small (1-5 clients), medium (5-15 clients), large (15+ clients)"
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large", "custom"], var.deployment_profile)
    error_message = "Must be 'small', 'medium', 'large', or 'custom'"
  }
}

variable "node_groups" {
  description = "EKS managed node group configurations (leave empty to use deployment_profile defaults)"
  type = map(object({
    instance_types = list(string)
    desired_size   = number
    max_size       = number
    min_size       = number
    disk_size      = optional(number, 100)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {} # Empty = use profile defaults
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

# IAM Policy Scoping Variables
variable "velero_backup_bucket" {
  description = "S3 bucket name for Velero backups (scopes IAM permissions)"
  type        = string
  default     = "" # Empty = wildcard (not recommended for production)
}

variable "route53_zone_arns" {
  description = "List of Route53 hosted zone ARNs for cert-manager (scopes IAM permissions)"
  type        = list(string)
  default     = [] # Empty = wildcard on all zones (not recommended for production)
}
