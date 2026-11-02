# Test environment (Lesson 18C-T)

> **Status (2026-11-02): deployed and accepted. Test Synapse has since been retired, so Test is now ADX-only.**
> - **Accepted:** 13 of 13 integration tests passed in run `41401561043` (commit `86fad6d`), tagged **`test-passed-2026-11-02`**. Prod promotes exactly that release ([prod-environment.md](prod-environment.md)).
> - **Retired:** the Test Synapse workspace was removed through a reviewed, saved Terraform plan (3 deletions) to free the subscription's Synapse quota (2 workspaces) for Prod. The follow-up run `41428063618` showed **No changes**. See [test-synapse-retirement.md](test-synapse-retirement.md).
> - **Now:** `deploy-app-test.yml` works with **`kql-only`** only. `kql-sql` and `full` need Synapse again (rebuild steps are in the retirement doc). ADX, IoT Hub, storage and monitoring remain. GitHub variable `TF_SYNAPSE_MODE=none`.
> - **Reconciliation has NOT been verified** in Test or anywhere else.

## Evidence

| Run | Workflow | Commit | Result | What it proved |
|---|---|---|---|---|
| `41329005231` | approved Terraform | `96e6726` | success | OIDC; `OK: Test identity cannot access rg-husky-pdm-dev`; 23 added via the exact saved plan; post-apply no-change |
| `41329123385` | approved Terraform | `96e6726` | success | follow-up run: no changes, so approval and apply skipped |
| `41338201298` | one-time Synapse handover | `77d6c52` | success | human admin granted Synapse Administrator (workflow deleted in PR #3) |
| `41340635265`, `41341166102` | app `kql-only` | `ab2f363` | failure | export refused: the managed identity policy and the cluster identity's Viewer role were missing |
| `41341600305` | app `kql-only` | `ab2f363` | success | KQL deployed; re-run skipped 11/12; `5 passed` |
| `41394765861` | approved Terraform | `ab2f363` | failure | the ADX-stopped check worked as designed |
| `41396226090` | approved Terraform | `ab2f363` | success | IoT Hub → ADX data connection: 1 added |
| `41397526409` | app `kql-sql` | `ab2f363` | failure | Synapse deployed with the deployer's 6 grants; the lake-read check failed because the lake was empty (found the step-order issue, PR #4) |
| `41399028829`, `41400247069` | app `full` | `ab2f363`, `bbaf7a6` | failure | found the step-order issue (PR #4) and the empty-lake wait bug (PR #5) |
| **`41401561043`** | **app `full`** | **`86fad6d`** | **success** | **13 of 13**: Bronze 337 s, Quarantine, raw archive, Parquet → Synapse 253 s, views read the lake |
| `41407963105` | approved Terraform | `a470b89` | success | module `synapse_mode` change: 3 moved, 0 added/changed/destroyed |
| — (admin, local saved plan) | Synapse retirement | `eba97f2` | success | `0 added, 0 changed, 3 destroyed` (workspace + 2 roles), plan reviewed first |
| `41428063618` | approved Terraform | `eba97f2` | success | after retirement: **No changes** |

The logs are saved outside the repo in `C:\dev\azure\husky-evidence\test\`. The release file hashes are in [test-synapse-retirement.md](test-synapse-retirement.md#release-file-hashes-at-test-passed-2026-11-02).

**Steps the original plan below didn't include, all discovered here:**
- the cluster's system identity must be **Viewer** on `pdm_test`
- the pipeline-created Synapse workspace made the deployer its only Synapse Administrator and Entra SQL admin, which needed the one-time handover; the serverless SQL login needed Synapse RBAC, not just the SQL admin setting
- the empty-lake behaviour, error 13807

Prod handles all three by design ([prod-environment.md § Problems](prod-environment.md#problems-found-in-the-real-deployments)).

Test reuses the verified Dev design through a Terraform module, with stronger isolation than Dev:

| | Dev (existing) | Test (this lesson) |
|---|---|---|
| Terraform | `envs/dev`, resources written inline | `envs/test` → `modules/pdm_platform` |
| State | `tfstate-dev/husky-dev.tfstate` | `tfstate-test/husky-test.tfstate` |
| Deployer | `sp-husky-pdm-dev`, built-in **Contributor** | `sp-husky-pdm-test`, **custom role**: Contributor minus ADX and Synapse admin grants |
| Role assignments for managed identities | created by a human's local apply | created by the pipeline through **constrained delegation**: only 2 blob roles, only to service principals, never to itself |
| GitHub environments | `dev`, `dev-approval` | `test`, `test-approval` |
| Resource group | managed by Dev Terraform | created by the admin bootstrap; Test Terraform only reads it |
| IoT Hub | F1 (free) | **B1**: only one free hub is allowed per subscription |
| Synapse firewall | permanent `allowAll` (0.0.0.0–255.255.255.255) | **no permanent rule**. `deploy-app-test.yml` adds `gh-run-<run>-<attempt>` for the runner's own IP and always removes it at the end. The module rejects an allow-all range. Admins add a temporary rule for their IP: `az synapse workspace firewall-rule create --name admin-<date> --workspace-name syn-husky-pdm-test-0599 --resource-group rg-husky-pdm-test --start-ip-address <ip> --end-ip-address <ip>`, then delete it afterwards. |
| Plan guards | blocks deletes | blocks deletes, admin-only resource types, role assignments outside the 2 blob roles, and self-grants |
| Provenance | checksum + commit | checksum + `provenance.json` (commit, run, environment, state), all checked before apply |
| After apply | `state list` | **no-change plan must pass**, then `state list` and outputs |

## Isolation: why Test can't touch Dev or Prod

1. **Identity.** The `test` GitHub environment trusts only `sp-husky-pdm-test`. Its federated credential subject ends in `:environment:test`. Its roles cover only `rg-husky-pdm-test` and the `tfstate-test` container. Every plan job proves this at runtime: "Prove identity isolation" fails the run if the identity can read `rg-husky-pdm-dev`.
2. **Code.** `envs/test` variables reject names that don't contain `test`, and the resource group must end with `-test`. Both workflows have a "Target guard" step that rejects any value containing `dev` or `prod`.
3. **State.** A different container and key. The Test identity has no access to `tfstate-dev`.
4. **Concurrency.** Separate groups (`husky-terraform-test`, `husky-app-test`).

## Files

| File | Purpose |
|---|---|
| [`infra/terraform/modules/pdm_platform/`](../infra/terraform/modules/pdm_platform) | reusable platform: lake, IoT Hub with dual routing, ADX, Synapse, monitoring, managed-identity blob roles |
| [`infra/terraform/envs/test/`](../infra/terraform/envs/test) | Test root: resource group data source, module call, name guards, `terraform.tfvars.example` |
| [`infra/bootstrap-env/`](../infra/bootstrap-env) | **admin-only**, local state, one workspace per environment: resource group, deployer app + OIDC credential, custom role, state access, constrained RBAC delegation |
| [`.github/workflows/deploy-test-approved.yml`](../.github/workflows/deploy-test-approved.yml) | plan → guards → provenance → `test-approval` → exact apply → post-apply no-change plan; a run with no changes skips approval and apply |
| [`.github/workflows/deploy-app-test.yml`](../.github/workflows/deploy-app-test.yml) | generated from `deploy-app-dev.yml`; identical except name, environment, concurrency and a target guard |
| [`synapse/00_bootstrap_test.sql`](../synapse/00_bootstrap_test.sql) | admin-only Synapse setup: database, lake credential, deployer login and the same 6 grants as Dev |

No changes were needed in `scripts/` or `tests/`. They already read every endpoint from environment variables.

Dev isn't migrated to the module yet. That needs `moved` blocks and a proven no-change plan, so it's a separate, later step.

## Deployment order

**Admin** = you, on a laptop, with Owner rights. **Pipeline** = GitHub Actions as `sp-husky-pdm-test`.

| # | Who | Step | Creates paid resources? |
|---|---|---|---|
| 1 | Admin | `infra/bootstrap-env`: `terraform workspace new test`, then plan, review and apply with `-var environment=test`. **As executed:** the manual route instead: the app and credential in the portal, the resource group and roles via `az` using [`infra/roles/`](../infra/roles) (the custom role JSON and the role-grant condition). | no (resource group, app, roles) |
| 2 | Admin | GitHub: create environments `test` (branch policy `main`) and `test-approval` (required reviewer); set the variables and `ALERT_EMAIL` secret listed below; `TF_CREATE_DATA_CONNECTION=false` | no |
| 3 | Pipeline | `deploy-test-approved.yml`: review the plan, approve, apply | **yes**: ADX, IoT Hub B1, Synapse, storage, Log Analytics |
| 4 | Admin | ADX: add yourself as `AllDatabasesAdmin`, add the deployer as `Admin` on `pdm_test`, **remove the deployer's automatic creator rights**, allow the system managed identity for continuous export (commands below) | no |
| 5 | Admin | Synapse: set yourself as Entra SQL admin, **remove the deployer's automatic Synapse Administrator role**, run `synapse/00_bootstrap_test.sql` | no |
| 6 | Pipeline | `deploy-app-test.yml`, scope `kql-only`: creates tables, mapping, functions, policies and export | no |
| 7 | Admin + Pipeline | set `TF_CREATE_DATA_CONNECTION=true`, then run `deploy-test-approved.yml` (expect 1 to add: the data connection) | no |
| 8 | Admin | IoT device `IMM-900` in the Test hub → secret `IOTHUB_DEVICE_CONNECTION_STRING`; `TEST_DEVICE_ID=IMM-900`; `Storage Blob Data Reader` on Test `raw` for the deployer | no |
| 9 | Pipeline | `deploy-app-test.yml`, scope `full`: end-to-end acceptance | no |
| 10 | Pipeline | `deploy-test-approved.yml` again: expect "No changes", with approval and apply skipped | no |
| 11 | Admin | stop the Test ADX cluster | — |

Why step 7 exists: an ADX data connection can only be created after its table and mapping exist, and in Test those are created by the release pipeline (step 6), not by Terraform.

### GitHub `test` environment

| Variables | Value |
|---|---|
| `AZURE_CLIENT_ID` | from bootstrap output `AZURE_CLIENT_ID` |
| `DEPLOYER_OBJECT_ID` | from bootstrap output `deployer_object_id` |
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | same as Dev |
| `TF_STATE_ACCOUNT` / `TF_STATE_CONTAINER` / `TF_STATE_KEY` | `sthpdm5mljzdg5` / `tfstate-test` / `husky-test.tfstate` (container and key are also fixed in the workflow and must match) |
| `TF_RESOURCE_GROUP_NAME` | `rg-husky-pdm-test` |
| `TF_LOCATION` / `TF_SYNAPSE_LOCATION` | `eastus2` / `centralus` |
| `TF_STORAGE_ACCOUNT_NAME`, `ADLS_ACCOUNT_NAME` | `sthuskypdmtest0599` |
| `TF_IOT_HUB_NAME` | `iot-husky-pdm-test-0599` |
| `TF_ADX_CLUSTER_NAME` | `adxhuskypdmtest0599` |
| `ADX_CLUSTER_URI` / `ADX_DATABASE` | `https://adxhuskypdmtest0599.eastus2.kusto.windows.net` / `pdm_test` |
| `TF_SYNAPSE_WORKSPACE_NAME` | `syn-husky-pdm-test-0599` |
| `SYNAPSE_SQL_SERVER` / `SYNAPSE_SQL_DATABASE` | `syn-husky-pdm-test-0599-ondemand.sql.azuresynapse.net` / `HuskyPDMTest` |
| `TF_CREATE_DATA_CONNECTION` | `false`, then `true` at step 7 |
| `TEST_DEVICE_ID` | `IMM-900` (step 8) |
| **Secrets:** `ALERT_EMAIL`, `IOTHUB_DEVICE_CONNECTION_STRING` (step 8) | |

All names were checked as available on 2026-11-01.

### Admin commands for steps 4 and 8

```powershell
$rg = "rg-husky-pdm-test"; $adx = "adxhuskypdmtest0599"; $tenant = "874dd38d-b50f-40f3-9c7d-8c1342244a1d"
$me = az ad signed-in-user show --query id -o tsv
$deployerClientId = "<AZURE_CLIENT_ID from bootstrap>"

# 4a. You as cluster admin; the deployer as admin of ONE database
az kusto cluster-principal-assignment create --cluster-name $adx --resource-group $rg --principal-assignment-name adx-admin --principal-id $me --principal-type User --role AllDatabasesAdmin --tenant-id $tenant
az kusto database-principal-assignment create --cluster-name $adx --resource-group $rg --database-name pdm_test --principal-assignment-name github-deployer-admin --principal-id $deployerClientId --principal-type App --role Admin --tenant-id $tenant

# 4b. ADX gives the CREATOR of a cluster/database admin rights automatically. List and remove the deployer's:
az kusto cluster-principal-assignment list --cluster-name $adx --resource-group $rg -o table
az kusto database-principal-assignment list --cluster-name $adx --resource-group $rg --database-name pdm_test -o table
# then: az kusto cluster-principal-assignment delete ... --principal-assignment-name <name of the deployer's entry>
```
```kql
// 4c. In Data Explorer as yourself: let the continuous export use the system identity
.show cluster policy managed_identity
.alter-merge cluster policy managed_identity ```[{"ObjectId": "system", "AllowedUsages": "AutomatedFlows"}]```
```
```powershell
# 8. Test device, secret (never displayed) and archive read access
az iot hub device-identity create --hub-name iot-husky-pdm-test-0599 --device-id IMM-900 --output none
az iot hub device-identity connection-string show --hub-name iot-husky-pdm-test-0599 --device-id IMM-900 --query connectionString -o tsv | gh secret set IOTHUB_DEVICE_CONNECTION_STRING -e test
gh variable set TEST_DEVICE_ID -e test -b "IMM-900"
$storageId = az storage account show --name sthuskypdmtest0599 --resource-group $rg --query id -o tsv
az role assignment create --assignee $deployerClientId --role "Storage Blob Data Reader" --scope "$storageId/blobServices/default/containers/raw"
```

## Acceptance criteria and evidence

| # | Criterion | Evidence | Result |
|---|---|---|---|
| 1 | Test uses its own state | plan log: init with `tfstate-test`/`husky-test.tfstate`; `provenance.json` | ✅ `41329005231` |
| 2 | Its own identity and scope | `OK: Test identity cannot access rg-husky-pdm-dev` | ✅ every infra run |
| 3 | OIDC works | "Azure OIDC Login" with the Test client ID | ✅ |
| 4 | Approval required | run waits at `test-approval` until approved | ✅ approved by `santnair0599` (**self-approval**) |
| 5 | Exact-plan apply | `test.tfplan: OK` and "Provenance OK", then apply | ✅ `41329005231`, `41396226090` |
| 6 | ADX and Synapse objects | Verify KQL objects `5 passed`; Synapse views exist and read the lake | ✅ `41341600305`, `41401561043` |
| 7 | Bronze / Silver / Quarantine | Verify Bronze and Silver; Verify quarantine | ✅ `41401561043` |
| 8 | Archive and Synapse reporting | Verify raw archive; Verify Synapse historical export | ✅ `41401561043` |
| 9 | Dev not modified | identity isolation (criterion 2) | ✅ by isolation. A direct Dev no-change gate run was **not** done after the Test deployment. |
| 10 | Subsequent no-change | "Post-apply plan: No changes"; follow-up run skips approval and apply | ✅ `41329123385`, `41428063618` |
| 11 | **Reconciliation** (Bronze = Silver + Quarantine) | — | ❌ **NOT VERIFIED**. `test_data_health.py` is an uncommitted draft that has never passed. |

## Estimated cost

Prices are Azure retail list prices, queried on 2026-11-01 from `prices.azure.com`. Actual bills depend on uptime, region pricing and any discounts.

| Resource | Price | Billed while stopped/idle? |
|---|---|---|
| ADX `Dev(No SLA)_Standard_E2a_v4`, 1 instance | E2a v4 Linux compute **$0.126/hour** (eastus2). Microsoft states the Dev SKU carries no ADX markup; the standard markup in the price list is $0.11/hour. | compute stops when the cluster is stopped; storage continues (cents) |
| IoT Hub B1 | **$10 per month** | **yes**: billed as long as the hub exists |
| Synapse serverless | $5 per TB scanned; these tests scan about 1 MB | no |
| Storage (LRS, small) | cents per month | yes (negligible) |
| Log Analytics | capped at 0.1 GB/day | only on ingestion |
| 2 metric alerts | about $0.10 per alert per month | yes (negligible) |

| Scenario | Estimate |
|---|---|
| One week, ADX running about 10 h in total, then tear down | **about $4–5** (B1 about $2.30 + ADX about $1.30 + the rest under $1) |
| Keep Test for a month, ADX running about 10 h | about $12–15 |
| **Forget to stop ADX** | about **+$3 per day** (+$92 per month) |

Tear-down isn't automated: the workflow blocks deletes by design, and `pdm_test` has `prevent_destroy`.
- **Partial:** the Synapse part has been retired using [test-synapse-retirement.md](test-synapse-retirement.md).
- **Full:** removing the rest of Test follows the same admin-run, reviewed-plan pattern ([runbooks.md §9](runbooks.md#9-cost-control-and-clean-up)).

While Test exists, its IoT Hub B1 costs **$10/month even when idle**.

## Residual privilege-escalation paths

The custom role and plan guards close the Dev gap for ADX and Synapse admin grants. These paths remain:

| Path | Why it remains | Control |
|---|---|---|
| **Creator rights**: ADX makes whoever creates a cluster or database an admin, and Synapse makes the workspace creator a Synapse Administrator | the pipeline creates them | Admin steps 4b and 5 remove them. **Until then the deployer is effectively admin of Test data.** |
| Storage account keys (`listKeys`) give full lake access | the lake allows shared keys (same as Dev). Denying `listKeys` may break the azurerm provider's storage reads (not tested). | Future: `shared_access_key_enabled = false`, after testing. |
| IoT Hub keys (`listkeys`) | needed for the ADX data connection policy (same as Dev) | Future: managed-identity data connection. |
| Constrained delegation lets the deployer grant blob roles to *other* service principals, for example a user-assigned identity it creates and attaches to compute it controls | the condition can exclude the deployer itself, but not every identity it might create | plan guard + human reviewer |
| ARM KQL scripts (`azurerm_kusto_script`) can't be denied in the custom role. Azure rejects `.../databases/scripts/write` as an unknown action, and creating a script appears to be authorised by database write, which the deployer needs. A script could run `.add database ... admins`. | there's no separate RBAC action | the plan guard blocks `azurerm_kusto_script`; human review of every plan |
| One human is both author and reviewer | single-person project | For Prod, use a second reviewer with "prevent self-review" on the environment. |

## Pre-deployment risks: how they turned out

| Risk noted before the first apply | Outcome |
|---|---|
| Synapse workspace creation by a deployer limited to one resource group | **worked**: the Synapse service created the managed resource group. But the creator (the deployer) became the only Synapse Administrator and the Entra SQL admin, which needed the handover. |
| The RBAC condition syntax (`ForAnyOfAllValues:GuidNotEquals`) | **accepted by Azure** (Test and Prod) |
| The managed identity policy might already allow the system identity | it **didn't** (`[]`). It had to be set, **and** the identity needed Viewer on the database. |
| The custom role's `.../databases/scripts/write` NotAction | **rejected by Azure** as an unknown action, and removed. The plan guard blocks `azurerm_kusto_script` instead. |
