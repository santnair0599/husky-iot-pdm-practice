"""Inject one malformed event straight into Bronze and prove the update policy quarantines it.

This bypasses IoT Hub and the Python validator on purpose: it tests the ADX
processing layer. Dev/Test only - it refuses to run against a Prod database.
"""
import json
import os
import re
import uuid
from datetime import datetime, timezone

import pytest

from tests.integration.adx_client import database, query_count, run_mgmt
from tests.integration.waiting import wait_until


def test_invalid_temperature_goes_to_quarantine():
    if "prod" in database().lower():
        pytest.fail("Refusing to inject malformed telemetry into a production database")

    device_id = os.getenv("TEST_DEVICE_ID", "IMM-900")
    assert re.fullmatch(r"IMM-[0-9]{3}", device_id), "TEST_DEVICE_ID must look like IMM-123"

    message_id = str(uuid.uuid4())
    payload = {
        "schema_version": "1.0",
        "message_id": message_id,
        "machine_id": device_id,
        "event_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "temperature_c": 300,  # valid range is -20..250, so this must be rejected
        "vibration_mm_s": 2.5,
        "pressure_bar": 140,
        "cycle_time_s": 25,
        "running_hours": 10,
        "status": "RUNNING",
    }

    # json.dumps twice: once for JSON, once to make a safely escaped KQL string literal
    literal = json.dumps(json.dumps(payload))

    run_mgmt(
        f""".set-or-append Telemetry_Raw <|
        print Payload = parse_json({literal}), IoTHubDeviceId = "{device_id}"
        """
    )
    print(f"Injected invalid test event {message_id}")

    wait_until(
        lambda: query_count(f"""
            Telemetry_Quarantine
            | where tostring(Payload.message_id) == "{message_id}"
            | where RejectReason == "INVALID_TEMPERATURE"
            | count
        """) >= 1,
        180,
        10,
        "Invalid event was not quarantined with INVALID_TEMPERATURE",
    )

    silver_count = query_count(f"""
        Telemetry
        | where MessageId == "{message_id}"
        | count
    """)
    assert silver_count == 0, "Malformed event leaked into Silver"
