variable "backup_project_id" { type = string }
variable "source_project_id" {
  type    = string
  default = "mc-v4-prod"
}
variable "source_bucket" {
  type    = string
  default = "mc-v4-prod.appspot.com"
}
variable "backup_bucket" { type = string } # globally unique
variable "backup_location" {
  type    = string
  default = "us-central1"
}
variable "backup_storage_class" {
  type    = string
  default = "NEARLINE"
}
variable "retention_days" {
  type    = number
  default = 30
}
variable "schedule_start_date" {
  type = object({ year = number, month = number, day = number })
}
variable "tf_operators" {
  # Principals allowed to IMPERSONATE the operator SA (keyless) — their ONLY
  # standing access. e.g. ["user:tubig.jlu@gmail.com"].
  type    = list(string)
  default = []
}
