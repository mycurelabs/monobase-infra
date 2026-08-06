# DigitalOcean DOKS Module - Variables

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
  description = "Full version slug ('doctl kubernetes options versions'). With auto_upgrade, update this to the live slug after DO upgrades — never apply a downgrade."
  type        = string
}

variable "node_pools" {
  description = "Node pools keyed by pool name. Set node_count only on non-autoscaled pools (the autoscaler owns it otherwise)."
  type = map(object({
    size       = string
    node_count = optional(number)
    auto_scale = optional(bool, false)
    min_nodes  = optional(number)
    max_nodes  = optional(number)
    labels     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    tags = optional(list(string), [])
  }))
}

variable "default_node_pool_key" {
  description = "node_pools key rendered inline in the cluster resource. Immutable seat: this pool cannot be deleted separately and its size change replaces the CLUSTER — pick the pool least likely to be resized or removed."
  type        = string

  validation {
    condition     = contains(keys(var.node_pools), var.default_node_pool_key)
    error_message = "default_node_pool_key must be a key of node_pools"
  }
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
  description = "Enable HA control plane (3 master nodes instead of 1). Enabling is in-place; disabling replaces the cluster."
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (ForceNew on the VPC)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "tags" {
  description = "Cluster tags, applied verbatim (the provider filters the auto-managed k8s* tags)"
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
