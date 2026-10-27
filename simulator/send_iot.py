import json
import os 

from azure.iot.device import IoTHubDeviceClient, Message

from simulator.machine import InjectionMouldingMachine
from simulator.validator import validate_telemetry


def build_validated_reading(machine):
    reading = machine.generate_reading()

    is_valid, errors = validate_telemetry(reading)

    if not is_valid:
        raise ValueError(
            f"Telemetry contract failed: {errors}"
        )

    return reading


def send_one_reading():
    connection_string = os.getenv(
        "IOTHUB_DEVICE_CONNECTION_STRING"
    )
    
    if not connection_string:
        raise RuntimeError(
            "Missing IOTHUB_DEVICE_CONNECTION_STRING"
        )
        
    machine = InjectionMouldingMachine("IMM-001")
    
    machine.advance_time(30 / 3600)
    
    reading = build_validated_reading(machine)
    
   

    payload = json.dumps(reading)
    message = Message(payload)
    message.content_type = "application/json"
    message.content_encoding = "utf-8"
    message.message_id = reading["message_id"]
    
    client = IoTHubDeviceClient.create_from_connection_string(
        connection_string
    )

    try:
        print("Connecting to Azure IoT Hub...")
        client.connect()

        print("Sending telemetry...")
        client.send_message(message)

        print("Azure IoT Hub acknowledged the message.")
        print("Device:", reading["machine_id"])
        print("Message ID:", reading["message_id"])
        print("Temperature:", reading["temperature_c"])
        print("Vibration:", reading["vibration_mm_s"])

        return True

    finally:
        client.shutdown()
        
if __name__ == "__main__":
    send_one_reading()