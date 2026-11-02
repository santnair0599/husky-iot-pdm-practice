variable "environment" {
  description = "Must be prod: this root can only ever describe the Prod environment"
  type        = string
  default     = "prod"

  validation {
    condition     = var.environment == "prod"
    error_message = "envs/prod only deploys the prod environment."
  }
}

variable "resource_group_name" {
  description = "Existing Prod resource group (created by the admin, not by this configuration)"
  type        = string

  validation {
    condition     = endswith(var.resource_group_name, "-prod")
    error_message = "resource_group_name must end with -prod."
  }
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string

  validation {
    condition     = can(regex("prod", var.storage_account_name)) && !can(regex("dev|test", var.storage_account_name))
    error_message = "storage_account_name must contain 'prod' and not 'dev' or 'test'."
  }
}

variable "iot_hub_name" {
  type = string

  validation {
    condition     = can(regex("-prod-", var.iot_hub_name)) && !can(regex("dev|test", var.iot_hub_name))
    error_message = "iot_hub_name must contain '-prod-' and not 'dev' or 'test'."
  }
}

variable "iot_hub_sku" {
  description = "Only one F1 (free) hub is allowed per subscription, and Dev uses it"
  type        = string
  default     = "B1"

  validation {
    condition     = var.iot_hub_sku != "F1"
    error_message = "F1 is taken by Dev (one free hub per subscription)."
  }
}

variable "adx_cluster_name" {
  type = string

  validation {
    condition     = can(regex("prod", var.adx_cluster_name)) && !can(regex("dev|test", var.adx_cluster_name))
    error_message = "adx_cluster_name must contain 'prod' and not 'dev' or 'test'."
  }
}

variable "adx_database_name" {
  type    = string
  default = "pdm_prod"

  validation {
    condition     = var.adx_database_name == "pdm_prod"
    error_message = "The Prod ADX database is pdm_prod."
  }
}

variable "create_data_connection" {
  description = "false for the first apply, true after the KQL release has created Telemetry_Raw"
  type        = bool
  default     = true
}

variable "synapse_workspace_name" {
  type = string

  validation {
    condition     = can(regex("-prod-", var.synapse_workspace_name)) && !can(regex("dev|test", var.synapse_workspace_name))
    error_message = "synapse_workspace_name must contain '-prod-' and not 'dev' or 'test'."
  }
}

variable "synapse_location" {
  type = string
}

variable "synapse_managed_resource_group_name" {
  description = "Leave null on first create; never reuse Dev's managed resource group"
  type        = string
  default     = null

  validation {
    condition     = var.synapse_managed_resource_group_name == null ? true : !can(regex("3749825f", var.synapse_managed_resource_group_name))
    error_message = "That is Dev's Synapse managed resource group."
  }
}

variable "alert_email" {
  type      = string
  sensitive = true
}

variable "synapse_mode" {
  description = "none until the ADMIN has created the Synapse workspace, then existing. Prod never lets Terraform create it."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["existing", "none"], var.synapse_mode)
    error_message = "Prod's Synapse workspace is created by an admin: use none or existing, never create."
  }
}
