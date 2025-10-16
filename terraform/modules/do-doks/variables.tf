# DigitalOcean DOKS Module - Variables
# All configurable parameters for DOKS cluster

# Deployment Profile Presets
locals {
  profile_defaults = {
    small = {
      node_size  = "s-2vcpu-4gb" # 2 vCPU, 4GB RAM
      node_count = 3
      min_nodes  = 3
      max_nodes  = 10
    }
    medium = {
      node_size  = "s-4vcpu-8gb" # 4 vCPU, 8GB RAM
      node_count = 5
      min_nodes  = 5
      max_nodes  = 15
    }
    large = {
      node_size  = "s-8vcpu-16gb" # 8 vCPU, 16GB RAM
      node_count = 10
      min_nodes  = 5
      max_nodes  = 20
    }
  }

  # Use custom node_pool if provided, otherwise use profile defaults
  effective_node_pool = var.node_size != "" ? {
    node_size  = var.node_size
    node_count = var.node_count
    min_nodes  = var.min_nodes
    max_nodes  = var.max_nodes
  } : local.profile_defaults[var.deployment_profile]
}

variable "cluster_name" {
  description = "Name of the DOKS cluster"
  type        = string
}

variable "region" {
  description = "DigitalOcean region (nyc1, nyc3, sfo3, sgp1, lon1, fra1, tor1, blr1, ams3)"
  type        = string
  default     = "nyc3"
}

variable "kubernetes_version" {
  description = "Kubernetes version (use 'doctl kubernetes options versions' to list available versions)"
  type        = string
  default     = "1.28.2-do.0"
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

# Custom node pool configuration (overrides deployment_profile)
variable "node_size" {
  description = "Droplet size for nodes (leave empty to use deployment_profile defaults)"
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Number of nodes (leave at 0 to use deployment_profile defaults)"
  type        = number
  default     = 0
}

variable "min_nodes" {
  description = "Minimum nodes for autoscaling (leave at 0 to use deployment_profile defaults)"
  type        = number
  default     = 0
}

variable "max_nodes" {
  description = "Maximum nodes for autoscaling (leave at 0 to use deployment_profile defaults)"
  type        = number
  default     = 0
}

variable "auto_upgrade" {
  description = "Enable automatic Kubernetes version upgrades"
  type        = bool
  default     = true
}

variable "surge_upgrade" {
  description = "Enable surge upgrades (adds extra node during upgrades for zero downtime)"
  type        = bool
  default     = true
}

variable "ha_control_plane" {
  description = "Enable HA control plane (3 master nodes instead of 1)"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.244.0.0/16"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = list(string)
  default     = []
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance window (monday, tuesday, etc.)"
  type        = string
  default     = "sunday"

  validation {
    condition     = contains(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "any"], var.maintenance_window_day)
    error_message = "Must be a valid day of week or 'any'"
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day for maintenance window (00:00-23:00 UTC)"
  type        = string
  default     = "04:00"
}
