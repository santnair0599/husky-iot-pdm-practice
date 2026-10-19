
import json
import random
import uuid

from datetime import datetime, timezone


class InjectionMouldingMachine:

    def __init__(self, machine_id: str):
        self.machine_id = machine_id

        # State retained between readings
        self.running_hours = 0.0
        self.bearing_wear = 0.0

    def advance_time(self, hours: float):
        """Simulate machine operation over time."""

        if hours <= 0:
            raise ValueError("Hours must be positive")

        self.running_hours += hours

        # Synthetic wear rate per operating hour
        self.bearing_wear += 0.02 * hours

    def generate_reading(self) -> dict:
        """Generate telemetry using current machine state."""

        reading = {
            "message_id": str(uuid.uuid4()),
            "machine_id": self.machine_id,
            "event_time": datetime.now(
                timezone.utc
            ).isoformat(),
            "temperature_c": round(
                random.uniform(70, 80), 2
            ),
            "vibration_mm_s": round(
                random.uniform(1.5, 3.5)
                + self.bearing_wear, 2
            ),
            "pressure_bar": round(
                random.uniform(130, 150), 2
            ),
            "cycle_time_s": round(
                random.uniform(20, 28), 2
            ),
            "running_hours": round(
                self.running_hours, 2
            ),
            "bearing_wear": round(
                self.bearing_wear, 4
            ),
            "status": "RUNNING"
        }

        return reading


if __name__ == "__main__":

    machine = InjectionMouldingMachine("IMM-001")

    for i in range(6):

        machine.advance_time(10)

        reading = machine.generate_reading()

        print(
            f"Hours: {reading['running_hours']}, "
            f"Wear: {reading['bearing_wear']}, "
            f"Vibration: {reading['vibration_mm_s']} mm/s"
        )
