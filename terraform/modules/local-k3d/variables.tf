# k3d Module - Variables

variable "cluster_name" {
  description = "Name of the k3d cluster"
  type        = string
  default     = "monobase-test"
}

variable "k3s_version" {
  description = "K3s/Kubernetes version"
  type        = string
  default     = "v1.28.3-k3s1"
}

variable "servers" {
  description = "Number of server nodes"
  type        = number
  default     = 1
}

variable "agents" {
  description = "Number of agent nodes"
  type        = number
  default     = 2
}

variable "http_port" {
  description = "Host port for HTTP (80)"
  type        = number
  default     = 8080
}

variable "https_port" {
  description = "Host port for HTTPS (443)"
  type        = number
  default     = 8443
}

variable "disable_traefik" {
  description = "Disable Traefik (use Envoy Gateway instead)"
  type        = bool
  default     = true
}

variable "install_gateway_api" {
  description = "Install Gateway API CRDs"
  type        = bool
  default     = true
}
