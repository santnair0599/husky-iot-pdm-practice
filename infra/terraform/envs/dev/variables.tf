
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
