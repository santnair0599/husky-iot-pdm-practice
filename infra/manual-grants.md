# One-time manual grants (run by a human admin, never by the pipeline)

The deployer `sp-husky-pdm-dev` has Contributor, which cannot grant roles.
Anything that gives it extra data access is done by hand and recorded here.

| Grant | Why | Lesson |
|---|---|---|
| ADX `Admin` on `pdm_dev` | deploy KQL | 19A (Terraform: `azurerm_kusto_database_principal_assignment.deployer`) |
| Synapse login + 6 grants in `HuskyPDMDev` | deploy views | 19B (`synapse/00_grant_deployer.sql`) |
| `Storage Blob Data Reader` on container `raw` | archive test reads the test message | 19C |
| IoT device `IMM-900` + secret `IOTHUB_DEVICE_CONNECTION_STRING` | dedicated test sender | 19C |