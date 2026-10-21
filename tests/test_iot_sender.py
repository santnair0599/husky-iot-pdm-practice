
import pytest

from simulator.machine import InjectionMouldingMachine
from simulator.send_iot import build_validated_reading


def test_build_validated_reading():
    machine = InjectionMouldingMachine("IMM-001")

    reading = build_validated_reading(machine)

    assert reading["machine_id"] == "IMM-001"
    assert reading["schema_version"] == "1.0"


def test_reject_bad_machine_id():
    machine = InjectionMouldingMachine("INVALID")

    with pytest.raises(ValueError):
        build_validated_reading(machine)
