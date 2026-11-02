# Prod environment (Lesson 18C-P)

> **Status: implemented in code and checked locally. NOT deployed.** Nothing on this page has run against Azure.
>
> **Approval is self-approval.** The `prod-approval` reviewer is the same person who triggers the run. That's a recorded human gate, **not independent review**. In a team, add a second reviewer and turn on "Prevent self-review".

Prod promotes **exactly** what passed Test: tag `test-passed-2026-11-02` (commit `86fad6d`), Test run `41401561043` with 13 of 13 integration tests passing. It reuses the Test design, plus fixes for the four problems Test uncovered.

## What's different from Test

| | Test | Prod |
|---|---|---|
| Runs from | `main` | **`prod-release-*` tags only**. Both workflows refuse anything else. |
| Promotion | — | the release workflow fails unless `kql/`, `deploy/`, `scripts/`, `synapse/05_deploy_views.sql` and `tests/` are **identical** to `TESTED_RELEASE_TAG`, and it prints their SHA-256s; the infrastructure workflow requires the tested tag to be an ancestor of the release |
| Synapse workspace | created by the pipeline, which then needed a one-time handover | **created by the admin**. Terraform only reads it (`synapse_mode = none`, then `existing`), so a human is the first Synapse Administrator and SQL admin. |
| ADX prerequisites | found by failing runs | the release workflow **preflight** checks them first: ADX identity is Viewer on `pdm_prod`, the deployer has no cluster-level rights, the deployer isn't the Synapse SQL admin |
| Smoke test | `full`: test message plus an injected invalid event | `smoke`: **one** controlled test event from IMM-900, then read-only checks. **No quarantine injection** (`test_quarantine.py` refuses Prod databases anyway). |
| Isolation proof | can't see Dev | can't see **Dev or Test** |
| After apply | no-change plan | no-change plan, **and** the deployer must not be the Synapse SQL admin |

## Files

| File | Purpose |
|---|---|
| [`infra/terraform/envs/prod/`](../infra/terraform/envs/prod) | Prod root: same module as Test, with name checks that reject `dev`/`test`, F1, `pdm_test`, and `synapse_mode = create` |
| [`infra/terraform/modules/pdm_platform/synapse.tf`](../infra/terraform/modules/pdm_platform/synapse.tf) | new `synapse_mode` (`create` / `existing` / `none`). `moved` blocks keep Test's records unchanged: a local Test plan showed **0 to add, 0 to change, 0 to destroy**, plus 3 renames. |
| [`.github/workflows/deploy-prod-approved.yml`](../.github/workflows/deploy-prod-approved.yml) | tag guard + ancestor check → target guard → OIDC → isolation (Dev and Test) → plan → plan guards → provenance → `prod-approval` → exact apply → no-change plan → SQL-admin check |
| [`.github/workflows/deploy-app-prod.yml`](../.github/workflows/deploy-app-prod.yml) | tag guard → target guard → promotion check → preflight → KQL and Synapse deploy, each re-run → `smoke` checks |
| [`infra/roles/husky-pdm-deployer-prod.json`](../infra/roles/husky-pdm-deployer-prod.json), [`rbac-delegation-condition-prod.txt`](../infra/roles/rbac-delegation-condition-prod.txt) | same narrowed custom role and role-grant condition as Test, scoped to Prod. The condition has a `<PROD_DEPLOYER_OBJECT_ID>` placeholder. |
| [`synapse/00_bootstrap_prod.sql`](../synapse/00_bootstrap_prod.sql) | admin-only SQL setup: database, lake credential, deployer login, the same 6 grants |

## Before Prod: one Test step

The module change has to run in Test once. Run `deploy-test-approved.yml` (Test ADX running) and approve. It should show **0 to add, 0 to change, 0 to destroy**, with 3 resources moved. After that, Test has run the exact module Prod will use.

## Deployment order

**Admin** = you, on your laptop. **Pipeline** = GitHub Actions as `sp-husky-pdm-prod`. Every pipeline run uses `--ref prod-release-…`.

