import functools
import os

from azure.identity import DefaultAzureCredential
from azure.kusto.data import KustoClient, KustoConnectionStringBuilder


@functools.lru_cache(maxsize=1)
def get_client():
    connection = KustoConnectionStringBuilder.with_azure_token_credential(
        os.environ["ADX_CLUSTER_URI"],
        DefaultAzureCredential(),
    )
    return KustoClient(connection)


def database():
    return os.environ["ADX_DATABASE"]


def query_scalar(kql):
    response = get_client().execute(database(), kql)
    rows = list(response.primary_results[0])
    if not rows:
        return None
    return rows[0][0]


def query_count(kql):
    return int(query_scalar(kql) or 0)


def run_mgmt(command):
    return get_client().execute_mgmt(database(), command)
