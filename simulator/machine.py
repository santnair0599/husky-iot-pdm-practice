
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
        
        self.temperature_fault_offset = 0.0
        self.pressure_fault_offset = 0.0
        self.stuck_temperature = None
        self.spike_pending = False
        
    
    
    def inject_fault(self, fault_type: str):
        """Inject one supported machine fault."""

        supported_faults = {
        "bearing_wear",
        "overheating",
        "seal_leak",
        "stuck_sensor",
        "spike"
        }

        if fault_type not in supported_faults:
            raise ValueError(
            f"Unsupported fault type: {fault_type}"
            )

        self.active_fault = fault_type

        if fault_type == "stuck_sensor":
            self.stuck_temperature = None

        if fault_type == "spike":
            self.spike_pending = True


    def clear_fault(self):
        """Stop the active fault without repairing accumulated wear."""

        self.active_fault = None
        self.stuck_temperature = None
        self.spike_pending = False
        

    
    def advance_time(self, hours: float):
        """Advance operating time and fault progression."""

        if hours <= 0:
            raise ValueError("Hours must be positive")

        self.running_hours += hours

        if self.active_fault == "bearing_wear":
            wear_rate = 0.20
        else:
            wear_rate = 0.02

        self.bearing_wear += wear_rate * hours

        if self.active_fault == "overheating":
            self.temperature_fault_offset += 1.5 * hours

        if self.active_fault == "seal_leak":
            self.pressure_fault_offset += 2.0 * hours


    
    def generate_reading(self) -> dict:
        """Generate telemetry based on machine condition."""

        temperature = round(
        random.uniform(70, 80)
        + self.temperature_fault_offset,
        2
        )

        vibration = round(
        random.uniform(1.5, 3.5)
        + self.bearing_wear,
        2
        )

        pressure = round(
        max(
            0,
            random.uniform(130, 150)
            - self.pressure_fault_offset
        ),
        2
        )

        cycle_time = round(
        random.uniform(20, 28), 2
        )

        # Simulate a stuck temperature sensor.
        if self.active_fault == "stuck_sensor":
            if self.stuck_temperature is None:
                self.stuck_temperature = temperature

            temperature = self.stuck_temperature

        # One-shot vibration spike.
        if self.spike_pending:
            vibration = round(vibration + 15.0, 2)
            self.spike_pending = False

        if self.active_fault == "spike":
            self.active_fault = None

        reading = {
        "message_id": str(uuid.uuid4()),
        "machine_id": self.machine_id,
        "event_time": datetime.now(
            timezone.utc
        ).isoformat(),
        "temperature_c": temperature,
        "vibration_mm_s": vibration,
        "pressure_bar": pressure,
        "cycle_time_s": cycle_time,
        "running_hours": round(self.running_hours, 2),
        "bearing_wear": round(self.bearing_wear, 4),
        "active_fault": self.active_fault,
        "status": "RUNNING"
        }

        return reading



if __name__ == "__main__":

    for fault in [
        "bearing_wear",
        "overheating",
        "seal_leak",
        "stuck_sensor",
        "spike"
    ]:
        machine = InjectionMouldingMachine("IMM-001")

        machine.inject_fault(fault)

        print(f"\n=== {fault.upper()} ===")

        for i in range(5):
            machine.advance_time(2)

            reading = machine.generate_reading()

            print(
                f"Hour={reading['running_hours']}, "
                f"Temp={reading['temperature_c']}, "
                f"Vib={reading['vibration_mm_s']}, "
                f"Pressure={reading['pressure_bar']}"
            )
