
resource "azurerm_role_assignment" "iot_raw_writer" {
  scope = azurerm_storage_container.lake["raw"].id

  role_definition_name = "Storage Blob Data Contributor"

  principal_id = azurerm_iothub.pdm.identity[0].principal_id

  principal_type = "ServicePrincipal"
}


resource "azurerm_iothub_endpoint_storage_container" "raw" {
  name                = "raw-telemetry"
  resource_group_name = azurerm_resource_group.pdm.name
  iothub_id           = azurerm_iothub.pdm.id

  container_name = azurerm_storage_container.lake["raw"].name

  authentication_type = "identityBased"
  endpoint_uri        = azurerm_storage_account.lake.primary_blob_endpoint

  encoding                   = "JSON"
  batch_frequency_in_seconds = 60
  max_chunk_size_in_bytes    = 10485760

  file_name_format = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"

  depends_on = [
    azurerm_role_assignment.iot_raw_writer
  ]
}


resource "azurerm_iothub_route" "archive" {
  name                = "route-raw-archive"
  resource_group_name = azurerm_resource_group.pdm.name
  iothub_name         = azurerm_iothub.pdm.name

  source    = "DeviceMessages"
  condition = "true"
  endpoint_names = [
    azurerm_iothub_endpoint_storage_container.raw.name
  ]

  enabled = true
}


resource "azurerm_iothub_route" "live" {
  name                = "route-live-events"
  resource_group_name = azurerm_resource_group.pdm.name
  iothub_name         = azurerm_iothub.pdm.name

  source         = "DeviceMessages"
  condition      = "true"
  endpoint_names = ["events"]

  enabled = true
}


