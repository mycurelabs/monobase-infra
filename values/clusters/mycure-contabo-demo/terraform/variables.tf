variable "cluster_name" {
  description = "k3d cluster name (also the kube context: k3d-<name>)"
  type        = string
}

variable "k3s_version" {
  description = "K3s image tag. Match DOKS prod where possible for fidelity."
  type        = string
  default     = "v1.33.4-k3s1"
}

variable "servers" {
  type    = number
  default = 1
}

variable "agents" {
  type    = number
  default = 2
}

variable "http_port" {
  type    = number
  default = 8080
}

variable "https_port" {
  type    = number
  default = 8443
}

variable "disable_traefik" {
  type    = bool
  default = true
}

variable "install_gateway_api" {
  type    = bool
  default = true
}

variable "storage_path" {
  description = "Persistent host dir for k3s local-path PVs (survives reboots, unlike the module's /tmp default)."
  type        = string
  default     = ""
}

variable "extra_port_mappings" {
  description = "Extra k3d port mappings (k3d -p syntax) — the cadence QUIC UDP legs."
  type        = list(string)
  default     = []
}

variable "api_port" {
  description = "Kubernetes API host binding — loopback only on this public VPS."
  type        = string
  default     = ""
}