| # | Who | Step | Billable? |
|---|---|---|---|
| A1 | Admin | create resource group `rg-husky-pdm-prod` (eastus2) | no |
| A2 | Admin | app registration `sp-husky-pdm-prod`; federated credential: Organization `santnair0599` (ID `31506535`), Repository `husky-iot-pdm-practice` (ID `1427372824`), Entity **Environment** `prod` | no |
| A3 | Admin | custom role from `husky-pdm-deployer-prod.json` → assign it on the Prod resource group; Storage Blob Data Contributor on **`tfstate-prod`**; RBAC Administrator with `rbac-delegation-condition-prod.txt` (placeholder replaced) | no |
| A4 | Admin | GitHub environments `prod` and `prod-approval` (reviewer: you), **both limited to tags `prod-release-*`**; set variables and secrets (below). Recommended: branch protection on `main`. | no |
| P1 | Pipeline | merge to `main`, create tag `prod-release-<date>-1`, run `deploy-prod-approved.yml`. Expect **20 to add** (no Synapse, no data connection). Approve. | **yes** (ADX, IoT Hub B1) |
| A5 | Admin | ADX: you as AllDatabasesAdmin; confirm the deployer is Admin on `pdm_prod` **only**; `.alter-merge cluster policy managed_identity` (AutomatedFlows); **cluster identity as Viewer on `pdm_prod`** | no |
| A6 | Admin | **create the Synapse workspace yourself** (commands below) | no (serverless) |
| P2 | Pipeline | `deploy-app-prod.yml`, scope `kql-only`: preflight, promotion check, KQL, re-run, verify | no |
| P3 | Admin + Pipeline | set `TF_CREATE_DATA_CONNECTION=true` and `TF_SYNAPSE_MODE=existing`, then run `deploy-prod-approved.yml`. Expect **3 to add** (data connection + 2 Synapse storage roles). Approve. | no |
| A7 | Admin | temporary firewall rule for your IP, run `00_bootstrap_prod.sql` (6 grants), remove the rule | no |
| A8 | Admin | IoT device `IMM-900` in the Prod hub; pipe its connection string into secret `IOTHUB_DEVICE_CONNECTION_STRING` (`prod`); Storage Blob Data Reader on Prod `raw` for the deployer | no |
| P4 | Pipeline | `deploy-app-prod.yml`, scope **`smoke`** | no |
| P5 | Pipeline | `deploy-prod-approved.yml` again: approval and apply are skipped if there are no changes | no |
| A9 | Admin | **stop Prod ADX** | — |

### GitHub `prod` environment

| Variables | Value |
|---|---|
| `AZURE_CLIENT_ID` / `DEPLOYER_OBJECT_ID` | from A2 (client ID / **service principal** object ID) |
| `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` | same as Test |
| `TF_STATE_ACCOUNT` / `TF_STATE_CONTAINER` / `TF_STATE_KEY` | `sthpdm5mljzdg5` / `tfstate-prod` / `husky-prod.tfstate` |
| `TF_RESOURCE_GROUP_NAME` | `rg-husky-pdm-prod` |
| `TF_LOCATION` / `TF_SYNAPSE_LOCATION` | `eastus2` / `centralus` |
| `TF_STORAGE_ACCOUNT_NAME`, `ADLS_ACCOUNT_NAME` | `sthuskypdmprod0599` |
| `TF_IOT_HUB_NAME` | `iot-husky-pdm-prod-0599` |
| `TF_ADX_CLUSTER_NAME` | `adxhuskypdmprod0599` |
| `ADX_CLUSTER_URI` / `ADX_DATABASE` | `https://adxhuskypdmprod0599.eastus2.kusto.windows.net` / `pdm_prod` |
| `TF_SYNAPSE_WORKSPACE_NAME` | `syn-husky-pdm-prod-0599` |
| `SYNAPSE_SQL_SERVER` / `SYNAPSE_SQL_DATABASE` | `syn-husky-pdm-prod-0599-ondemand.sql.azuresynapse.net` / `HuskyPDMProd` |
| `TF_CREATE_DATA_CONNECTION` / `TF_SYNAPSE_MODE` | `false` / `none` at first, then `true` / `existing` (P3) |
| `TEST_DEVICE_ID` | `IMM-900` |
| `TESTED_RELEASE_TAG` | `test-passed-2026-11-02` |
| **Secrets:** `ALERT_EMAIL`, `IOTHUB_DEVICE_CONNECTION_STRING` (A8) | |

All Prod resource names were confirmed available on 2026-11-02.

### A6: the admin creates the Synapse workspace

```powershell
$pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})   # never stored; Entra-only auth is enabled next
az synapse workspace create --name syn-husky-pdm-prod-0599 --resource-group rg-husky-pdm-prod --location centralus --storage-account sthuskypdmprod0599 --file-system synapse --sql-admin-login-user sqladminuser --sql-admin-login-password $pw -o none
Remove-Variable pw
az synapse ad-only-auth enable --workspace-name syn-husky-pdm-prod-0599 --resource-group rg-husky-pdm-prod -o none
az synapse sql ad-admin create --workspace-name syn-husky-pdm-prod-0599 --resource-group rg-husky-pdm-prod --display-name "live.com#engineersantoshnair@outlook.com" --object-id ed6b656a-82f9-4609-ab71-8333d50fbe4f -o none
az synapse role assignment list --workspace-name syn-husky-pdm-prod-0599 --query "[].principalId" -o tsv   # expect you + the workspace identity, never the deployer
```
The `synapse` container is created by P1, so A6 must come after it. You'll need your own temporary firewall rule for the last command, and for A7.

