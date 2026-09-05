variable "resource_type" {
  description = "Logical resource type key to name (e.g. \"resource_group\", \"storage_account\"). Must be a key in the resource_types map in locals.tf."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

variable "region" {
  description = "Full Azure region name (e.g. \"eastus2\"). Must be a key in the region_abbreviations map in locals.tf."
  type        = string
}

variable "instance" {
  description = "Zero-padded 3-digit instance number, e.g. \"001\", distinguishing multiple resources of the same type/environment/region."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{3}$", var.instance))
    error_message = "instance must be a 3-digit zero-padded number, e.g. \"001\"."
  }
}

variable "workload" {
  description = "Workload/application token. Defaults to \"fc\" (FullCode); override only for cross-workload shared resources."
  type        = string
  default     = "fc"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.workload))
    error_message = "workload must be lowercase alphanumeric."
  }
}
