# Runbooks

Each runbook follows the same pattern: **symptom → check → fix → prove it's fixed.** The commands use the Dev names. KQL runs in https://dataexplorer.azure.com against cluster `adxhuskypdmdev0599`, database `pdm_dev`.

For Test and Prod, swap in that environment's names: `…test…` / `pdm_test`, `…prod…` / `pdm_prod`, resource groups `rg-husky-pdm-test` / `rg-husky-pdm-prod`.

These procedures come from the real design and from problems hit while building Dev, Test and Prod. Failure drills that rehearse them on purpose are planned but not done yet.

| # | Runbook |
|---|---|
| 1 | [ADX cluster stopped or unavailable](#1-adx-cluster-stopped-or-unavailable) |
| 2 | [Messages not arriving in Bronze (ingestion failure)](#2-messages-not-arriving-in-bronze-ingestion-failure) |
| 3 | [Rows in Bronze but missing from Silver or Quarantine](#3-rows-in-bronze-but-missing-from-silver-or-quarantine) |
| 4 | [Parquet export failing or Synapse data stale](#4-parquet-export-failing-or-synapse-data-stale) |
| 5 | [A release fails halfway](#5-a-release-fails-halfway) |
| 6 | [Missing or expired permissions](#6-missing-or-expired-permissions) |
| 7 | [Terraform deployment problems](#7-terraform-deployment-problems) |
| 8 | [Synapse serverless query errors](#8-synapse-serverless-query-errors) |
| 9 | [Cost control and clean-up](#9-cost-control-and-clean-up) |
| — | [Open verification items](#open-verification-items) |

The two Azure Monitor alerts in [`monitor.tf`](../infra/terraform/envs/dev/monitor.tf) say "Runbook: monitoring/runbooks/ingestion.md" and "…/export.md". Those paths don't exist. The real procedures are runbooks [2](#2-messages-not-arriving-in-bronze-ingestion-failure) and [4](#4-parquet-export-failing-or-synapse-data-stale) on this page. The alert descriptions should be updated in a future infrastructure change.

---

## 1. ADX cluster stopped or unavailable

**Symptom:** a workflow fails at "Check ADX cluster is running" with `ADX cluster is Stopped. Start it before running this workflow.` Or Data Explorer / Power BI can't connect.

**Check:**
```powershell
az kusto cluster show --name adxhuskypdmdev0599 --resource-group rg-husky-pdm-dev --query state -o tsv
```

**Fix:**
```powershell
az kusto cluster start --name adxhuskypdmdev0599 --resource-group rg-husky-pdm-dev   # 5-10 min
```
Then re-run the failed workflow. If the state is `Starting` or `Stopping`, wait for it to finish; you can't start a cluster while it's stopping.

**Prove:** the state is `Running`, and the workflow passes its ADX check.

**Cost rule:** stop the cluster after every session, including after a failed run:
```powershell
az kusto cluster stop --name adxhuskypdmdev0599 --resource-group rg-husky-pdm-dev
```
While ADX is stopped, IoT Hub keeps messages on the `events` endpoint only for its retention period. The `raw` archive keeps everything, so it's the replay source for anything ADX missed.

## 2. Messages not arriving in Bronze (ingestion failure)

**Symptom:** the alert `alert-adx-ingestion-failed-dev` fires. Or "Verify Bronze and Silver" times out with `did not arrive in Telemetry_Raw`.

**Check, in order:**
1. **Did IoT Hub accept the message?** The sender prints `Azure IoT Hub acknowledged the message.` If it didn't:
   - check the device connection string, which must belong to the same device as `IOTHUB_MACHINE_ID`
   - check the **F1 tier limit of 8,000 messages per day** (IoT Hub → Metrics → *Total number of messages used*)
2. **Is ADX running?** See runbook 1.
3. **Did ADX reject it?**
   ```kql
   .show ingestion failures
   | where FailedOn > ago(2h)
   | project FailedOn, Table, Details, FailureKind, ErrorCode
   ```
   Typical causes:
   - the mapping `TelemetryRawMapping` was changed or is missing (`test_kql_deployed` checks it exists)
   - the payload isn't JSON
4. **Is the data connection healthy?** Portal → ADX cluster → Databases → `pdm_dev` → Data connections → `iot-telemetry-dev`. Check that it still uses consumer group `adx-dev` and shared access policy `adx-reader`.
5. **Is it just batching?** ADX batches ingestion. In run `41313214638`, Bronze took 325 s. Wait the full 10 minutes before treating it as a failure.

**Fix:**
- Restore a missing mapping by re-running the release (`deploy-app-dev.yml`, scope `kql-only`).
- Recreate a broken data connection with the approved Terraform workflow.
- Replay lost messages from the `raw` archive.

**Prove:** run the `full` scope. "Verify Bronze and Silver" passes.

## 3. Rows in Bronze but missing from Silver or Quarantine

**Why this can happen:** both update policies are `IsTransactional: false` ([`04_update_policies.kql`](../kql/04_update_policies.kql)). If a policy fails, or is disabled, Bronze still ingests and the row is silently not written downstream.

**Symptom:** a message is in `Telemetry_Raw` but in neither `Telemetry` nor `Telemetry_Quarantine`. Power BI counts drop with no ingestion alert.

**Check:**
```kql
.show table Telemetry policy update
.show table Telemetry_Quarantine policy update
```
Both must show `"IsEnabled": true` and `Source` `Telemetry_Raw`. Then count the lost rows:
```kql
let Bronze = Telemetry_Raw
    | where ingestion_time() between (ago(24h) .. ago(10m))
    | project MessageId = tostring(Payload.message_id);
let Downstream = union
    (Telemetry | project MessageId),
    (Telemetry_Quarantine | project MessageId = tostring(Payload.message_id));
Bronze | join kind=leftanti Downstream on MessageId | count
```
`.show ingestion failures` also lists update-policy failures.

**Fix, in two parts: fixing the bug doesn't fix the data.**
1. **Fix the configuration:** re-run the release (`kql-only`). [`04_update_policies.kql`](../kql/04_update_policies.kql) re-applies both policies as enabled, and `test_kql_deployed` asserts they're enabled.
2. **Backfill the lost rows** with the same functions the policies use, never with hand-written rows. Exclude anything already present, so the backfill is safe to repeat:
   ```kql
   .set-or-append Telemetry <|
       SilverRows()
       | join kind=leftanti (Telemetry | project MessageId) on MessageId

   .set-or-append Telemetry_Quarantine <|
       QuarantineRows()
       | extend MessageId = tostring(Payload.message_id)
       | join kind=leftanti (Telemetry_Quarantine | project MessageId = tostring(Payload.message_id)) on MessageId
       | project-away MessageId
   ```
   These scan all of Bronze. On a large database, add a time filter on `ingestion_time()`.

**Prove:** the `leftanti` count above returns 0.

## 4. Parquet export failing or Synapse data stale

**Symptom:** the alert `alert-adx-export-failed-dev` fires. Or "Verify Synapse historical export" times out after 30 minutes. Or Synapse reports stop at an old date.

**Check:**
```kql
.show continuous-export TelemetryHistoricalExport
.show continuous-export TelemetryHistoricalExport failures
.show continuous-export TelemetryHistoricalExport exported-artifacts
| where Timestamp > ago(2h)
```
Look at:
- `IsDisabled`
- `LastRunResult`
- the failure messages; a `403` / permission failure means the ADX identity lost its storage role

Check that role:
```powershell
$storageId = az storage account show -n sthuskypdmdev0599 -g rg-husky-pdm-dev --query id -o tsv
az role assignment list --scope "$storageId/blobServices/default/containers/curated" --query "[].{role:roleDefinitionName,principal:principalId}" -o table
```
The ADX cluster's identity must have `Storage Blob Data Contributor`. It's defined in [`adx_export.tf`](../infra/terraform/envs/dev/adx_export.tf).

**Creating the export fails** with *"The managed identity 'system' … is not authorized to access the database"* (seen in Test runs `41340635265` and `41341166102`). The cluster's own identity needs **both**:
1. the cluster policy: `.alter-merge cluster policy managed_identity` with `"ObjectId": "system"` and `"AllowedUsages": "AutomatedFlows"`
2. **Viewer on the database**: `az kusto database-principal-assignment create … --principal-id <cluster identity client ID> --principal-type App --role Viewer`

Both are admin-only. Prod's release **preflight** checks the Viewer role before deploying.

**Fix:**
- Missing role: run the approved Terraform workflow. The plan will show the role assignment being re-created.
- Export disabled after repeated failures: `.enable continuous-export TelemetryHistoricalExport`
- **Don't re-create the export to "reset" it.** [`12_continuous_export.kql`](../kql/12_continuous_export.kql) is create-only on purpose. Re-creating it can re-export or skip data. Change it only as a planned, manual step.

**Prove:**
- new rows appear in `exported-artifacts`
- `SELECT MAX(EventTime) FROM pdm.vw_telemetry_deduplicated` moves forward
- a `full` run passes

## 5. A release fails halfway

**Symptom:** "Deploy KQL" or "Deploy Synapse views" fails partway through.

**Facts:**
- Every file is rendered and checked **before** anything is deployed. A bad placeholder or a forbidden SQL statement fails with no changes made.
- After that, deployment is **not transactional.**
  - KQL: files before the failing one are applied. Inside a file, commands before the failing one are applied too (`ThrowOnErrors` stops at the first error).
  - Synapse: batches before the failing one are applied.
- Every object uses create-merge, create-or-alter or CREATE OR ALTER, so re-running is safe.

**Fix:** fix the file, commit, re-run the same scope. **Roll forward; don't try to undo by hand.** To return to the previous version, revert the commit and re-run the release.

**Prove:** the deploy, re-run and verify steps are all green.

## 6. Missing or expired permissions

| Error (where) | Cause | Fix |
|---|---|---|
| `No matching federated identity record found …` (Azure login step) | the job didn't run in `environment: dev`, ran from a branch other than `main`, or the federated credential `gh-husky-dev-env` was changed | Use the `dev` environment from `main`. Compare the token subject with the credential: `az ad app federated-credential list --id <AZURE_CLIENT_ID>`. |
| `AuthorizationFailed` on a Terraform resource | the deployer's `Contributor` on `rg-husky-pdm-dev` was removed | An admin restores it (one-time setup, Lesson 18A). |
| `AuthorizationPermissionMismatch` / 403 on blobs (archive test, state) | missing `Storage Blob Data Reader` on `raw`, or `Contributor` on `tfstate-dev` | Re-grant using [`infra/manual-grants.md`](../infra/manual-grants.md). **Wait up to 10 minutes** for role assignments to take effect before re-running. |
| ADX "Principal … is not authorized" (Deploy KQL) | the deployer's database `Admin` was removed | Re-apply with the approved Terraform workflow (`azurerm_kusto_database_principal_assignment.deployer`). Check with `.show database pdm_dev principals`. |
| `Cannot find the user 'sp-husky-pdm-dev'` (Synapse) | the user exists in `master` as a login but not in `HuskyPDMDev` | As Synapse admin, in `HuskyPDMDev`: `CREATE USER [sp-husky-pdm-dev] FROM LOGIN [sp-husky-pdm-dev];` then re-run the grants in [`00_grant_deployer.sql`](../synapse/00_grant_deployer.sql). |
| `CREATE VIEW permission denied` / credential errors (Synapse) | one of the 6 grants is missing | Run the verify query at the end of [`00_grant_deployer.sql`](../synapse/00_grant_deployer.sql), expect 6 rows, and re-grant what's missing. |
| `Unauthorized` (Send test telemetry) | the IMM-900 key was regenerated, or the secret holds a different device | Reset the secret (next row's method). |
| `Invalid Connection String - Invalid Key` (Send test telemetry) | the secret was damaged when it was piped (`\|`) into `gh secret set` in Windows PowerShell 5.1, which re-encodes piped text. Seen in Prod run `41436746679`. | Set it as an argument: `$cs = az iot hub device-identity connection-string show --hub-name <hub> --device-id IMM-900 --query connectionString -o tsv; gh secret set IOTHUB_DEVICE_CONNECTION_STRING -e <env> -b $cs; Remove-Variable cs`. `$cs.Length` should be about 128. |
| Admin gets `Login failed … (18456)` on serverless SQL, or Studio says "you don't have access" | the workspace was **created by the pipeline**, so the deployer is the only Synapse Administrator. Being the Entra SQL admin alone wasn't enough. | Test: a one-time reviewed handover workflow granted the human Synapse Administrator (run `41338201298`), then the human removed the deployer's role. Prod avoids this: **the admin creates the workspace**. |
| `ReachedPerSubscriptionWorkspaceLimit … Current maximum: 2` (creating Synapse) | subscription quota: 2 Synapse workspaces on Pay-As-You-Go | Request a quota increase, or retire a workspace **through a reviewed Terraform plan** ([test-synapse-retirement.md](test-synapse-retirement.md)), never by a manual delete. |

OIDC tokens are short-lived and issued per job, so there are no client secrets to expire. A long job refreshes its login before the 30-minute Synapse wait ("Refresh Azure login").

## 7. Terraform deployment problems

| Symptom | Cause | Fix |
|---|---|---|
| No-change gate fails with "Infrastructure changes detected" | drift: someone changed Azure in the portal, or code changed without being applied | Read the printed plan. Then either apply the code with the approved workflow, or update the code to match Azure. Re-run the gate until it reports "No changes". |
| A local plan shows the action group email changing | `TF_VAR_alert_email` isn't set, or is set to a different address from the deployed one | Set it to the deployed value before `terraform plan`. |
| A plan shows every `kusto_script` being replaced | CRLF vs LF line endings (historic) | Already fixed: KQL is no longer in Terraform, and the deploy script normalises line endings. |
| "Plan contains delete or replace actions" | the `jq` guard did its job | Find out why something would be destroyed. Destroying anything needs a separate, deliberate process; this workflow won't do it. |
| `sha256sum: WARNING … did NOT match` | the plan artifact changed between plan and apply | Don't apply. Re-run the whole workflow to get a fresh, reviewed plan. |
| Apply can't find the plan artifact | artifacts are kept for 1 day | Re-run the whole workflow. Never apply an unreviewed plan. |
| `Error acquiring the state lock` | another run holds the lease, or a crashed run left it | Wait: `-lock-timeout=5m` already retries. Only if no run is active: `terraform force-unlock <LOCK_ID>`. |
| `Failed to save state` (network drop during a laptop apply) | Terraform wrote `errored.tfstate` locally | `terraform state push errored.tfstate`, then run the no-change gate. |
| Synapse workspace would be replaced | `synapse_managed_resource_group_name` doesn't match the managed resource group Azure created | Set `TF_SYNAPSE_MANAGED_RG_NAME` to the existing name. The delete guard also blocks this. |

## 8. Synapse serverless query errors

| Error | Meaning | Fix |
|---|---|---|
| "warming up" | the serverless pool is cold | Retry after about 30 s. |
| `No results. Previous SQL was not a query` | an intermittent cold-start response with no result set | `query_synapse` retries this automatically, 3 times. If it keeps happening, check the pool's health in the portal. |
| A view returns 0 rows | export not running (runbook 4), or the Synapse identity lost `Storage Blob Data Reader` on `curated` | Check both. |
| `Content of directory on path 'telemetry/**' cannot be listed. (13807)` | in a **new environment** `curated/telemetry/` doesn't exist until the first continuous export | Expected until the first export. The export test waits on 13807 only (PR #5; proven in Prod run `41437359315`: "No Parquet folder yet; waiting" → passed). If it persists after an export, check runbook 4. |
| The data source points at `https://<…>.dfs.core.windows.net/curated` | a placeholder in the bootstrap SQL wasn't replaced | `SELECT name, location FROM sys.external_data_sources;` then `DROP EXTERNAL DATA SOURCE HuskyCuratedLake;` and re-create it with the real account. |

## 9. Cost control and clean-up

**What bills, and when:**

| Resource | Dev | Test | Prod | Billed while idle? |
|---|---|---|---|---|
| ADX Dev SKU (E2a v4), about $0.126/h | ✓ | ✓ | ✓ | compute: **only while Running**; storage: cents |
| IoT Hub | F1 (free) | **B1, $10/month** | **B1, $10/month** | **yes**, B1 for as long as it exists |
| Synapse serverless ($5/TB scanned) | ✓ | retired | ✓ | no |
| Storage, Log Analytics (0.1 GB/day cap), alerts | ✓ | ✓ | ✓ | cents |

**Rule: keep every ADX cluster stopped unless you're actively deploying or testing.** Each forgotten cluster costs about $3 a day.

**Start, check, stop:**
```powershell
az kusto cluster start --name <adxhuskypdmdev0599|adxhuskypdmtest0599|adxhuskypdmprod0599> --resource-group <rg-husky-pdm-dev|-test|-prod>
az kusto cluster show  --name <cluster> --resource-group <rg> --query state -o tsv     # Running / Stopped / Starting / Stopping
az kusto cluster stop  --name <cluster> --resource-group <rg>
```
**Check all three at once:**
```powershell
foreach ($e in "dev","test","prod") { "{0}: {1}" -f $e, (az kusto cluster show -n "adxhuskypdm$($e)0599" -g "rg-husky-pdm-$e" --query state -o tsv) }
```
Workflows that need ADX check it first and fail clearly if it's stopped ("ADX cluster is Stopped. Start it before running this workflow."). Start the cluster, re-run, then stop it.

**Temporary firewall rules:** admins open Synapse to their own IP only while working (`admin-<date>`), and remove the rule afterwards. Release workflows add and **always** remove their own `gh-run-…` rule. Check that nothing is left open:
```powershell
az synapse workspace firewall-rule list --workspace-name <workspace> --resource-group <rg> --query "[].name" -o tsv
```

**Clean-up.** These are admin-only; the workflows block deletes by design:
- **One component** (example: Test Synapse): change the configuration so Terraform plans *only* those deletions, save the plan, review it, apply it locally, then confirm a pipeline run shows "No changes". See [test-synapse-retirement.md](test-synapse-retirement.md).
- **A whole environment:** follow [prod-environment.md § Clean-up](prod-environment.md#clean-up-admin-only-not-through-the-workflow):
  1. save the evidence
  2. `terraform state rm` the `prevent_destroy` database
  3. review a `plan -destroy`
  4. apply it
  5. delete any admin-created Synapse workspace
  6. remove the identity, roles, custom role, resource group, GitHub environments and state blob
- **Never delete resources by hand** while Terraform still manages them. The state would drift, and the next plan would try to re-create them.

## Open verification items

| Item | Status | How to close it |
|---|---|---|
| **The Quarantine update policy is enabled.** It may have been disabled during the Lesson 19D negative test (step 6a), and no output from that session was recorded. | **Pending.** It can't be checked while ADX is stopped, and ADX isn't being started just for this check. | At the next planned ADX session, run `.show table Telemetry_Quarantine policy update` and expect `"IsEnabled": true`. Any `deploy-app-dev` run also restores it, because it re-applies `04_update_policies.kql`, and its "Verify KQL objects" step fails if either policy is disabled. If it was disabled, also run the Quarantine backfill and lost-row check from runbook 3. |
