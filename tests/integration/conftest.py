"""Integration tests talk to live Azure, so they only run when asked to.

    $env:RUN_INTEGRATION = "1"   (PowerShell)   or   RUN_INTEGRATION: "1"   (workflow)

Without it, `python -m pytest tests/` runs only the fast unit tests.
"""
import os
import uuid

import pytest

if os.getenv("RUN_INTEGRATION") != "1":
    collect_ignore_glob = ["test_*.py"]


@pytest.fixture(scope="session")
def message_id():
    value = os.environ.get("TEST_MESSAGE_ID", "")
    try:
        # A UUID check also makes the value safe to place inside a KQL string
        return str(uuid.UUID(value))
    except ValueError:
        pytest.fail(f"TEST_MESSAGE_ID must be a UUID, got {value!r}")
