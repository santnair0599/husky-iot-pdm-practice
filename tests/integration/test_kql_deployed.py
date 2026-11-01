import json

from tests.integration.adx_client import run_mgmt

TABLES = {"Telemetry_Raw", "Telemetry", "Telemetry_Quarantine"}
FUNCTIONS = {
    "ValidateTelemetryRows", "SilverRows", "QuarantineRows", "TelemetryDeduplicated",
    "DeviceHealth", "VibrationAnomalies", "VibrationForecast", "MaintenanceAlerts",
}


def names(command, column):
    return {row[column] for row in run_mgmt(command).primary_results[0]}


def test_tables_exist():
    missing = TABLES - names(".show tables", "TableName")
    assert not missing, f"Missing tables: {missing}"


def test_functions_exist():
    missing = FUNCTIONS - names(".show functions", "Name")
    assert not missing, f"Missing functions: {missing}"


def test_raw_ingestion_mapping_exists():
    mappings = names(".show table Telemetry_Raw ingestion json mappings", "Name")
    assert "TelemetryRawMapping" in mappings


def test_update_policies_read_bronze():
    for table, query in [("Telemetry", "SilverRows()"),
                         ("Telemetry_Quarantine", "QuarantineRows()")]:
        rows = list(run_mgmt(f".show table {table} policy update").primary_results[0])
        policy = json.loads(rows[0]["Policy"])[0]
        assert policy["IsEnabled"], f"{table} update policy is disabled"
        assert policy["Source"] == "Telemetry_Raw", f"{table} reads {policy['Source']}"
        assert policy["Query"] == query, f"{table} runs {policy['Query']}"


def test_lake_export_exists():
    assert "TelemetryParquet" in names(".show external tables", "TableName")
    assert "TelemetryHistoricalExport" in names(".show continuous-exports", "Name")