# Prod environment (Lesson 18C-P)

> **Status (2026-11-02): deployed and verified.** Infrastructure, application release and smoke test all passed, and a later plan found no drift (evidence below).
>
> **Approval is self-approval.** The `prod-approval` reviewer is the same person who triggers the run. That's a recorded human gate, **not independent review**. In a team, add a second reviewer and turn on "Prevent self-review".
>
> **Reconciliation has NOT been verified.** No check that Bronze = Silver + Quarantine has run in any environment (see [Acceptance criteria](#acceptance-criteria-and-evidence)).

Prod promotes **exactly** what passed Test:
- Test tag **`test-passed-2026-11-02`** (commit `86fad6d`): Test run `41401561043`, 13 of 13 integration tests passed
- Prod release tag **`prod-release-2026-11-02-1`** (commit `a470b89`), which contains that tag and has identical release files

It reuses the Test design, plus fixes for the problems Test uncovered.

## Deployment evidence

Every Prod run below ran from tag `prod-release-2026-11-02-1` (commit `a470b89`) as `sp-husky-pdm-prod`, and every log showed **0 errors and no secret values**.

| # | Run | Workflow | Result | Key log lines |
|---|---|---|---|---|
| P1 | `41412119364` | approved Terraform | success | `Release prod-release-2026-11-02-1 contains tested release test-passed-2026-11-02`; `OK: Prod identity cannot access rg-husky-pdm-dev` / `…rg-husky-pdm-test`; `ADX state: NotCreated`; `prod.tfplan: OK`; `Provenance OK … environment prod`; **`Apply complete! Resources: 20 added, 0 changed, 0 destroyed.`**; `Post-apply plan: No changes.` |
| P2 | `41417893719` | app release `kql-only` | success | **`Promotion check OK: release files are identical to test-passed-2026-11-02`**; `ADX preflight OK`; 11 and 12 `Completed` (first time), skipped on re-run; `Verify KQL objects: 5 passed` |
| P3 | `41418285822` | approved Terraform | success | only `azurerm_kusto_iothub_data_connection.telemetry[0]` created; `1 added`; no-change after |
| P3b | `41432917752` | approved Terraform (`synapse_mode = existing`) | success | 2 storage roles for the admin-created workspace's identity; `2 added`; **`OK: Synapse SQL admin is ed6b656a… (not the deployer)`** |
| P4 | `41436746679` | app release `smoke` | **failure** | everything up to the test send passed; the send failed with `Invalid Connection String - Invalid Key` (damaged secret, see [problems](#problems-found-in-the-real-deployments)) |
| P4 | **`41437359315`** | **app release `smoke`** | **success** | promotion check OK; preflight OK; first Prod Synapse deploy twice (`3` batches); message `8a108231-…` → Bronze in 340 s → Silver; raw archive `iot-husky-pdm-prod-0599/01/2026/11/02/11`; `No Parquet folder yet; waiting` → export passed (66 s); views read the lake; firewall rule removed |
| P5 | **`41440910246`** | approved Terraform | success | **`No changes: approval and apply will be skipped.`** Isolation from Dev and Test proven again. |

**Approvals recorded on `prod-approval`, all by `santnair0599` (self-approval):**

| Run | Comment |
|---|---|
| `41412119364` | none. The reviewer left the comment empty, which is a gap in the record. |
| `41418285822` | *"P3: adds IoT Hub -> ADX data connection only (1 add, 0 change/destroy). Self-approved."* |
| `41432917752` | *"Synapse existing mode: 2 storage roles for workspace identity 25e6c6c5; workspace itself not managed by Terraform. Self-approved."* |

**Admin steps completed by hand:**
- A1–A4: resource group; app `sp-husky-pdm-prod` (`64678ee8…`) with credential `…:environment:prod`; custom role, `tfstate-prod` access and the role-grant condition excluding `29d54faa…`; GitHub `prod` and `prod-approval` limited to tags `prod-release-*`, with 23 variables
- A5: you as AllDatabasesAdmin; cluster identity `72be438e…` as Viewer on `pdm_prod`; managed identity policy `AutomatedFlows`. The deployer is Admin on `pdm_prod` only.
- A6: workspace `syn-husky-pdm-prod-0599` created by the admin, Entra-only, with the admin as SQL admin
- A7: `HuskyPDMProd` with the deployer's 6 grants (no `db_owner`)
- A8: device `IMM-900`; deployer Blob Data Reader on `raw`

## Problems found in the real deployments

Each problem was found by a failing run or a check, fixed at its cause, and, where possible, turned into an automatic check.

| # | Found in | Problem | Evidence | Fix |
|---|---|---|---|---|
| 1 | Test | ADX continuous export refused: *"managed identity 'system' … is not authorized to access the database"* | Test runs `41340635265`, `41341166102` | admin step: the cluster policy `managed_identity` allows `AutomatedFlows`, **and** the cluster's own identity is **Viewer** on the database. (Dev had this Viewer role, but it had never been written down.) Prod's **preflight** now checks it before deploying. |
| 2 | Test | the pipeline created the Synapse workspace, so it became the **only Synapse Administrator and the Entra SQL admin**. The human admin couldn't log in (`18456`) or use Studio. | Test; handover run `41338201298` | a one-time, reviewed handover workflow (PR #2) granted the human Synapse Administrator, then the human removed the deployer's role (PR #3 deleted the workflow). In **Prod the admin creates the workspace**: Terraform only reads it (`synapse_mode = existing`), and two automatic checks confirm the deployer isn't the SQL admin. |
| 3 | Prod | **Synapse workspace quota**: `ReachedPerSubscriptionWorkspaceLimit … Current maximum: 2` (Dev and Test held both) | admin step A6 | **targeted retirement of Test's Synapse workspace**, through a reviewed, saved Terraform plan (3 deletions), not a manual delete, so state never drifted. Then the Test no-change run `41428063618`. See [test-synapse-retirement.md](test-synapse-retirement.md). |
| 4 | Test | in a new environment `curated/telemetry/` doesn't exist until the first export, so Synapse raises **13807** and the export test gave up after 1.85 s | Test run `41400247069` | the test waits on 13807 only, and other SQL errors still fail at once (PR #5, checked offline with 3 scenarios). The lake-read check moved after the export (PR #4). **Proven in Prod**: `No Parquet folder yet; waiting` → passed. |
| 5 | Prod | the device secret was damaged on its way into GitHub: *"Invalid Connection String - Invalid Key"*. Windows PowerShell 5.1 re-encodes text piped (`|`) into another program. The Azure value itself checked out as valid (3 parts, 128 characters, no byte-order mark). | Prod run `41436746679` | set the secret as an argument instead: `$cs = az … -o tsv; gh secret set … -b $cs; Remove-Variable cs`. **Don't pipe secrets in Windows PowerShell 5.1.** |
| 6 | Prod | the Synapse data source was created with the literal text `<PROD_STORAGE_ACCOUNT>` (a placeholder left in) | read-only check after A7 | `DROP` and re-`CREATE EXTERNAL DATA SOURCE` with the real URL, before any view used it |

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

## Before Prod: one Test step (done)

The module change had to run in Test once. **Done in Test run `41407963105`**: 3 moved, `0 added, 0 changed, 0 destroyed`, post-apply no-change. So Test ran the exact module Prod uses.

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
| P3 | Admin + Pipeline | set `TF_CREATE_DATA_CONNECTION=true` and `TF_SYNAPSE_MODE=existing`, then run `deploy-prod-approved.yml`. Expect **3 to add** (data connection + 2 Synapse storage roles). Approve. **As executed:** the Synapse quota blocked A6, so P3 ran in two parts: data connection first (`41418285822`, +1), then Synapse `existing` after A6 (`41432917752`, +2). | no |
| A7 | Admin | temporary firewall rule for your IP, run `00_bootstrap_prod.sql` (6 grants), remove the rule. **Replace both `<…>` placeholders**, including the storage account in the data source. | no |
| A8 | Admin | IoT device `IMM-900` in the Prod hub; set secret `IOTHUB_DEVICE_CONNECTION_STRING` (`prod`) **as an argument, not through a pipe**: `$cs = az iot hub device-identity connection-string show … -o tsv; gh secret set IOTHUB_DEVICE_CONNECTION_STRING -e prod -b $cs; Remove-Variable cs`. Storage Blob Data Reader on Prod `raw` for the deployer. | no |
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

| # | Criterion | Evidence | Result |
|---|---|---|---|
| 1 | Its own state | init with `tfstate-prod/husky-prod.tfstate`; `provenance.json` | ✅ P1 `41412119364` |
| 2 | Its own identity and scope | "OK: Prod identity cannot access rg-husky-pdm-dev" **and** "…rg-husky-pdm-test" | ✅ every infra run, including P5 `41440910246` |
| 3 | Only tested files promoted | "Promotion check OK: release files are identical to test-passed-2026-11-02", plus the SHA-256 list in the run summary | ✅ `41417893719`, `41437359315` |
| 4 | Approval recorded | `prod-approval` approval | ✅ 3 approvals, **self-approval**; P1's comment is empty |
| 5 | Exact-plan apply | `prod.tfplan: OK`, "Provenance OK", then apply | ✅ `41412119364`, `41418285822`, `41432917752` |
| 6 | No-change after apply | "Post-apply plan: No changes."; P5 skips approval and apply | ✅ all three applies, plus **P5 `41440910246`** |
| 7 | Admin-only prerequisites in place | release preflight: "ADX preflight OK", "Synapse SQL admin is not the deployer" | ✅ `41437359315` (and post-apply in `41432917752`) |
| 8 | Smoke | one IMM-900 event reaches Bronze/Silver, raw archive, Parquet and Synapse; views read the lake | ✅ **`41437359315`** |
| 9 | Dev and Test untouched | criterion 2, plus separate state containers | ✅ |
| 10 | **Reconciliation** (Bronze = Silver + Quarantine) | — | ❌ **NOT VERIFIED** |

**Reconciliation has not been verified anywhere.** The draft `tests/integration/test_data_health.py` (Lesson 19D) is uncommitted and has never run successfully in any environment, so Prod's acceptance doesn't include it.

Next step: prove it in Test, which still has ADX. Run it once to pass, then twice with deliberate failures (an unknown device; a disabled Quarantine policy plus one injected row). Only then run it **read-only** in Prod.

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

Running Dev, Test and Prod together roughly triples the ADX cost. Keep only one cluster running at a time. Stop and start commands, and what keeps billing while idle: [runbooks.md §9](runbooks.md#9-cost-control-and-clean-up).

## Residual risks

All of these are the same as in [test-environment.md](test-environment.md#residual-privilege-escalation-paths):
- storage and IoT Hub keys
- the role-grant permission can give blob roles to *other* service principals
- ARM KQL scripts can't be denied in the role, so the plan check is the control

Prod-specific:
- **Self-approval** (above).
- **`main` has no branch protection.** Prod's tag-only rule controls *which ref* can deploy, not *who* can push. Add branch protection before treating this as more than a lab.
- The `none` and `existing` Synapse modes are now **proven in Prod**: P1 (`none`) and `41432917752` (`existing`, +2 roles, post-apply SQL-admin check OK). `create` is proven in Test.
