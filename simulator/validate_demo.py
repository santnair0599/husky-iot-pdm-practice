
from simulator.machine import InjectionMouldingMachine
from simulator.validator import validate_telemetry


machine = InjectionMouldingMachine("IMM-001")

reading = machine.generate_reading()

is_valid, errors = validate_telemetry(reading)

print("Valid message:", is_valid)
print("Errors:", errors)


# Deliberately corrupt the telemetry.
bad_reading = reading.copy()
bad_reading["temperature_c"] = 300

is_valid, errors = validate_telemetry(bad_reading)

print("\nInvalid message:", is_valid)
print("Errors:", errors)
