
import pytest

from simulator.machine import InjectionMouldingMachine
from simulator.validator import validate_telemetry


@pytest.fixture
def valid_reading():
    machine = InjectionMouldingMachine("IMM-001")
    return machine.generate_reading()


def test_valid_telemetry(valid_reading):
    valid, errors = validate_telemetry(valid_reading)

    assert valid is True
    assert errors == []


def test_missing_required_field(valid_reading):
    valid_reading.pop("machine_id")

    valid, errors = validate_telemetry(valid_reading)

    assert valid is False
    assert errors


def test_invalid_temperature(valid_reading):
    valid_reading["temperature_c"] = 300

    valid, errors = validate_telemetry(valid_reading)

    assert valid is False
    assert errors


def test_invalid_machine_id(valid_reading):
    valid_reading["machine_id"] = "UNKNOWN"

    valid, errors = validate_telemetry(valid_reading)

    assert valid is False
    assert errors


def test_wrong_schema_version(valid_reading):
    valid_reading["schema_version"] = "2.0"

    valid, errors = validate_telemetry(valid_reading)

    assert valid is False
    assert errors


def test_unexpected_field(valid_reading):
    valid_reading["secret_debug_field"] = "test"

    valid, errors = validate_telemetry(valid_reading)

    assert valid is False
    assert errors


def test_invalid_message_uuid(valid_reading):
    valid_reading["message_id"] = "not-a-uuid"

    valid, errors = validate_telemetry(valid_reading)

    assert valid is False
    assert errors


def test_invalid_timestamp(valid_reading):
    valid_reading["event_time"] = "yesterday"

    valid, errors = validate_telemetry(valid_reading)

    assert valid is False
    assert errors
