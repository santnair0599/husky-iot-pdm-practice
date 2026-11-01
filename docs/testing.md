# Testing and acceptance evidence

There are two layers of tests:
- **Unit tests** run offline in seconds. They run on every application release.
- **Integration tests** query live Azure. They run only when `RUN_INTEGRATION=1`, which the release workflow sets, so `pytest tests/` on a laptop never touches Azure by accident ([`tests/integration/conftest.py`](../tests/integration/conftest.py)).

Rule used throughout: **a gate is trusted only after it has been made to fail on purpose.**

## Unit tests (40)

| File | Tests | Covers |
|---|---|---|
| [`tests/test_machine.py`](../tests/test_machine.py) | 16 | machine simulation, bearing wear, fault injection and recovery |
| [`tests/test_telemetry_contract.py`](../tests/test_telemetry_contract.py) | 8 | JSON-schema contract v1: valid and invalid readings |
| [`tests/test_deploy_scripts.py`](../tests/test_deploy_scripts.py) | 9 | KQL manifest order, export objects marked create-only, placeholder rendering and refusal of unsafe values, no hard-coded storage account, `ThrowOnErrors`, Synapse view order, `GO`/CRLF splitting, ODBC driver choice |
| [`tests/test_fleet.py`](../tests/test_fleet.py) | 5 | 12-machine fleet, scheduled faults, JSONL output, rejected messages keep their errors |
| [`tests/test_iot_sender.py`](../tests/test_iot_sender.py) | 2 | the sender builds a validated reading and rejects a bad machine ID |

Run them:
```powershell
python -m pytest tests -q        # expect: 40 passed
```

## Integration tests

| File | What it proves | Scope | Waits up to |
|---|---|---|---|
| [`test_kql_deployed.py`](../tests/integration/test_kql_deployed.py) | 3 tables, 8 functions and the raw mapping exist; both update policies are **enabled**, read `Telemetry_Raw` and run the expected function; the external table and continuous export exist | all | — |
| [`test_synapse_deployed.py`](../tests/integration/test_synapse_deployed.py) | the 3 `pdm` views exist, and each returns rows from the lake | `kql-sql`, `full` | — |
| [`test_adx_pipeline.py`](../tests/integration/test_adx_pipeline.py) | the sent message reached Bronze and Silver, and is **not** in Quarantine | `full` | 600 s (`ADX_WAIT_SECONDS`) |
| [`test_quarantine.py`](../tests/integration/test_quarantine.py) | a 300 °C reading injected into Bronze lands in Quarantine with `INVALID_TEMPERATURE`, and **not** in Silver; refuses to run against a database whose name contains `prod` | `full` | 180 s |
| [`test_archive.py`](../tests/integration/test_archive.py) | the sent message exists in the `raw` container | `full` | 300 s (`ARCHIVE_WAIT_SECONDS`) |
| [`test_synapse_reporting.py`](../tests/integration/test_synapse_reporting.py) | the sent message is in `pdm.vw_telemetry_deduplicated`, so it went through the Parquet export | `full` | 1800 s (`SYNAPSE_WAIT_SECONDS`) |

Shared helpers:
- [`waiting.py`](../tests/integration/waiting.py) polls until a condition holds, and prints how long it took.
- [`adx_client.py`](../tests/integration/adx_client.py) and [`synapse_client.py`](../tests/integration/synapse_client.py) connect with `DefaultAzureCredential`. On a laptop that's your `az login`; in CI it's the OIDC deployer.
- `synapse_client.query_synapse` retries up to 3 times, but only when serverless SQL returns no result set ("No results. Previous SQL was not a query"). This was seen twice on cold starts. Real SQL errors fail immediately.

The message ID passed between steps is checked to be a UUID before it's placed in any query ([`conftest.py`](../tests/integration/conftest.py)).

## End-to-end evidence

Run `41313214638`, scope `full`, commit `fe52f1b`, 2026-11-01, 7 m 36 s. It ran as `sp-husky-pdm-dev`.

