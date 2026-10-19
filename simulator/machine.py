
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
        self.active_fault = None
        
    
    def inject_fault(self, fault_type: str):
        """Activate a supported simulated machine fault."""

        supported_faults = {"bearing_wear"}

        if fault_type not in supported_faults:
            raise ValueError(
                f"Unsupported fault type: {fault_type}"
            )

        self.active_fault = fault_type


    def clear_fault(self):
        """Stop accelerated deterioration."""

        self.active_fault = None


    def advance_time(self, hours: float):
        """Advance simulated machine operation."""

        if hours <= 0:
            raise ValueError("Hours must be positive")

        self.running_hours += hours

        normal_wear_rate = 0.02
        faulty_wear_rate = 0.20

        if self.active_fault == "bearing_wear":
            wear_rate = faulty_wear_rate
        else:
            wear_rate = normal_wear_rate

        self.bearing_wear += wear_rate * hours

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
            "active_fault": self.active_fault,
            "status": "RUNNING"
        }

        return reading


if __name__ == "__main__":

    machine = InjectionMouldingMachine("IMM-001")

    print("=== NORMAL OPERATION ===")

    for _ in range(3):
        machine.advance_time(5)
        reading = machine.generate_reading()

        print(
            f"Hours={reading['running_hours']}, "
            f"Wear={reading['bearing_wear']}, "
            f"Vibration={reading['vibration_mm_s']}"
        )

    print("\n=== BEARING FAULT INJECTED ===")

    machine.inject_fault("bearing_wear")

    for _ in range(3):
        machine.advance_time(5)
        reading = machine.generate_reading()

        print(
            f"Hours={reading['running_hours']}, "
            f"Wear={reading['bearing_wear']}, "
            f"Vibration={reading['vibration_mm_s']}"
        )

    print("\n=== FAULT CLEARED ===")

    machine.clear_fault()
    machine.advance_time(5)

    reading = machine.generate_reading()

    print(
        f"Hours={reading['running_hours']}, "
        f"Wear={reading['bearing_wear']}, "
        f"Vibration={reading['vibration_mm_s']}"
    )
