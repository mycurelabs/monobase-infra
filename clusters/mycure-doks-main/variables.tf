# MyCure DOKS Cluster - Variables

variable "cluster_name" {
  description = "Name of the DOKS cluster"
  type        = string
  default     = "mycure-doks-main"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sgp1"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.33.1-do.5"
}

variable "node_size" {
  description = "Droplet size for nodes"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "node_count" {
  description = "Number of nodes"
  type        = number
  default     = 3
}

variable "min_nodes" {
  description = "Minimum nodes (same as node_count for no autoscaling)"
  type        = number
  default     = 3
}

variable "max_nodes" {
  description = "Maximum nodes (same as node_count for no autoscaling)"
  type        = number
  default     = 3
}

variable "ha_control_plane" {
  description = "Enable HA control plane"
  type        = bool
  default     = false
}

variable "auto_upgrade" {
  description = "Enable automatic Kubernetes version upgrades"
  type        = bool
  default     = true
}

variable "surge_upgrade" {
  description = "Enable surge upgrades"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.116.0.0/20"
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance window"
  type        = string
  default     = "sunday"
}

variable "maintenance_window_hour" {
  description = "Hour of day for maintenance window (UTC)"
  type        = string
  default     = "04:00"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = list(string)
  default     = ["mycure", "staging", "monobase-infrastructure"]
}


# Staging node pool configuration
variable "staging_node_size" {
  description = "Droplet size for staging nodes"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "staging_node_count" {
  description = "Initial number of staging nodes"
  type        = number
  default     = 1
}

variable "staging_min_nodes" {
  description = "Minimum staging nodes for autoscaling"
  type        = number
  default     = 1
}

variable "staging_max_nodes" {
  description = "Maximum staging nodes for autoscaling"
  type        = number
  default     = 3
}

# Production node pool configuration
variable "production_node_size" {
  description = "Droplet size for production nodes"
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "production_node_count" {
  description = "Initial number of production nodes"
  type        = number
  default     = 1
}

variable "production_min_nodes" {
  description = "Minimum production nodes for autoscaling"
  type        = number
  default     = 1
}

variable "production_max_nodes" {
  description = "Maximum production nodes for autoscaling"
  type        = number
  default     = 3
}
