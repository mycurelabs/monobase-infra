# AWS EKS Cluster - Variable Declarations

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region (e.g., us-east-1, us-west-2, eu-west-1)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (leave empty for auto-detection)"
  type        = list(string)
  default     = []
}

variable "enable_public_endpoint" {
  description = "Enable public API endpoint"
  type        = bool
  default     = true
}

variable "api_access_cidrs" {
  description = "CIDR blocks allowed to access EKS API"
  type        = list(string)
  default     = ["0.0.0.0/0"] # CHANGE IN PRODUCTION
}

variable "deployment_profile" {
  description = "Deployment size: small (1-5 clients), medium (5-15), large (15+)"
  type        = string
  default     = "small"
}

variable "node_groups" {
  description = "Custom node group config (leave empty to use deployment_profile)"
  type = map(object({
    instance_types = list(string)
    desired_size   = number
    max_size       = number
    min_size       = number
    disk_size      = optional(number, 100)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {}
}

variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI driver (required for storage)"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "velero_backup_bucket" {
  description = "S3 bucket for Velero backups (scopes IAM permissions)"
  type        = string
  default     = ""
}

variable "route53_zone_arns" {
  description = "Route53 zone ARNs for cert-manager (scopes IAM permissions)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
