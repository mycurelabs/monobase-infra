variable "cluster_name" { type = string }
variable "region" { type = string }
variable "kubernetes_version" { type = string }
variable "vpc_cidr" { type = string }
variable "ha_control_plane" { type = bool }
variable "auto_upgrade" { type = bool }
variable "surge_upgrade" { type = bool }
variable "tags" { type = list(string) }
variable "default_node_pool_key" { type = string }

variable "node_pools" {
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
