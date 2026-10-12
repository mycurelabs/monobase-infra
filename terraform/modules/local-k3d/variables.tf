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
  description = "Install Gateway API CRDs (NGF experimental bundle)"
  type        = bool
  default     = true
}

variable "gateway_api_ref" {
  description = "NGINX Gateway Fabric git ref for the experimental Gateway API CRD bundle. Keep in lockstep with nginxGateway.version / scripts/upgrade-gateway-api-crds.sh."
  type        = string
  default     = "v2.6.7"
}

variable "create_timeout" {
  description = "Timeout k3d waits for the cluster to become ready"
  type        = string
  default     = "180s"
}

variable "storage_path" {
  description = "Host directory mounted as k3s local-path storage on every node. Empty = /tmp/k3d-<cluster_name> (wiped on reboot). Set a persistent path for long-lived clusters."
  type        = string
  default     = ""
}

variable "extra_port_mappings" {
  description = "Additional k3d port mappings (k3d -p syntax), e.g. [\"6472:6472/udp@loadbalancer\"] for UDP gateway listeners."
  type        = list(string)
  default     = []
}

variable "api_port" {
  description = "k3d --api-port value ([HOST:]PORT), e.g. \"127.0.0.1:6445\" to keep the apiserver off public interfaces. Empty = k3d default (random port on 0.0.0.0)."
  type        = string
  default     = ""
}
