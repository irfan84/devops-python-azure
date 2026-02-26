variable "project" {
  type    = string
  default = "devopspy"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "office_ip" {
  type        = string
  description = "The static IP from Azure DevOps Library"
}


variable "location" {
  type    = string
  default = "newzealandnorth"
}