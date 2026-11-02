# Teardown: retiring the Husky Azure lab

> **Status (2026-11-02): IN PROGRESS.** **Prod is torn down**; see the [execution log](#8-execution-log). Test and Dev are not yet: each environment's final saved destroy plan needs explicit approval before it's applied.

The goal is to stop all Azure charges while **keeping** the GitHub repository, documentation, release tags (`test-passed-2026-11-02` → `86fad6d`, `prod-release-2026-11-02-1` → `a470b89`), the release-file hashes ([test-synapse-retirement.md](test-synapse-retirement.md#release-file-hashes-at-test-passed-2026-11-02)) and the run evidence.

## 0. Before anything is deleted

**Save the run logs.** GitHub deletes Actions logs after its retention period, 90 days by default. Test's logs are already in `C:\dev\azure\husky-evidence\test\`.
```powershell
New-Item -ItemType Directory -Force C:\dev\azure\husky-evidence\prod, C:\dev\azure\husky-evidence\dev | Out-Null
foreach ($id in 41412119364,41417893719,41418285822,41432917752,41436746679,41437359315,41440910246) { gh run view $id --log > "C:\dev\azure\husky-evidence\prod\run-$id.log" }
foreach ($id in 41287480751,41287867245,41291855425,41310902846,41313214638) { gh run view $id --log > "C:\dev\azure\husky-evidence\dev\run-$id.log" }
Get-ChildItem C:\dev\azure\husky-evidence -Recurse -File | Measure-Object | Select-Object Count   # expect 19 (7 test + 7 prod + 5 dev)
```

**Local secret:** `synapse/00_bootstrap_prod.sql` in the working tree contains the real Prod master-key password. It has never been committed. Save it elsewhere if you want it, then run `git restore synapse/00_bootstrap_prod.sql`.

## 1. Inventory (2026-11-02)

| Resource group | Contents | Created by |
|---|---|---|
| `rg-husky-pdm-dev` | IoT Hub (F1), ADX `adxhuskypdmdev0599`, storage `sthuskypdmdev0599`, Synapse `syn-husky-pdm-dev-0599`, Log Analytics, action group, 2 alerts | **Terraform, including the resource group itself** |
| `rg-husky-pdm-test` | IoT Hub (B1), ADX, storage, Log Analytics, action group, 2 alerts (Synapse already retired) | resources: Terraform; **resource group: admin** |
| `rg-husky-pdm-prod` | IoT Hub (B1), ADX, storage, **Synapse `syn-husky-pdm-prod-0599`**, Log Analytics, action group, 2 alerts | resources: Terraform; **Synapse and resource group: admin** |
| `synapseworkspace-managedrg-3749825f-…` / `…-23da3fb3-…` | Synapse-managed SQL servers (Dev / Prod) | Azure; **deleted with their workspace** |
| `rg-husky-pdm-tfstate` | storage `sthpdm5mljzdg5`: containers `tfstate-dev`, `tfstate-test`, `tfstate-prod` (one state file each, all unlocked) | `infra/bootstrap` (**local** state) |
| `NetworkWatcherRG` | Azure network watchers | **Azure automatic. Not Husky; don't touch.** |

**Shared backend:** `sthpdm5mljzdg5` holds only the three Husky state files, so it belongs to this project alone.

**Protections:**
- `prevent_destroy` on `azurerm_kusto_database` in `infra/terraform/envs/dev/adx.tf` and `infra/terraform/modules/pdm_platform/adx.tf`
- every approved workflow **blocks deletes**

So the teardown runs locally, from saved plans built in a separate teardown copy where `prevent_destroy` is off. The repo's code is unchanged.

## 2. Saved destroy plans (read-only previews)

Built 2026-11-02 in the scratchpad teardown copy (`…/scratchpad/teardown/infra/envs/<env>/destroy-<env>.tfplan`):
- from the **real remote state**, with `-lock=false -refresh=false`, so no lock was taken and nothing was written
- ADX was stopped at the time
- every change is a `delete`, `applyable: true`, and **no plan references another environment**

| Env | Plan | SHA-256 | Deletes |
|---|---|---|---|
| **Prod** | `destroy-prod.tfplan` | `29cc66c30e4ff5efb56f7286d42654e728443fe7b85fefe2470d510b769deed4` | **23**: IoT Hub + consumer group, endpoint, 2 routes, SAS policy; ADX cluster + `pdm_prod` + data connection; storage + `raw`/`curated`/`synapse`; 4 role assignments (IoT→raw, ADX→curated, Synapse identity→curated/synapse); Log Analytics, action group, 2 diagnostic settings, 2 alerts |
| **Test** | `destroy-test.tfplan` | `fae6100d1c41f216cdaf7ffa10f343dfc2e702c5953a95c5cb8dc718c85fd46c` | **21**: the same, minus the 2 Synapse roles (already retired) |
| **Dev** | `destroy-dev.tfplan` | `f6d16e62b348fa5212c071a179aad9392cea50fdc4b48275c9ce9cf595da2510` | **29**: the same set + **Synapse workspace** + `allowAll` firewall rule + ADX `adx-admin` and `github-deployer-admin` assignments + `quarantine` container + **resource group `rg-husky-pdm-dev`** (Dev's Terraform owns its resource group) |

**Not in any plan (manual clean-up):**

| Env | Item |
|---|---|
| Prod | admin-created Synapse workspace `syn-husky-pdm-prod-0599` (Terraform only reads it) and its managed resource group; resource group `rg-husky-pdm-prod`; RG-scoped role assignments (custom role, RBAC Administrator); custom role `Husky PDM Deployer (prod)`; app `sp-husky-pdm-prod` (`64678ee8…`); its Blob Data Contributor on `tfstate-prod`; GitHub `prod`, `prod-approval` |
| Test | resource group `rg-husky-pdm-test`; RG-scoped role assignments; custom role `Husky PDM Deployer (test)`; app `sp-husky-pdm-test` (`6630dfb8…`); its `tfstate-test` role; GitHub `test`, `test-approval` |
| Dev | app `sp-husky-pdm-dev` (`716c397a…`); its `tfstate-dev` role; the human's Blob roles on `sthuskypdmdev0599` (go with the storage account); Entra user `pbi-analyst@…onmicrosoft.com`; GitHub `dev`, `dev-approval` |
| Shared | `rg-husky-pdm-tfstate` / `sthpdm5mljzdg5` (via `infra/bootstrap`, local state); the human's Blob roles on the tfstate account and resource group |

**Deleted automatically with their parent:**
- IoT devices (`IMM-900`, `IMM-001`), with the hub
- ADX principal assignments and managed-identity policy, with the cluster
- role assignments scoped inside a storage account (for example the deployers' `raw` Reader), with the account
- the Synapse managed resource groups, with their workspaces

## 3. Order and procedure (after approval, one environment at a time)

Order: **Prod → Test → Dev → identities → shared backend (optional, last).**

**The previews in section 2 aren't applied.** They were built with `-refresh=false`, so they were never compared with live Azure. For each environment, a **final plan is regenerated against live Azure** (refresh on, normal state lock) and approved by its own full SHA-256.

For each environment:
```powershell
# a) Start its ADX. A refreshed plan has to read the ADX database (impossible while the cluster is
#    stopped), and deleting the database, data connection and principal assignments needs it running.
az kusto cluster start --name adxhuskypdm<env>0599 --resource-group rg-husky-pdm-<env>

# b) Regenerate the FINAL plan against live Azure, in the teardown copy (prevent_destroy off in the copy only)
cd "C:\Users\97156\AppData\Local\Temp\claude\C--Users-97156\7fc48c2e-2de5-4ee8-8b00-938d2bc82a1e\scratchpad\teardown\infra\envs\<env>"
$env:TF_VAR_alert_email = "santnair0599@gmail.com"
terraform plan -destroy -input=false "-out=final-destroy-<env>.tfplan"   # review the full list; approve by its full SHA-256

# c) Apply exactly the approved final plan (Terraform refuses it if the state changed since)
(Get-FileHash final-destroy-<env>.tfplan -Algorithm SHA256).Hash   # must equal the approved SHA-256
$env:TF_VAR_alert_email = "santnair0599@gmail.com"
terraform apply final-destroy-<env>.tfplan                   # expect: 0 added, 0 changed, N destroyed

# d) Verify
terraform state list                                         # expect: only data sources (test/prod: data.azurerm_resource_group…), or nothing (dev)
az resource list -g rg-husky-pdm-<env> --query "[].name" -o tsv   # prod: only syn-husky-pdm-prod-0599 left; test: empty; dev: resource group gone
```
If a plan is reported as **stale** ("Saved plan is stale"), something changed the state. Don't force it. Regenerate the plan the same way, compare it, and get it approved again.

**Prod extras, after step d: the admin-created Synapse workspace**

Inventory (read-only, 2026-11-02):
- no dedicated SQL pools, no Spark pools, no firewall rules, no private endpoints, no resource locks
- the managed resource group `synapseworkspace-managedrg-23da3fb3-…` holds only its SQL server and `master`
- the serverless database `HuskyPDMProd` (views, credential, data source, deployer login and grants) lives inside the workspace and is deleted with it
- the lake data is in storage, which the Prod plan has already deleted

```powershell
az synapse workspace show -n syn-husky-pdm-prod-0599 -g rg-husky-pdm-prod --query "{state:provisioningState,mrg:managedResourceGroupName}" -o table   # review
az synapse workspace delete --name syn-husky-pdm-prod-0599 --resource-group rg-husky-pdm-prod --yes
az group exists -n synapseworkspace-managedrg-23da3fb3-6ab5-490e-a63e-f86f7f053c56   # expect false (Azure removes it; may take minutes)
```
**Test and Prod extras** (the deployer's object ID: test `40e96239-…`, prod `29d54faa-…`):
```powershell
$rgId = az group show -n rg-husky-pdm-<env> --query id -o tsv
az role assignment delete --assignee <deployer-object-id> --scope $rgId                   # custom role + RBAC Administrator
az role definition delete --name "Husky PDM Deployer (<env>)" --scope $rgId
az resource list -g rg-husky-pdm-<env> --query "length(@)" -o tsv                       # must be 0
az group delete --name rg-husky-pdm-<env> --yes                                          # admin-created resource group, now empty
```
The custom role must be deleted **before** its resource group: its only assignable scope is that group.

## 4. Identities and GitHub (after all three environments)

```powershell
$stateId = az storage account show -n sthpdm5mljzdg5 -g rg-husky-pdm-tfstate --query id -o tsv
az role assignment delete --assignee bc4acfe8-2ed0-451c-ba50-659edf2c310e --scope "$stateId/blobServices/default/containers/tfstate-dev"    # Dev deployer
az role assignment delete --assignee 40e96239-18b0-45e2-9391-9335e2796fbd --scope "$stateId/blobServices/default/containers/tfstate-test"   # Test deployer
az role assignment delete --assignee 29d54faa-17fb-4fea-a661-edace6228959 --scope "$stateId/blobServices/default/containers/tfstate-prod"   # Prod deployer
foreach ($a in "716c397a-9a52-4e49-a122-83d601664a2d","6630dfb8-ce93-48e5-b26f-c0c4f9c37136","64678ee8-4aff-405f-9677-d9737e5e649f") { az ad app delete --id $a }   # also removes their federated credentials and service principals
az ad user delete --id pbi-analyst@engineersantoshnairoutlook.onmicrosoft.com
foreach ($e in "dev","dev-approval","test","test-approval","prod","prod-approval") { gh api -X DELETE repos/santnair0599/husky-iot-pdm-practice/environments/$e }   # removes each environment's variables and secrets
```
Deleting an app registration moves it to the Entra recycle bin for 30 days, from where it can be restored.

## 5. Shared state backend (optional, last)

Only after all three state files are empty and the evidence is saved:
```powershell
cd "C:\dev\azure\husky-iot-predictive-maintenance-(practice)\infra\bootstrap"
terraform plan -destroy "-out=destroy-bootstrap.tfplan"      # expect 6: random string, resource group, storage account, 3 containers
terraform apply destroy-bootstrap.tfplan
```
That removes `rg-husky-pdm-tfstate` and all Terraform state history. To rebuild later you'd re-bootstrap from scratch.

## 6. Final check: no cost left

```powershell
az group list --query "[?contains(name,'husky') || starts_with(name,'synapseworkspace-managedrg')].name" -o tsv   # expect nothing (or only rg-husky-pdm-tfstate if step 5 skipped)
az ad app list --filter "startswith(displayName,'sp-husky')" --query "[].displayName" -o tsv                   # expect nothing
az role definition list --custom-role-only true --query "[?contains(roleName,'Husky')].roleName" -o tsv         # expect nothing
gh api repos/santnair0599/husky-iot-pdm-practice/environments -q '[.environments[].name]'                     # expect []
```

**After teardown, nothing bills.** Today, while it exists:
- **ADX:** about $0.126/h per cluster **while running**
- **IoT Hub B1** (Test, Prod): **$10/month each, always**
- storage and Log Analytics: cents

Log Analytics workspaces are **soft-deleted for 14 days**. That costs nothing, but blocks reusing the same name during that time.

## 7. Risks and notes

- **Dev's plan deletes its resource group** (`rg-husky-pdm-dev`), because Dev's Terraform created it. The azurerm provider refuses to delete a resource group that still contains unmanaged resources, so it fails safely if anything unexpected is inside. If you want to keep the empty group, remove it from the plan first: `terraform state rm azurerm_resource_group.pdm` in the teardown copy, then re-plan.
- **The plans used `-refresh=false`.** They delete exactly what the state records. A resource already deleted by hand makes that step fail with "not found", which is harmless; re-plan and continue.
- **The teardown copy lives in the session scratchpad.** If it's gone, rebuild it: copy `infra/terraform/{modules,envs}`, switch `prevent_destroy` off in that copy only, `terraform init` with `-backend-config` for the environment, then `terraform plan -destroy -lock=false -refresh=false -out=…`. Review it again.
- **Not touched:** `NetworkWatcherRG`, anything outside the Husky resource groups, the repository, tags, docs and Actions history.

## 8. Execution log

### Prod (2026-11-02): complete, except the identity and GitHub items kept for the final clean-up

| Time (UTC) | Action | By | Evidence |
|---|---|---|---|
| before 13:00 | evidence saved: 19 run logs (Test 7, Prod 7, Dev 5) in `C:\dev\azure\husky-evidence\`, no keys in any | admin | file count and key scan |
| ≈12:55–13:02 | **Terraform destroy of Prod**: final plan regenerated against live Azure (refresh on, state lock, Prod ADX running), approved by full SHA-256 `be0bc256cd98b23dd181fc6324822f5220958f972b9c8a09a058ab7f8b865d7c`, hash re-checked immediately before apply | admin (local, saved plan) | `Apply complete! Resources: 0 added, 0 changed, 23 destroyed.`; Prod state now empty (1,855 bytes); only the admin-created Synapse workspace left in the resource group |
| 13:09–13:10 | admin-created Synapse workspace `syn-husky-pdm-prod-0599` deleted (serverless `HuskyPDMProd` with it) | admin | activity log `Microsoft.Synapse/workspaces/delete` Succeeded 13:10:22; managed resource group `…-23da3fb3-…` then gone |
| 13:54:05 / 13:54:07 | role assignments `5680ad58-145a-42c1-98fa-94215de47989` (Husky PDM Deployer (prod)) and `13ecb69b-37b2-4dde-bc15-da3e6c21be4f` (RBAC Administrator, with condition) for `sp-husky-pdm-prod` (`29d54faa…`) deleted | admin | activity log `roleAssignments/delete` Succeeded |
| 13:54:15 | custom role `Husky PDM Deployer (prod)` (`e9cf88bc-9372-4efd-917f-a9a8d45c7639`) deleted; it had 0 assignments | admin | activity log `roleDefinitions/delete` Succeeded |
| 13:54:39 | empty resource group `rg-husky-pdm-prod` deleted | admin | activity log `resourcegroups/delete` Succeeded; `az group exists` → `false` |

**Checks after Prod:**
- Dev: 8 resources; Test: 7 resources. Their state files are unchanged (`husky-dev.tfstate` 70,952 bytes, last modified 2026-11-01T08:13:07Z; `husky-test.tfstate` 61,727 bytes, 2026-11-02T10:22:22Z).
- The built-in RBAC Administrator role and the 3 subscription-level role assignments are untouched.
- **Kept for the final clean-up:** app `sp-husky-pdm-prod`, its Blob Data Contributor on `tfstate-prod`, `husky-prod.tfstate` (empty), and GitHub `prod` / `prod-approval`.

**Cost:** nothing in Prod bills any more. The ADX cluster and the $10/month IoT Hub B1 are both gone.
