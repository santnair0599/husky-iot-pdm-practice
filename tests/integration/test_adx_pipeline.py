"""One real message, sent through IoT Hub by the workflow, must reach Bronze and Silver."""
from tests.integration.adx_client import query_count
from tests.integration.waiting import timeout_from_env, wait_until

# ADX batches streaming input for up to ~5 minutes in Dev
ADX_TIMEOUT = timeout_from_env("ADX_WAIT_SECONDS", 600)


def test_message_arrived_in_bronze(message_id):
    kql = f"""
    Telemetry_Raw
    | where tostring(Payload.message_id) == "{message_id}"
    | count
    """
    wait_until(
        lambda: query_count(kql) >= 1,
        ADX_TIMEOUT,
        15,
        f"{message_id} did not arrive in Telemetry_Raw",
    )


def test_valid_message_arrived_in_silver(message_id):
    kql = f"""
    Telemetry
    | where MessageId == "{message_id}"
    | count
    """
    # The update policy runs as part of the Bronze ingestion, so this is quick
    wait_until(
        lambda: query_count(kql) >= 1,
        120,
        10,
        f"{message_id} reached Bronze but not Silver",
    )


def test_valid_message_not_quarantined(message_id):
    kql = f"""
    Telemetry_Quarantine
    | where tostring(Payload.message_id) == "{message_id}"
    | count
    """
    assert query_count(kql) == 0
