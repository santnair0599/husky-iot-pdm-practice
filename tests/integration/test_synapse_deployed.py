"""Checks that the Synapse release deployed working views (Lesson 19B).

Read-only: it only runs SELECT queries, so it is safe to run at any time.
"""
from tests.integration.synapse_client import query_synapse

VIEWS = ["vw_telemetry_deduplicated", "vw_device_daily", "vw_fleet_summary"]


def test_views_exist():
    for view in VIEWS:
        found = query_synapse(
            "SELECT COUNT(*) FROM sys.views "
            "WHERE name = ? AND SCHEMA_NAME(schema_id) = 'pdm'",
            (view,),
        )
        assert int(found) == 1, f"pdm.{view} is missing"


def test_views_read_the_lake():
    for view in VIEWS:
        rows = query_synapse(f"SELECT COUNT(*) FROM pdm.{view}")
        assert int(rows) > 0, f"pdm.{view} returned no rows"
        
