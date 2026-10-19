
from datetime import datetime

from simulator.machine import InjectionMouldingMachine
import pytest


def test_machine_id():
    machine = InjectionMouldingMachine("IMM-001")

    reading = machine.generate_reading()

    assert reading["machine_id"] == "IMM-001"


def test_reading_within_normal_range():
    machine = InjectionMouldingMachine("IMM-001")

    reading = machine.generate_reading()

    assert 70 <= reading["temperature_c"] <= 80
    assert 1.5 <= reading["vibration_mm_s"] <= 3.5
    assert 130 <= reading["pressure_bar"] <= 150
    assert 20 <= reading["cycle_time_s"] <= 28


def test_message_ids_are_unique():
    machine = InjectionMouldingMachine("IMM-001")

    reading1 = machine.generate_reading()
    reading2 = machine.generate_reading()

    assert reading1["message_id"] != reading2["message_id"]


def test_event_time_is_timezone_aware():
    machine = InjectionMouldingMachine("IMM-001")

    reading = machine.generate_reading()
    timestamp = datetime.fromisoformat(reading["event_time"])

    assert timestamp.utcoffset() is not None


def test_machine_status():
    machine = InjectionMouldingMachine("IMM-001")

    reading = machine.generate_reading()

    assert reading["status"] == "RUNNING"
    

def test_bearing_wear_increases_over_time():
    machine = InjectionMouldingMachine("IMM-001")

    initial_wear = machine.bearing_wear

    machine.advance_time(10)

    assert machine.running_hours == 10
    assert machine.bearing_wear > initial_wear
    
def test_reject_invalid_time():
    machine = InjectionMouldingMachine("IMM-001")
    with pytest.raises(ValueError):
        machine.advance_time(-5)


def test_inject_bearing_fault():
    machine = InjectionMouldingMachine("IMM-001")

    machine.inject_fault("bearing_wear")

    assert machine.active_fault == "bearing_wear"


def test_fault_accelerates_wear():
    normal_machine = InjectionMouldingMachine("IMM-001")
    faulty_machine = InjectionMouldingMachine("IMM-002")

    faulty_machine.inject_fault("bearing_wear")

    normal_machine.advance_time(10)
    faulty_machine.advance_time(10)

    assert (
        faulty_machine.bearing_wear
        > normal_machine.bearing_wear
    )

    assert faulty_machine.bearing_wear == pytest.approx(2.0)
    assert normal_machine.bearing_wear == pytest.approx(0.2)


def test_clear_fault():
    machine = InjectionMouldingMachine("IMM-001")

    machine.inject_fault("bearing_wear")
    machine.advance_time(5)

    wear_before_clear = machine.bearing_wear

    machine.clear_fault()

    assert machine.active_fault is None
    assert machine.bearing_wear == wear_before_clear

    machine.advance_time(5)

    assert machine.bearing_wear == pytest.approx(
        wear_before_clear + 0.1
    )


def test_reject_unsupported_fault():
    machine = InjectionMouldingMachine("IMM-001")

    with pytest.raises(ValueError):
        machine.inject_fault("engine_failure")
