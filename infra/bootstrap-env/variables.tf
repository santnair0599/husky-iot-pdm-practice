variable "environment" {
  description = "Environment to bootstrap"
  type        = string

  validation {
    condition     = contains(["test", "prod"], var.environment)
    error_message = "environment must be test or prod (Dev was bootstrapped by hand in Lesson 18A)."
  }
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "github_repository_subject" {
  description = "owner@owner_id/repo@repo_id, matching the immutable-ID OIDC subject used by Dev"
  type        = string
  default     = "santnair0599@31506535/husky-iot-pdm-practice@1427372824"
}

variable "state_resource_group_name" {
  type    = string
  default = "rg-husky-pdm-tfstate"
}

variable "state_storage_account_name" {
  type    = string
  default = "sthpdm5mljzdg5"
}
