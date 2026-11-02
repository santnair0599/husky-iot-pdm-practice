"""The test message must become visible through the Synapse historical view."""
import pyodbc

from tests.integration.synapse_client import query_synapse
from tests.integration.waiting import timeout_from_env, wait_until

# ADX ingestion (~5 min) + continuous export every 15 min + a margin
SYNAPSE_TIMEOUT = timeout_from_env("SYNAPSE_WAIT_SECONDS", 1800)

# Synapse error 13807: "Content of directory on path ... cannot be listed".
# In a new environment curated/telemetry/ does not exist until the first export.
FOLDER_NOT_THERE_YET = "13807"


def test_message_exported_to_parquet(message_id):
    sql = """
    SELECT COUNT(*)
    FROM pdm.vw_telemetry_deduplicated
    WHERE MessageId = ?
    """

    def exported():
        try:
            return int(query_synapse(sql, (message_id,))) == 1
        except pyodbc.ProgrammingError as error:
            # Keep waiting only for the not-yet-exported case; anything else is a real failure
            if FOLDER_NOT_THERE_YET in str(error):
                print("No Parquet folder yet; waiting for the first export")
                return False
            raise

    wait_until(
        exported,
        SYNAPSE_TIMEOUT,
        60,
        f"{message_id} not found in pdm.vw_telemetry_deduplicated",
    )
