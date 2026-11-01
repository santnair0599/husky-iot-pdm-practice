import os
import time

from scripts.deploy_synapse import connect


def query_synapse(sql, params=(), attempts=3):
    """Return the first value of the first result set.

    Serverless SQL sometimes answers a cold query with no result set
    ("No results. Previous SQL was not a query"), so retry that case only.
    Real SQL errors (bad column, missing view) still fail immediately.
    """
    for attempt in range(1, attempts + 1):
        with connect(
            os.environ["SYNAPSE_SQL_SERVER"],
            os.environ["SYNAPSE_SQL_DATABASE"],
        ) as connection:
            cursor = connection.cursor()
            cursor.execute(sql, *params)
            # Skip any non-query results that come before the real result set
            while cursor.description is None and cursor.nextset():
                pass
            if cursor.description is not None:
                return cursor.fetchone()[0]
        if attempt < attempts:
            print(f"Synapse returned no result set, retrying ({attempt}/{attempts})")
            time.sleep(10)
    raise RuntimeError(f"Synapse returned no result set after {attempts} attempts: {sql}")