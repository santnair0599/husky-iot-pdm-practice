import json
from simulator.fleet import MachineFleet

def read_jsonl(path):
    with open(path, encoding="utf-8") as file:
        return [json.loads(line) for line in file]

def test_fleet_has_12_machines():
    fleet = MachineFleet()
    assert len(fleet.machines) == 12
    assert "IMM-001" in fleet.machines
    assert "IMM-012" in fleet.machines

def test_one_tick_generates_12_messages():
    fleet = MachineFleet()
    readings = fleet.run_tick(1)
    assert len(readings) == 12
    assert len({
        r["message_id"] for r in readings
    }) == 12

def test_scheduled_fault():
    fleet = MachineFleet()
    fleet.schedule_fault(
        2, "IMM-001", "bearing_wear"
    )
    fleet.run_tick(1)
    assert fleet.machines["IMM-001"].active_fault is None
    fleet.run_tick(2)
    assert (
        fleet.machines["IMM-001"].active_fault
        == "bearing_wear"
    )

def test_fleet_jsonl_output(tmp_path):
    fleet = MachineFleet()
    result = fleet.run(
        ticks=3,
        output_dir=tmp_path
    )
    readings = read_jsonl(
        tmp_path / "telemetry.jsonl"
    )
    assert result["total"] == 36
    assert result["valid"] == 36
    assert result["rejected"] == 0
    assert len(readings) == 36

def test_rejected_message_preserves_errors(tmp_path, monkeypatch):
    fleet = MachineFleet(machine_count=1)
    machine = fleet.machines["IMM-001"]
    original = machine.generate_reading


    def broken_reading():
        reading = original()
        reading["temperature_c"] = 300
        return reading
    monkeypatch.setattr(
        machine, "generate_reading", broken_reading
    )
    result = fleet.run(
        ticks=1,
        output_dir=tmp_path
    )
    rejected = read_jsonl(
        tmp_path / "rejected.jsonl"
    )
    assert result["valid"] == 0
    assert result["rejected"] == 1
    assert len(rejected) == 1
    assert rejected[0]["reading"]["temperature_c"] == 300
    assert rejected[0]["errors"]