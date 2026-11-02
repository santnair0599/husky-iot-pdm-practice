variable "environment" {
  description = "Must be test: this root can only ever describe the Test environment"
  type        = string
  default     = "test"

  validation {
    condition     = var.environment == "test"
    error_message = "envs/test only deploys the test environment."
  }
}

variable "resource_group_name" {
  description = "Existing Test resource group (created by the admin, not by this configuration)"
  type        = string

  validation {
    condition     = endswith(var.resource_group_name, "-test")
    error_message = "resource_group_name must end with -test."
  }
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string

  validation {
    condition     = can(regex("test", var.storage_account_name)) && !can(regex("dev|prod", var.storage_account_name))
    error_message = "storage_account_name must contain 'test' and not 'dev' or 'prod'."
  }
}

variable "iot_hub_name" {
  type = string

  validation {
    condition     = can(regex("-test-", var.iot_hub_name)) && !can(regex("dev|prod", var.iot_hub_name))
    error_message = "iot_hub_name must contain '-test-' and not 'dev' or 'prod'."
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
    condition     = can(regex("test", var.adx_cluster_name)) && !can(regex("dev|prod", var.adx_cluster_name))
    error_message = "adx_cluster_name must contain 'test' and not 'dev' or 'prod'."
  }
}

variable "adx_database_name" {
  type    = string
  default = "pdm_test"

  validation {
    condition     = var.adx_database_name == "pdm_test"
    error_message = "The Test ADX database is pdm_test."
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
    condition     = can(regex("-test-", var.synapse_workspace_name)) && !can(regex("dev|prod", var.synapse_workspace_name))
    error_message = "synapse_workspace_name must contain '-test-' and not 'dev' or 'prod'."
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
  description = "create while Test has its own Synapse; none after the Test workspace is retired (subscription limit: 2 Synapse workspaces)"
  type        = string
  default     = "create"

  validation {
    condition     = contains(["create", "none"], var.synapse_mode)
    error_message = "Test uses create, or none once its Synapse workspace is retired."
  }
}
