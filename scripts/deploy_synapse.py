"""Deploy the Synapse serverless SQL listed in deploy/synapse-manifest.txt.

Usage (from the project root):
    python scripts/deploy_synapse.py --dry-run   # split and print batches, no Azure calls
    python scripts/deploy_synapse.py             # deploy

Environment variables:
    SYNAPSE_SQL_SERVER    e.g. syn-husky-pdm-dev-0599-ondemand.sql.azuresynapse.net
    SYNAPSE_SQL_DATABASE  e.g. HuskyPDMDev
"""
import argparse
import os
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "synapse"
MANIFEST = ROOT / "deploy" / "synapse-manifest.txt"

SQL_COPT_SS_ACCESS_TOKEN = 1256
SUPPORTED_DRIVERS = (
    "ODBC Driver 18 for SQL Server",
    "ODBC Driver 17 for SQL Server",
)

# "GO" on its own line ends a batch (it is a client keyword, not T-SQL)
GO_LINE = re.compile(r"^\s*GO\s*;?\s*$", re.IGNORECASE | re.MULTILINE)

# Secrets and privileged bootstrap statements never belong in a release script
FORBIDDEN = re.compile(r"\bPASSWORD\b|\bMASTER\s+KEY\b|\bSECRET\b", re.IGNORECASE)


def read_manifest(path=MANIFEST):
    files = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            files.append(line)
    return files


def split_batches(sql_text):
    sql_text = sql_text.replace("\r\n", "\n")
    return [batch.strip() for batch in GO_LINE.split(sql_text) if batch.strip()]


def load_batches():
    batches = []
    for filename in read_manifest():
        path = SQL_DIR / filename
        if not path.is_file():
            raise FileNotFoundError(f"Manifest lists a missing file: {path}")
        text = path.read_text(encoding="utf-8")
        if FORBIDDEN.search(text):
            raise ValueError(
                f"{filename} contains a password/master-key/secret statement; "
                "keep that in the one-time bootstrap, not the release."
            )
        batches.extend((filename, batch) for batch in split_batches(text))
    return batches


def pick_driver(available):
    for name in SUPPORTED_DRIVERS:
        if name in available:
            return name
    raise RuntimeError(
        "No Microsoft ODBC Driver 18 or 17 for SQL Server is installed. "
        f"Installed drivers: {available}"
    )


def connect(server, database):
    """Open a pyodbc connection with a Microsoft Entra token (no SQL password)."""
    import pyodbc
    from azure.identity import DefaultAzureCredential

    token = DefaultAzureCredential().get_token(
        "https://database.windows.net/.default"
    ).token
    token_bytes = token.encode("utf-16-le")
    token_struct = struct.pack("<I", len(token_bytes)) + token_bytes

    connection_string = (
        f"Driver={{{pick_driver(pyodbc.drivers())}}};"
        f"Server=tcp:{server},1433;"
        f"Database={database};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
    )

    return pyodbc.connect(
        connection_string,
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct},
        autocommit=True,
        timeout=30,
    )


def first_line(batch):
    return batch.splitlines()[0][:80]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="split the SQL into batches and print them without connecting",
    )
    args = parser.parse_args(argv)

    batches = load_batches()

    if args.dry_run:
        for filename, batch in batches:
            print(f"----- {filename}: {first_line(batch)}")
        print(f"Dry run OK: {len(batches)} SQL batches.")
        return 0

    server = os.environ["SYNAPSE_SQL_SERVER"]
    database = os.environ["SYNAPSE_SQL_DATABASE"]

    with connect(server, database) as connection:
        cursor = connection.cursor()
        for filename, batch in batches:
            print(f"Deploying SQL: {filename}: {first_line(batch)}")
            cursor.execute(batch)

    print(f"All Synapse SQL batches completed ({len(batches)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
