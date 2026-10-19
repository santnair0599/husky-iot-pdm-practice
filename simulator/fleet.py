
import json
import time

from pathlib import Path

from simulator.machine import InjectionMouldingMachine
from simulator.validator import validate_telemetry


class MachineFleet:

    def __init__(
        self,
        machine_count=12,
        interval_seconds=30,
        operating_hours_per_step=None
    ):
        if machine_count <= 0:
            raise ValueError("machine_count must be positive")

        if interval_seconds <= 0:
            raise ValueError("interval_seconds must be positive")

        self.interval_seconds = interval_seconds

        # By default, simulated time matches wall-clock time.
        self.hours_per_step = (
            operating_hours_per_step
            if operating_hours_per_step is not None
            else interval_seconds / 3600
        )

        if self.hours_per_step <= 0:
            raise ValueError("operating_hours_per_step must be positive")

        self.machines = {
            f"IMM-{i:03d}": InjectionMouldingMachine(
                f"IMM-{i:03d}"
            )
            for i in range(1, machine_count + 1)
        }

        # tick -> list of fault activation events
        self.fault_schedule = {}

    def schedule_fault(
        self,
        tick: int,
        machine_id: str,
        fault_type: str
    ):
        if tick < 1:
            raise ValueError("tick must be >= 1")

        if machine_id not in self.machines:
            raise ValueError(f"Unknown machine: {machine_id}")

        supported = {
            "bearing_wear",
            "overheating",
            "seal_leak",
            "stuck_sensor",
            "spike"
        }

        if fault_type not in supported:
            raise ValueError(f"Unknown fault: {fault_type}")

        event = {
            "machine_id": machine_id,
            "fault_type": fault_type
        }

        self.fault_schedule.setdefault(tick, []).append(event)

    def run_tick(self, tick: int):
        """Generate one reading from every machine."""

        if tick < 1:
            raise ValueError("tick must be >= 1")

        # Activate any faults scheduled for this tick.
        for event in self.fault_schedule.get(tick, []):
            machine = self.machines[event["machine_id"]]

            machine.inject_fault(event["fault_type"])

        readings = []

        for machine in self.machines.values():
            machine.advance_time(self.hours_per_step)
            readings.append(machine.generate_reading())

        return readings

    def run(
        self,
        ticks: int,
        output_dir="data",
        sleep_between_ticks=False
    ):
        if ticks <= 0:
            raise ValueError("ticks must be positive")

        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)

        telemetry_file = output_path / "telemetry.jsonl"
        rejected_file = output_path / "rejected.jsonl"

        valid_count = 0
        rejected_count = 0

        with (
            telemetry_file.open("w", encoding="utf-8") as good,
            rejected_file.open("w", encoding="utf-8") as rejected
        ):
            for tick in range(1, ticks + 1):

                readings = self.run_tick(tick)

                for reading in readings:
                    is_valid, errors = validate_telemetry(reading)

                    if is_valid:
                        good.write(json.dumps(reading) + "\n")
                        valid_count += 1
                    else:
                        rejected.write(
                            json.dumps({
                                "tick": tick,
                                "reading": reading,
                                "errors": errors
                            }) + "\n"
                        )
                        rejected_count += 1

                if sleep_between_ticks and tick < ticks:
                    time.sleep(self.interval_seconds)

        return {
            "total": valid_count + rejected_count,
            "valid": valid_count,
            "rejected": rejected_count,
            "telemetry_file": str(telemetry_file),
            "rejected_file": str(rejected_file)
        }
