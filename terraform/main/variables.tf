variable "project" {
  type    = string
  default = "devopspy"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "newzealandnorth"
}

variable "office_ip" {
  type        = string
  description = "The static IP from Azure DevOps Library"
}
