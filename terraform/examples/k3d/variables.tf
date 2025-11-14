variable "cluster_name" {
  description = "Name of the k3d cluster"
  type        = string
  default     = "k3d-local"
}

variable "k3s_version" {
  description = "K3s version"
  type        = string
  default     = "v1.28.5-k3s1"
}

variable "servers" {
  description = "Number of server nodes (control plane)"
  type        = number
  default     = 1
}

variable "agents" {
  description = "Number of agent nodes (workers)"
  type        = number
  default     = 3
}

variable "http_port" {
  description = "HTTP port to expose (LoadBalancer)"
  type        = number
  default     = 80
}

variable "https_port" {
  description = "HTTPS port to expose (LoadBalancer)"
  type        = number
  default     = 443
}

variable "disable_traefik" {
  description = "Disable built-in Traefik (use Envoy Gateway instead)"
  type        = bool
  default     = true
}

variable "install_gateway_api" {
  description = "Install Gateway API CRDs"
  type        = bool
  default     = true
}
