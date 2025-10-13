# On-Prem K3s Module - Variables

variable "cluster_name" {
  description = "Name of the K3s cluster"
  type        = string
}

variable "server_ips" {
  description = "List of server IP addresses for K3s control plane"
  type        = list(string)
}

variable "agent_ips" {
  description = "List of agent IP addresses for K3s workers (optional)"
  type        = list(string)
  default     = []
}

variable "k3s_version" {
  description = "K3s version"
  type        = string
  default     = "v1.28.3+k3s1"
}

variable "k3s_token" {
  description = "K3s cluster token (shared secret)"
  type        = string
  sensitive   = true
}

variable "ssh_user" {
  description = "SSH user for server access"
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}

variable "enable_ha" {
  description = "Enable HA mode (requires 3+ servers)"
  type        = bool
  default     = true
}

variable "install_longhorn" {
  description = "Install Longhorn storage"
  type        = bool
  default     = true
}

variable "install_metallb" {
  description = "Install MetalLB load balancer"
  type        = bool
  default     = true
}

variable "metallb_ip_range" {
  description = "IP range for MetalLB (e.g., 192.168.1.100-192.168.1.110)"
  type        = string
  default     = ""
}
