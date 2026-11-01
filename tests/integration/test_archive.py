"""The IoT Hub archive route must have written the test message to the raw container."""
import os
from datetime import datetime, timedelta, timezone

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from tests.integration.waiting import timeout_from_env, wait_until

ARCHIVE_TIMEOUT = timeout_from_env("ARCHIVE_WAIT_SECONDS", 300)
LOOKBACK = timedelta(minutes=60)


def test_archive_contains_test_message(message_id):
    service = BlobServiceClient(
        account_url=f"https://{os.environ['ADLS_ACCOUNT_NAME']}.blob.core.windows.net",
        credential=DefaultAzureCredential(),
    )
    container = service.get_container_client("raw")
    since = datetime.now(timezone.utc) - LOOKBACK
    needle = message_id.encode("utf-8")

    def message_archived():
        # Dev lab only: scan recent small files. Never scan a whole production lake.
        for blob in container.list_blobs():
            if blob.last_modified < since or blob.size > 5_000_000:
                continue
            if needle in container.download_blob(blob.name).readall():
                print(f"Found in {blob.name}")
                return True
        return False

    wait_until(
        message_archived,
        ARCHIVE_TIMEOUT,
        20,
        f"{message_id} not found in the raw archive",
    )