## Acceptance criteria and evidence

| # | Criterion | Evidence |
|---|---|---|
| 1 | Its own state | P1 init with `tfstate-prod/husky-prod.tfstate`; `provenance.json` |
| 2 | Its own identity and scope | "OK: Prod identity cannot access rg-husky-pdm-dev" **and** "…rg-husky-pdm-test" |
| 3 | Only tested files promoted | "Promotion check OK: release files are identical to test-passed-2026-11-02", plus the SHA-256 list in the run summary |
| 4 | Approval recorded | `prod-approval` approval with a comment (**self-approval**) |
| 5 | Exact-plan apply | `prod.tfplan: OK`, "Provenance OK", then apply |
| 6 | No-change after apply | "Post-apply plan: No changes."; P5 skips approval and apply |
| 7 | Admin-only prerequisites in place | release preflight: "ADX preflight OK", "Synapse SQL admin is not the deployer" |
| 8 | Smoke | P4: one IMM-900 event reaches Bronze/Silver, raw archive, Parquet and Synapse; views read the lake |
| 9 | Dev and Test untouched | criterion 2, plus separate state containers |

**Not covered:** read-only reconciliation (Bronze = Silver + Quarantine). The draft `tests/integration/test_data_health.py` has never run successfully anywhere, so it isn't part of Prod. Run it in Test first if you want it here.

## Rollback and recovery

| Situation | Action |
|---|---|
| A bad **application** release | Roll forward, or re-promote the previous tested release: set `TESTED_RELEASE_TAG` to the earlier `test-passed-*` tag, tag a commit whose release files match it as `prod-release-…`, and run `deploy-app-prod.yml`. KQL and views are create-or-alter, so this restores the old definitions. The export is create-only and isn't touched. |
| A release fails halfway | Not transactional: fix and re-run ([runbooks.md §5](runbooks.md#5-a-release-fails-halfway)) |
| Infrastructure drift or a bad change | Reviewed plan through `deploy-prod-approved.yml`. Deletes are blocked; replacing anything needs a separate, deliberate procedure. |
| Data lost downstream | Replay from the `raw` archive; backfill with `SilverRows()` / `QuarantineRows()` ([runbooks.md §3](runbooks.md#3-rows-in-bronze-but-missing-from-silver-or-quarantine)) |
| ADX stopped, permissions, export, Synapse errors | [runbooks.md](runbooks.md) §1, §4, §6, §8 |

## Clean-up (admin only, not through the workflow)

1. Keep the evidence: run IDs, approval screenshots, run summaries.
2. Locally in `infra/terraform/envs/prod`, initialised against `tfstate-prod`: `terraform state rm module.platform.azurerm_kusto_database.pdm` (because `prevent_destroy` blocks deleting it; it goes with its cluster), then `terraform plan -destroy "-out=destroy.tfplan"`. **Read it**: Prod resources only. Then `terraform apply destroy.tfplan`.
3. Delete the admin-created Synapse workspace: `az synapse workspace delete --name syn-husky-pdm-prod-0599 --resource-group rg-husky-pdm-prod`.
4. Remove the manual pieces: the deployer's role assignments (including `raw`), the custom role, the app `sp-husky-pdm-prod`, the resource group, the GitHub `prod` and `prod-approval` environments, and the `husky-prod.tfstate` blob.

## Estimated cost

Same sizes as Test. Azure retail list prices, checked 2026-11-01.

| Resource | Price | Billed when idle? |
|---|---|---|
| ADX Dev SKU (E2a v4) | about **$0.126/hour** while running | compute: no, when stopped; storage: yes (cents) |
| IoT Hub B1 | **$10/month** | **yes**, as long as it exists |
| Synapse serverless | $5 per TB scanned (these checks scan about 1 MB) | no |
| Storage, Log Analytics (0.1 GB/day cap), 2 metric alerts | cents | yes (negligible) |

| Scenario | Estimate |
|---|---|
| One Prod practice day, ADX on about 3 h | about $0.75 |
| Keep Prod one week, ADX on about 6 h in total | about $3 |
| **Forget to stop ADX** | about **+$3 per day** |

Running Dev, Test and Prod together roughly triples the ADX cost. Keep only one cluster running at a time.

## Residual risks

All of these are the same as in [test-environment.md](test-environment.md#residual-privilege-escalation-paths):
- storage and IoT Hub keys
- the role-grant permission can give blob roles to *other* service principals
- ARM KQL scripts can't be denied in the role, so the plan check is the control

Prod-specific:
- **Self-approval** (above).
- **`main` has no branch protection.** Prod's tag-only rule controls *which ref* can deploy, not *who* can push. Add branch protection before treating this as more than a lab.
- The `existing` and `none` Synapse modes have only been checked locally (`validate` + guard tests). Their first real run is P1/P3.
