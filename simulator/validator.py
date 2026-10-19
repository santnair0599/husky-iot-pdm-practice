
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


SCHEMA_PATH = (
    Path(__file__).resolve().parents[1]
    / "contracts"
    / "telemetry_v1.schema.json"
)


with open(SCHEMA_PATH, encoding="utf-8") as file:
    TELEMETRY_SCHEMA = json.load(file)


# Check whether the schema itself is valid.
Draft202012Validator.check_schema(TELEMETRY_SCHEMA)

validator = Draft202012Validator(
    TELEMETRY_SCHEMA,
    format_checker=FormatChecker()
)


def validate_telemetry(reading: dict):
    """
    Return (is_valid, errors) for a telemetry event.
    """

    errors = sorted(
        validator.iter_errors(reading),
        key=lambda error: str(error.path)
    )

    messages = [error.message for error in errors]

    return len(messages) == 0, messages
