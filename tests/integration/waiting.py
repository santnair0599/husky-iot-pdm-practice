import os
import time


def timeout_from_env(name, default_seconds):
    return int(os.getenv(name, str(default_seconds)))


def wait_until(check, timeout, interval, failure_message):
    """Poll check() until it returns True; ingestion and export are asynchronous."""
    started = time.monotonic()
    deadline = started + timeout

    while True:
        if check():
            elapsed = time.monotonic() - started
            # Recorded so we learn the real latency of each layer
            print(f"Condition met after {elapsed:.0f}s")
            return elapsed

        if time.monotonic() >= deadline:
            raise AssertionError(f"{failure_message} (waited {timeout}s)")

        time.sleep(interval)
