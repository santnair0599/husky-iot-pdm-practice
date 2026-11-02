# Test Synapse retirement (Lesson 18C, Option B)

> **Status (2026-11-02): EXECUTED.**
> - The admin reviewed a saved plan showing exactly `0 to add, 0 to change, 3 to destroy` (workspace `syn-husky-pdm-test-0599` + its 2 storage roles). The saved file was also checked programmatically: 3 deletes, all inside `rg-husky-pdm-test`, nothing in Dev or Prod, `pdm_test` untouched.
> - **`Apply complete! Resources: 0 added, 0 changed, 3 destroyed.`**
> - `TF_SYNAPSE_MODE=none` set on `test`. Run **`41428063618`**: *"No changes: approval and apply will be skipped."*
> - Afterwards only `syn-husky-pdm-dev-0599` remained, which freed the slot. Prod's workspace `syn-husky-pdm-prod-0599` was then created (A6).
> - Logs were saved to `C:\dev\azure\husky-evidence\test\` beforehand.
>
> Sections 3 and 4 below are the procedure as it was approved and run.

**Why:** the subscription allows **2 Synapse workspaces** (Pay-As-You-Go: `ReachedPerSubscriptionWorkspaceLimit … Current maximum: 2`). Dev and Test hold both, so Prod's admin-created workspace (step A6 in [prod-environment.md](prod-environment.md)) can't be created.

**Choice:** a **targeted retirement**. Only Test's Synapse workspace is removed. The rest of Test (ADX, IoT Hub, storage, monitoring, identity) stays, and Test keeps working as an ADX-only environment.

## 1. Test acceptance evidence (preserved)

Release tag **`test-passed-2026-11-02`** (annotated) → commit **`86fad6d1d5c61c044049895fd18ab5a64e2b4c0a`**.

| Run | Workflow | Commit | Result | What it proved |
|---|---|---|---|---|
| `41329005231` | approved Terraform | `96e6726` | success | OIDC, isolation from Dev, 23 added via exact saved plan, post-apply no-change |
| `41329123385` | approved Terraform | `96e6726` | success | follow-up run: no changes, so approval and apply were skipped |
| `41394765861` | approved Terraform | `ab2f363` | failure | the ADX-stopped check worked as designed ("ADX cluster is Stopped") |
| `41396226090` | approved Terraform | `ab2f363` | success | IoT Hub → ADX data connection: 1 added, post-apply no-change |
| `41407963105` | approved Terraform | `a470b89` | success | module `synapse_mode` change: 3 moved, 0 added/changed/destroyed |
| `41338201298` | one-time Synapse handover | `77d6c52` | success | granted the human admin Synapse Administrator (workflow deleted in PR #3) |
| `41340635265`, `41341166102` | app release `kql-only` | `ab2f363` | failure | found missing admin prerequisites: export identity policy, cluster identity Viewer |
| `41341600305` | app release `kql-only` | `ab2f363` | success | KQL deployed, re-run skipped 11/12, `5 passed` |
| `41397526409` | app release `kql-sql` | `ab2f363` | failure | Synapse deployed with the deployer's 6 grants; lake read failed because the lake was empty (found the step-order issue) |
| `41399028829`, `41400247069` | app release `full` | `ab2f363`, `bbaf7a6` | failure | found the step-order issue (PR #4) and the empty-lake wait bug (PR #5) |
| **`41401561043`** | **app release `full`** | **`86fad6d`** | **success** | **13 of 13 integration tests**: Bronze 337 s, Quarantine, raw archive, Parquet → Synapse 253 s, views read the lake |

**Reconciliation was never run.** The Bronze = Silver + Quarantine gate (`tests/integration/test_data_health.py`, Lesson 19D) is an uncommitted draft that has not run successfully anywhere. Test acceptance doesn't include it.

### Release file hashes at `test-passed-2026-11-02`

| File | SHA-256 |
|---|---|
| `deploy/kql-manifest.txt` | `b8a4dcb73859c2ba61eac696bf1da4f13575fc94d831b589d9db849df8cc896b` |
| `deploy/synapse-manifest.txt` | `65f7dce821463205716ce3bb0c1ece08d552b3403361b59433d246e2ab9de3c5` |
| `kql/01_raw_ingestion.kql` | `719aa10d417a22cc33273e344c2e9bdf25948bcb6c72fe7ae485968574b41897` |
| `kql/02_silver_quarantine_tables.kql` | `bc83a3ba0e9ad7035836de9336bc83112b2285e3d305faacf77cbdab4f34a79d` |
| `kql/03_validation_functions.kql` | `53ec0e2fa8bad3f870545bf6eb9bb7cf7410aecc648871c6432daf024fbf2338` |
| `kql/04_update_policies.kql` | `dce1ce0872b9e70d0ae1a0c77eea7505428176bd22aa2887665a53ef4da560b6` |
| `kql/06_device_health.kql` | `64393e815287b88d713d9c4c469bc988939f84651916d648020ac1ee8ff2ac0b` |
| `kql/07_vibration_anomalies.kql` | `f887ba08a0f2000cee545b99559f7fd004cf96b60d4750676cd8551b77501383` |
| `kql/08_vibration_forecast.kql` | `85ea85e85b4859d20a83003f9b4d3644390479ff40bde1b03657ed894a9df276` |
| `kql/09_maintenance_alerts.kql` | `1022fb20c669cc68f8fb8c0ebdd0ccd2090af490596ed4f5ed90da3d801f62bf` |
| `kql/11_external_parquet.kql` | `69ff43bfbb92f81f534226ed4b769a4a09f642fa8f5aeac9662a60422a72e4e2` |
| `kql/12_continuous_export.kql` | `a982d03f32ff2217ae3a5877d286492ac9201dc04d1d145bbbd992804c9246d7` |
| `scripts/deploy_kql.py` | `63ca8d97a059884c9814cab61aaca4b0ee64ef90b3e1663d5af55e078de3a41f` |
| `scripts/deploy_synapse.py` | `42aed7203e72d9f4ac5aa55bbf508199ffa12da85ecde0d895ddaf3bb5e7de25` |
| `synapse/05_deploy_views.sql` | `ab0d68cf5a9e9bdbbd2f3d46be9d6228ccb2a03f777f089c869a4ae818f3fdf1` |

Prod's release workflow checks these files against the tag on every promotion (`git diff` against `TESTED_RELEASE_TAG`, plus a SHA-256 list in the run summary). Prod run `41417893719` reported "Promotion check OK".

**Save the logs before deleting anything:**
```powershell
New-Item -ItemType Directory -Force C:\dev\azure\husky-evidence\test | Out-Null
foreach ($id in 41329005231,41329123385,41396226090,41407963105,41338201298,41341600305,41401561043) { gh run view $id --log > "C:\dev\azure\husky-evidence\test\run-$id.log" }
```
This folder is outside the repo. I checked earlier that the logs contain no secrets: no keys and no alert email.

## 2. Test inventory (2026-11-02)

| Kind | Test-only items |
|---|---|
| Resource group `rg-husky-pdm-test` | IoT Hub `iot-husky-pdm-test-0599`; ADX `adxhuskypdmtest0599` / `pdm_test`; storage `sthuskypdmtest0599` (`raw`, `curated`, `synapse`); **Synapse `syn-husky-pdm-test-0599`**; Log Analytics; action group; 2 alerts |
| Synapse managed RG | `synapseworkspace-managedrg-f1670966-…`, **managed by the workspace** (holds `Microsoft.Sql/servers/syn-husky-pdm-test-0599`) |
| Terraform state | `tfstate-test/husky-test.tfstate` (69 KB, unlocked). **All 24 resource IDs are inside `rg-husky-pdm-test`** (checked programmatically). |
| Azure role assignments | deployer: custom role + RBAC Admin (RG), Blob Reader (`raw`), Blob Contributor (`tfstate-test`); IoT Hub identity → `raw`; ADX identity → `curated`; **Synapse identity `382537c1…` → `synapse` + `curated`** |
| Synapse RBAC / SQL | you + workspace identity as Synapse Administrator; database `HuskyPDMTest` with the deployer's 6 grants |
| Entra | app `sp-husky-pdm-test` (`6630dfb8…`), credential `…:environment:test`; custom role `Husky PDM Deployer (test)` |
| IoT device | `IMM-900` (Test hub) |
| GitHub | environments `test`, `test-approval` |

**Shared items: none are touched.**
- The state storage account `sthpdm5mljzdg5` is shared, but Test can only reach `tfstate-test`.
- Dev and Prod Terraform and workflows don't reference any Test resource. The only mention is Prod's isolation check, which *requires* that Test be unreachable.
- Prod Synapse is a separate, admin-created workspace (`syn-husky-pdm-prod-0599`) in `rg-husky-pdm-prod`. **Prod doesn't depend on the Test workspace.**

## 3. Deletion scope (targeted)

From a read-only preview (`terraform plan -refresh=false -var synapse_mode=none` on `envs/test`):
```
module.platform.azurerm_role_assignment.synapse_curated_reader[0]  will be destroyed  (46b0459d-…)
module.platform.azurerm_role_assignment.synapse_default_fs[0]      will be destroyed  (55eaf604-…)
module.platform.azurerm_synapse_workspace.pdm[0]                    will be destroyed  (syn-husky-pdm-test-0599)
Plan: 0 to add, 0 to change, 3 to destroy.
```
With the setting unchanged (`create`), the same code plans **"No changes"**.

| Deleted | Consequence |
|---|---|
| Workspace `syn-husky-pdm-test-0599` | the serverless `HuskyPDMTest` database (views, credential, data source, deployer login and grants) goes with it; Azure removes the **managed RG** and the workspace's managed identity. Firewall rules: none exist. |
| 2 role assignments for the Synapse identity | that identity no longer exists afterwards |

**Kept:**
- the `synapse` and `curated` containers and their data
- ADX, IoT Hub, storage, monitoring
- the deployer and its roles
- GitHub environments, and the `SYNAPSE_*` variables, which become unused

**Afterwards:**
- `deploy-app-test.yml` works only with **`kql-only`**. `kql-sql` and `full` fail at the Synapse firewall step, because there's no workspace.
- Test is **no longer able to repeat the 13/13 acceptance run** until Synapse is rebuilt.

**Protections, and why this runs outside the workflow:**
- `deploy-test-approved.yml` **blocks every delete**, by design.
- `prevent_destroy` exists only on `pdm_test`, which this retirement doesn't touch.
- So the admin runs the retirement locally, from a reviewed saved plan. The workflow stays delete-proof.

## 4. Procedure (admin, after approval)

The code change is already in the working tree, and must be merged first through a PR:
- `envs/test` gains `synapse_mode` (default `create`)
- `deploy-test-approved.yml` passes `TF_VAR_synapse_mode` (default `create`)

```powershell
cd "C:\dev\azure\husky-iot-predictive-maintenance-(practice)"
# 0. Evidence saved (section 1), PR merged, on main and up to date
git checkout main; git pull

