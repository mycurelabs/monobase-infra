# DOKS Cluster - Variable Definitions

variable "cluster_name" {
  description = "Name of the DOKS cluster"
  type        = string
}

variable "region" {
  description = "DigitalOcean region (e.g., sgp1)"
  type        = string
  default     = "sgp1"
}

variable "kubernetes_version" {
  description = "Kubernetes version (use 'doctl kubernetes options versions' to list available)"
  type        = string
}

variable "deployment_profile" {
  description = "Deployment size profile: small (1-5 clients), medium (5-15), large (15+)"
  type        = string
  default     = "medium"
}

variable "node_size" {
  description = "Droplet size for nodes (empty = use deployment_profile defaults)"
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Initial number of nodes (0 = use deployment_profile defaults)"
  type        = number
  default     = 0
}

variable "min_nodes" {
  description = "Minimum nodes for autoscaling (0 = use deployment_profile defaults)"
  type        = number
  default     = 0
}

variable "max_nodes" {
  description = "Maximum nodes for autoscaling (0 = use deployment_profile defaults)"
  type        = number
  default     = 0
}

variable "auto_upgrade" {
  description = "Enable automatic Kubernetes version upgrades"
  type        = bool
  default     = false
}

variable "surge_upgrade" {
  description = "Enable surge upgrades (zero downtime)"
  type        = bool
  default     = true
}

variable "ha_control_plane" {
  description = "Enable HA control plane (3 master nodes)"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = list(string)
  default     = ["mycure", "production", "managed-by-terraform"]
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance window"
  type        = string
  default     = "sunday"
}

variable "maintenance_window_hour" {
  description = "Hour of day for maintenance window (UTC)"
  type        = string
  default     = "18:00"
}
