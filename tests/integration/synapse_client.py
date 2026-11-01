import os

from scripts.deploy_synapse import connect


def query_synapse(sql, params=()):
    with connect(
        os.environ["SYNAPSE_SQL_SERVER"],
        os.environ["SYNAPSE_SQL_DATABASE"],
    ) as connection:
        cursor = connection.cursor()
        cursor.execute(sql, *params)
        return cursor.fetchone()[0]
