
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique storage account name"
  type        = string
}

variable "iot_hub_name" {
  description = "Globally unique IoT Hub name"
  type        = string
}


variable "adx_cluster_name" {
  description = "Globally unique ADX cluster name"
  type        = string
}

variable "adx_admin_object_id" {
  description = "Entra object ID of the human/group given AllDatabasesAdmin on the ADX cluster"
  type        = string
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
  description = "Managed RG Azure created for the workspace; must match or Terraform replaces the workspace"
  type        = string
}
