"""Deploy the application KQL listed in deploy/kql-manifest.txt to one ADX database.

Usage (from the project root):
    python scripts/deploy_kql.py --dry-run   # render and print only, no Azure calls
    python scripts/deploy_kql.py             # deploy

Environment variables:
    ADX_CLUSTER_URI    e.g. https://adxhuskypdmdev0599.eastus2.kusto.windows.net
    ADX_DATABASE       e.g. pdm_dev
    ADLS_ACCOUNT_NAME  storage account used inside {{ADLS_ACCOUNT_NAME}} placeholders
"""
import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KQL_DIR = ROOT / "kql"
MANIFEST = ROOT / "deploy" / "kql-manifest.txt"

# The only placeholders a KQL file may use, and the shape each value must have
PLACEHOLDERS = {
    "ADLS_ACCOUNT_NAME": re.compile(r"^[a-z0-9]{3,24}$"),
}
PLACEHOLDER_PATTERN = re.compile(r"\{\{\s*([A-Za-z0-9_]+)\s*\}\}")

# How to ask ADX whether a create-only object already exists
EXISTS_QUERIES = {
    "external-table": '.show external tables | where TableName == "{name}" | count',
    "continuous-export": '.show continuous-exports | where Name == "{name}" | count',
}


def read_manifest(path=MANIFEST):
    """Return [{"file": ..., "create_only": None or (kind, name)}] in deployment order."""
    entries = []
    lines = path.read_text(encoding="utf-8").splitlines()

    for line_no, line in enumerate(lines, start=1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue

        parts = line.split()
        if len(parts) == 1:
            entries.append({"file": parts[0], "create_only": None})
        elif len(parts) == 3 and parts[1] == "create-only":
            kind, _, name = parts[2].partition(":")
            if kind not in EXISTS_QUERIES or not name:
                raise ValueError(
                    f"{path.name}:{line_no}: unknown create-only target {parts[2]!r}"
                )
            entries.append({"file": parts[0], "create_only": (kind, name)})
        else:
            raise ValueError(
                f"{path.name}:{line_no}: expected '<file>' or "
                "'<file> create-only <kind>:<name>'"
            )

    return entries


def render(text, env):
    """Normalise line endings and fill {{PLACEHOLDERS}} from approved configuration."""

    def substitute(match):
        key = match.group(1)
        if key not in PLACEHOLDERS:
            raise ValueError(f"Unknown placeholder {{{{{key}}}}}")
        value = env.get(key, "")
        if not PLACEHOLDERS[key].match(value):
            raise ValueError(
                f"Placeholder {{{{{key}}}}} needs a valid {key} environment variable"
            )
        return value

    text = text.replace("\r\n", "\n")
    return PLACEHOLDER_PATTERN.sub(substitute, text).strip()


def build_command(script_text):
    # ThrowOnErrors: one failed command fails the whole deployment
    return (
        ".execute database script with (ThrowOnErrors=true) <|\n"
        + script_text
    )


def load_scripts(env):
    """Render every file BEFORE deploying anything, so a bad file stops the release early."""
    scripts = []
    for entry in read_manifest():
        path = KQL_DIR / entry["file"]
        if not path.is_file():
            raise FileNotFoundError(f"Manifest lists a missing file: {path}")
        scripts.append((entry, render(path.read_text(encoding="utf-8"), env)))
    return scripts


def object_exists(client, database, kind, name):
    response = client.execute_mgmt(
        database, EXISTS_QUERIES[kind].format(name=name)
    )
    rows = list(response.primary_results[0])
    return bool(rows) and int(rows[0][0]) > 0


def deploy(scripts, cluster, database):
    # Imported here so --dry-run and the unit tests need no Azure packages
    from azure.identity import DefaultAzureCredential
    from azure.kusto.data import KustoClient, KustoConnectionStringBuilder

    connection = KustoConnectionStringBuilder.with_azure_token_credential(
        cluster, DefaultAzureCredential()
    )
    client = KustoClient(connection)

    for entry, script_text in scripts:
        filename = entry["file"]

        if entry["create_only"]:
            kind, name = entry["create_only"]
            if object_exists(client, database, kind, name):
                print(f"Skipped (already exists): {filename} [{kind} {name}]")
                continue

        print(f"Deploying KQL: {filename}")
        response = client.execute_mgmt(database, build_command(script_text))

        for row in response.primary_results[0]:
            print(f"    {row['CommandType']}: {row['Result']}")
            if row["Result"] != "Completed":
                raise RuntimeError(
                    f"{filename}: {row['CommandType']} {row['Result']} - {row['Reason']}"
                )

        print(f"Completed: {filename}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="render the scripts and print them without connecting to Azure",
    )
    args = parser.parse_args(argv)

    scripts = load_scripts(os.environ)

    if args.dry_run:
        for entry, script_text in scripts:
            mode = "create-only" if entry["create_only"] else "repeatable"
            print(f"----- {entry['file']} ({mode})")
            print(script_text)
        print(f"Dry run OK: {len(scripts)} KQL files rendered.")
        return 0

    deploy(
        scripts,
        cluster=os.environ["ADX_CLUSTER_URI"],
        database=os.environ["ADX_DATABASE"],
    )
    print("All KQL deployment scripts completed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
