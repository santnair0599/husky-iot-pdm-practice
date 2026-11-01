# Security and access

The principles used in Dev:

1. **No stored Azure credentials in CI.** GitHub Actions uses OIDC ([cicd.md](cicd.md#authentication-oidc-no-stored-azure-secret)).
2. **Least privilege per identity.** Each identity gets only the data access its job needs, scoped to a container or database where possible.
3. **The deployer can't grant itself data access.** Grants that widen the deployer's data access are made by a human admin, outside the pipeline, and recorded in Git ([`infra/manual-grants.md`](../infra/manual-grants.md), [`synapse/00_grant_deployer.sql`](../synapse/00_grant_deployer.sql)). One exception is documented under [known gaps](#known-gaps).
4. **No SQL or storage passwords in any release.** Synapse uses Entra-only authentication, and the SQL deploy script rejects password, master-key and secret statements.

## Identities and what they can do

### Human administrator

The project owner signs in as an Entra guest account.

| Scope | Access | Source |
|---|---|---|
| ADX cluster | `AllDatabasesAdmin` | Terraform `azurerm_kusto_cluster_principal_assignment.admin` |
| Synapse | Entra admin of the workspace | Azure portal |
| Subscription | runs bootstrap Terraform and the one-time grants below | outside this repo |

### GitHub deployer: `sp-husky-pdm-dev`

| Plane | Scope | Access | Why | How it was granted |
|---|---|---|---|---|
| Azure RBAC | `rg-husky-pdm-dev` | `Contributor` | create and update Dev resources | one-time setup (Lesson 18A) |
| Azure RBAC | container `tfstate-dev` | `Storage Blob Data Contributor` | read and write Terraform state | one-time setup |
| Azure RBAC | container `raw` | `Storage Blob Data Reader` | integration test reads the archived test message | manual, 19C ([`manual-grants.md`](../infra/manual-grants.md)) |
| ADX data plane | database `pdm_dev` only | `Admin` | deploy tables, functions, policies, exports | Terraform `azurerm_kusto_database_principal_assignment.deployer`, through the approved workflow (run `41287480751`) |
| Synapse SQL | database `HuskyPDMDev` | 6 grants, listed below, **no `db_owner`** | deploy and test the reporting views | manual, 19B ([`00_grant_deployer.sql`](../synapse/00_grant_deployer.sql)) |

The deployer's Synapse grants, as verified with `sys.database_permissions` on 2026-11-01:

| Permission | Scope | Purpose |
|---|---|---|
| `CONNECT` | database | sign in |
| `CREATE VIEW` | database | create new views |
| `ALTER` | schema `pdm` | change objects in `pdm` only |
| `SELECT` | schema `pdm` | lets the tests read the views |
| `ADMINISTER DATABASE BULK OPERATIONS` | database | `OPENROWSET` over the lake |
| `REFERENCES` | credential `HuskyLakeIdentity` | **use** the lake credential, not change it |

`Contributor` does **not** include `Microsoft.Authorization/roleAssignments/write`, so the deployer can't give itself storage roles. It can't create Synapse logins or grants either, because those are SQL data-plane operations.

### Managed identities (resource to resource, no keys)

| Identity | Access | Used for | Defined in |
|---|---|---|---|
| IoT Hub `iot-husky-pdm-dev-0599` | `Storage Blob Data Contributor` on `raw` | archive route writes JSON | [`routing.tf`](../infra/terraform/envs/dev/routing.tf) |
| ADX cluster `adxhuskypdmdev0599` | `Storage Blob Data Contributor` on `curated` | continuous export writes Parquet | [`adx_export.tf`](../infra/terraform/envs/dev/adx_export.tf) |
| Synapse workspace | `Storage Blob Data Contributor` on `synapse`; `Storage Blob Data Reader` on `curated` | workspace file system; views read Parquet through `HuskyLakeIdentity` | [`synapse.tf`](../infra/terraform/envs/dev/synapse.tf) |

Each grant is scoped to a single **container**, not the storage account. So the Synapse identity can read `curated` but not `raw`, and ADX can write `curated` but not `raw`.

### Other principals

| Principal | Access | Note |
|---|---|---|
| `pbi-analyst@…onmicrosoft.com` (tenant user) | ADX `Viewer` on `pdm_dev` | Created by hand for Power BI, because Power BI rejected the guest account. **Not in Terraform yet.** |
| Test device `IMM-900` | send telemetry only | Its own device key, so it can be revoked without touching `IMM-001`. Created by hand; azurerm has no IoT device resource. |

## Secrets and configuration

| Name | Type (GitHub `dev` environment) | Contains | Exposure control |
|---|---|---|---|
| `ALERT_EMAIL` | secret | alert recipient | Terraform variable marked `sensitive` |
| `IOTHUB_DEVICE_CONNECTION_STRING` | secret | IMM-900 device key | piped straight from `az` into `gh secret set`, never displayed; passed only to the "Send test telemetry" step; GitHub masks it in logs |
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | variables | identifiers, not credentials | |
| `ADX_*`, `SYNAPSE_SQL_*`, `ADLS_ACCOUNT_NAME`, `TEST_DEVICE_ID`, `TF_*` | variables | names and endpoints | |

Run `41313214638` was checked after the fact: none of its 1,019 log lines contains `SharedAccessKey=`.

Git ignores `*.tfvars`, `*.tfstate*`, `*.tfplan`, `.env*`, `*.pem`, `*.pfx` and `*.key` ([`.gitignore`](../.gitignore)).

Terraform state is stored with shared-key access **disabled** on the state account. Only Entra-authenticated identities can read it.

## Known gaps

These are deliberate lab shortcuts or open findings. Lessons 1–19 did not fix them.

| Gap | Risk | Suggested fix |
|---|---|---|
| **The deployer could raise its own ADX rights through Terraform.** `Contributor` includes writing `Microsoft.Kusto/.../principalAssignments`, the control-plane resource that grants ADX data access. | A Terraform change could give the deployer (or anyone) more ADX access. Today the only control is the human reviewer in the approved workflow. | A plan check that fails on new `azurerm_kusto_*principal_assignment` resources, or a custom role without `principalAssignments/write`. |
| Synapse firewall rule `allowAll` (0.0.0.0–255.255.255.255) and public network access | The SQL endpoint is reachable from any IP (Entra sign-in is still required). | Restrict to known IPs, or use a private endpoint. |
| ADX data connection uses IoT Hub shared access policy `adx-reader` | a key-based secret inside Azure | Managed-identity data connection. |
| Lake storage account allows shared-key access (the default; not disabled in [`main.tf`](../infra/terraform/envs/dev/main.tf)) | an account key bypasses RBAC | `shared_access_key_enabled = false`, after checking that every consumer uses Entra. |
| ADX, IoT Hub and storage have public endpoints | no network isolation | Private endpoints (beyond a Dev lab budget). |
| Manual principals: `pbi-analyst`, `IMM-900`, the deployer's `raw` reader and Synapse grants | can drift without anyone noticing | Bring them into Terraform where a resource exists, and periodically compare the others with [`manual-grants.md`](../infra/manual-grants.md). |
| The deployer also has an older ADX `Viewer` assignment, observed 2026-11-01 next to `Admin` | redundant, and not in code | Remove it once confirmed unused. |