# 1. Test ADX running, so Terraform can refresh every resource
az kusto cluster start --name adxhuskypdmtest0599 --resource-group rg-husky-pdm-test

# 2. Saved, reviewable retirement plan (normal state locking)
cd infra\terraform\envs\test
terraform init -input=false -reconfigure "-backend-config=storage_account_name=sthpdm5mljzdg5" "-backend-config=container_name=tfstate-test" "-backend-config=key=husky-test.tfstate"
$env:TF_VAR_alert_email = "santnair0599@gmail.com"
terraform plan -input=false -var synapse_mode=none "-out=retire-synapse.tfplan"
#    STOP unless it says: Plan: 0 to add, 0 to change, 3 to destroy  (the 3 resources in section 3)

# 3. Apply exactly that plan
terraform apply retire-synapse.tfplan
Remove-Item retire-synapse.tfplan

# 4. Keep the pipeline in step, and prove no drift
gh variable set TF_SYNAPSE_MODE -e test -b "none"
cd ..\..\..\..
gh workflow run deploy-test-approved.yml --ref main      # expect: No changes, approval and apply skipped

# 5. Stop Test ADX
az kusto cluster stop --name adxhuskypdmtest0599 --resource-group rg-husky-pdm-test

# 6. Confirm the slot is free (may take a few minutes after deletion)
az synapse workspace list --query "[].name" -o tsv     # expect only syn-husky-pdm-dev-0599
```
Then continue Prod at **A6** ([prod-environment.md](prod-environment.md)).

## 5. Rebuilding Test Synapse later

The subscription limit has to allow it. Either retire another workspace, or have the limit raised. Then:
1. `gh variable set TF_SYNAPSE_MODE -e test -b "create"`, then run `deploy-test-approved.yml` (expect 3 to add) and approve.
2. The creator is the pipeline again, so repeat the handover: a one-time workflow (see PR #2) grants you Synapse Administrator, then you remove the deployer's role.
3. Set yourself as SQL admin, add a temporary firewall rule, and run `synapse/00_bootstrap_test.sql` (6 grants).
4. `deploy-app-test.yml` with scope `full` → 13 of 13.

**Recovery if the retirement goes wrong:**
- The apply touches only the 3 listed resources.
- If it stops partway, re-run `terraform plan -var synapse_mode=none`. It plans only what's left.
- If you need Synapse back, follow the rebuild steps above.