| Step | Result from the log |
|---|---|
| Unit tests | `40 passed` |
| Verify KQL objects | `5 passed` |
| Verify Synapse views | `2 passed` |
| Send test telemetry | `Message ID: 08600bc9-8f8c-472d-8627-9170ffb3e98b` |
| Verify Bronze and Silver | `3 passed in 325.01s` |
| Verify quarantine | injected `26a9b116-1b87-4d0f-8c10-c835721297bc`, `1 passed` |
| Verify raw archive | `Found in iot-husky-pdm-dev-0599/01/2026/11/01/13/52`, `1 passed` |
| Verify Synapse historical export | `1 passed in 63.49s` |

That's 13 integration tests passed. The timings are from this one run and are not benchmarks.

Earlier releases: `41291855425` (`kql-only`) and `41310902846` (`kql-sql`); see [cicd.md](cicd.md#verified-runs).

## Negative controls: gates made to fail

| Gate | How it was broken | Observed result | Recorded |
|---|---|---|---|
| KQL release (`ThrowOnErrors`) | a temporary function referencing a non-existent column was added to a KQL file and deployed from a laptop | the deploy failed with `SEM0100` (no such column) at "command number 2"; the file was restored with `git restore` | laptop session, 19A |
| KQL object test | a fake function name was added to `FUNCTIONS` | **result not recorded**; treat as unverified | — |
| Synapse release | a `vw_broken_probe` view selecting `NoSuchColumn` was appended to `05_deploy_views.sql` | `Invalid column name 'NoSuchColumn'`, exit code 1, no "completed" line; `pdm` still had exactly 3 views afterwards | laptop session, 19B |
| Synapse view test | `vw_does_not_exist` was added to `VIEWS` | `2 failed` | laptop session, 19B |
| Quarantine routing | built into every `full` run | invalid reading reaches Quarantine and not Silver | every `full` run |
| No-change gate | — | **no recorded run with exit code 2** | — |
| Delete/replace guard | — | **not exercised in a recorded run** | — |

The laptop negative controls ran with the administrator's identity, not the deployer's. They show that the scripts fail correctly; they don't test permissions.

## Lesson 19D (skipped)

Lesson 19D planned two data-health gates and was **skipped by decision**. The draft [`tests/integration/test_data_health.py`](../tests/integration/test_data_health.py) is kept **uncommitted** in the working tree and isn't part of any workflow.

| Test | Checks |
|---|---|
| `test_device_data_is_fresh` | the device's latest Silver row arrived within `FRESHNESS_MAX_MINUTES` (default 60) |
| `test_every_bronze_row_lands_in_silver_or_quarantine` | for Bronze rows from the last `RECON_WINDOW_HOURS` (24), ignoring the newest `RECON_SETTLE_MINUTES` (10): none is missing downstream, and Silver + Quarantine row counts equal Bronze; skips as **UNVERIFIED** if the window is empty |

**Assessment: worth committing, but only after it has run.** It covers the one failure the other tests can't see: a non-transactional update policy silently dropping rows. Before committing it:
1. Run it against live ADX, and record a pass and both negative controls (an unknown device, and a disabled Quarantine policy with one injected row).
2. Decide how to handle the known edge cases:
   - `DownstreamRows` counts every Silver/Quarantine row whose ID appears in the window. A message redelivered outside the window would be counted twice.
   - Rows with an empty `message_id` all share the key `""`.
3. Add a "Verify data health" step to the `full` scope of [`deploy-app-dev.yml`](../.github/workflows/deploy-app-dev.yml).

## Running integration tests from a laptop

```powershell
az login
$env:RUN_INTEGRATION      = "1"
$env:ADX_CLUSTER_URI      = "https://adxhuskypdmdev0599.eastus2.kusto.windows.net"
$env:ADX_DATABASE         = "pdm_dev"
$env:SYNAPSE_SQL_SERVER   = "syn-husky-pdm-dev-0599-ondemand.sql.azuresynapse.net"
$env:SYNAPSE_SQL_DATABASE = "HuskyPDMDev"
python -m pytest tests\integration\test_kql_deployed.py tests\integration\test_synapse_deployed.py -v
```
ADX must be running. The tests that need a sent message (`test_adx_pipeline`, `test_archive`, `test_synapse_reporting`) also need `TEST_MESSAGE_ID`, so they're meant to run inside the workflow.
