variable "environment" {
  description = "Deployment environment (dev, test, prod)."
  type        = string
}

variable "region" {
  description = "Full Azure region name, e.g. \"eastus2\"."
  type        = string
}

variable "instance" {
  description = "Zero-padded instance number, e.g. \"001\"."
  type        = string
  default     = "001"
}

variable "tags" {
  description = "Tags to apply to the resource group."
  type        = map(string)
  default     = {}
}
