variable "environment" {
  description = "Environment name used in resource names and tags (test, prod)"
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group, created by the admin bootstrap (infra/bootstrap-env)"
  type        = string
}

variable "location" {
  description = "Region for everything except Synapse"
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique ADLS Gen2 account name (3-24 lowercase letters and digits)"
  type        = string
}

variable "iot_hub_name" {
  description = "Globally unique IoT Hub name"
  type        = string
}

variable "iot_hub_sku" {
  description = "IoT Hub tier. Only one F1 (free) hub is allowed per subscription, and Dev uses it."
  type        = string
  default     = "B1"
}

variable "adx_cluster_name" {
  description = "Globally unique ADX cluster name (max 22 characters)"
  type        = string
}

variable "adx_sku_name" {
  description = "ADX SKU. The Dev SKU has no SLA and is billed for compute only."
  type        = string
  default     = "Dev(No SLA)_Standard_E2a_v4"
}

variable "adx_database_name" {
  description = "ADX database name, e.g. pdm_test"
  type        = string
}

variable "create_data_connection" {
  description = "Create the IoT Hub -> ADX data connection. False on a new environment until the KQL release has created Telemetry_Raw and its mapping."
  type        = bool
  default     = true
}

variable "synapse_mode" {
  description = "create (Terraform creates Synapse), existing (an admin created it; Terraform reads it) or none (not yet)"
  type        = string
  default     = "create"

  validation {
    condition     = contains(["create", "existing", "none"], var.synapse_mode)
    error_message = "synapse_mode must be create, existing or none."
  }
}

variable "synapse_workspace_name" {
  description = "Globally unique Synapse workspace name"
  type        = string
}

variable "synapse_location" {
  description = "Region for Synapse (eastus2 SQL provisioning is restricted for this subscription)"
  type        = string
}

variable "synapse_managed_resource_group_name" {
  description = "Leave null on first create so Azure names it; set it afterwards only if Terraform shows a change"
  type        = string
  default     = null
}

variable "synapse_firewall_ip_ranges" {
  description = <<-EOT
    Permanent Synapse firewall rules, as name => { start, end }. Default: none.
    GitHub-hosted runners have no fixed IPs, so the release workflow adds a rule
    for its own IP at the start of a run and removes it at the end. Those
    temporary rules are not managed here, so they never show up as drift.
  EOT
  type = map(object({
    start = string
    end   = string
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.synapse_firewall_ip_ranges) : !(r.start == "0.0.0.0" && r.end == "255.255.255.255")])
    error_message = "An allow-all Synapse firewall rule is not permitted; add specific ranges."
  }
}

variable "alert_email" {
  description = "Alert recipient. Comes from a GitHub secret; never commit it."
  type        = string
  sensitive   = true
}

variable "log_daily_quota_gb" {
  description = "Log Analytics daily ingestion cap (cost guard)"
  type        = number
  default     = 0.1
}
