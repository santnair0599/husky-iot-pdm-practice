"""Fast checks on the release scripts and manifests - no Azure needed."""
from pathlib import Path

import pytest

from scripts import deploy_kql, deploy_synapse

ROOT = Path(__file__).resolve().parents[1]


def test_kql_manifest_files_exist_in_order():
    files = [entry["file"] for entry in deploy_kql.read_manifest()]
    for name in files:
        assert (ROOT / "kql" / name).is_file(), name
    # Tables and functions must exist before the policies that use them
    assert files.index("02_silver_quarantine_tables.kql") < files.index("04_update_policies.kql")
    assert files.index("03_validation_functions.kql") < files.index("04_update_policies.kql")
    assert files.index("11_external_parquet.kql") < files.index("12_continuous_export.kql")


def test_export_objects_are_create_only():
    modes = {e["file"]: e["create_only"] for e in deploy_kql.read_manifest()}
    assert modes["11_external_parquet.kql"] == ("external-table", "TelemetryParquet")
    assert modes["12_continuous_export.kql"] == ("continuous-export", "TelemetryHistoricalExport")
    assert modes["04_update_policies.kql"] is None


def test_all_kql_renders_with_storage_account():
    scripts = deploy_kql.load_scripts({"ADLS_ACCOUNT_NAME": "sttestaccount01"})
    rendered = {entry["file"]: text for entry, text in scripts}
    assert "https://sttestaccount01.blob.core.windows.net/curated" in rendered["11_external_parquet.kql"]
    assert all("{{" not in text for text in rendered.values())
    assert all("\r" not in text for text in rendered.values())


def test_render_refuses_missing_or_unsafe_values():
    with pytest.raises(ValueError):
        deploy_kql.render("x {{ADLS_ACCOUNT_NAME}}", {})
    with pytest.raises(ValueError):
        deploy_kql.render("x {{ADLS_ACCOUNT_NAME}}", {"ADLS_ACCOUNT_NAME": "bad;name"})
    with pytest.raises(ValueError):
        deploy_kql.render("x {{SOMETHING_ELSE}}", {"SOMETHING_ELSE": "abc"})


def test_no_hard_coded_storage_account_in_kql():
    for path in (ROOT / "kql").glob("*.kql"):
        text = path.read_text(encoding="utf-8").replace("{{ADLS_ACCOUNT_NAME}}", "")
        assert "sthuskypdm" not in text, f"{path.name} hard-codes a storage account"


def test_execute_script_command_throws_on_errors():
    command = deploy_kql.build_command(".create-merge table T (A: string)")
    assert command.startswith(".execute database script with (ThrowOnErrors=true) <|\n")


def test_synapse_views_deploy_in_dependency_order():
    batches = deploy_synapse.load_batches()
    views = [
        batch.split("CREATE OR ALTER VIEW", 1)[1].split()[0]
        for _, batch in batches
    ]
    assert views == [
        "pdm.vw_telemetry_deduplicated",
        "pdm.vw_device_daily",
        "pdm.vw_fleet_summary",
    ]


def test_split_batches_handles_go_and_crlf():
    sql = "SELECT 1\r\nGO\r\n\r\nSELECT 2\r\ngo\r\n"
    assert deploy_synapse.split_batches(sql) == ["SELECT 1", "SELECT 2"]


def test_pick_driver_prefers_18():
    assert deploy_synapse.pick_driver(
        ["ODBC Driver 17 for SQL Server", "ODBC Driver 18 for SQL Server"]
    ) == "ODBC Driver 18 for SQL Server"
    with pytest.raises(RuntimeError):
        deploy_synapse.pick_driver(["SQL Server"])
