"""The test message must become visible through the Synapse historical view."""
from tests.integration.synapse_client import query_synapse
from tests.integration.waiting import timeout_from_env, wait_until

# ADX ingestion (~5 min) + continuous export every 15 min + a margin
SYNAPSE_TIMEOUT = timeout_from_env("SYNAPSE_WAIT_SECONDS", 1800)


def test_message_exported_to_parquet(message_id):
    sql = """
    SELECT COUNT(*)
    FROM pdm.vw_telemetry_deduplicated
    WHERE MessageId = ?
    """
    wait_until(
        lambda: int(query_synapse(sql, (message_id,))) == 1,
        SYNAPSE_TIMEOUT,
        60,
        f"{message_id} not found in pdm.vw_telemetry_deduplicated",
    )
