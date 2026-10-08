"""Build the warehouse and run every analysis.

    python scripts/ingest.py     # once: download + land raw Parquet
    python run.py                # build data/retail.duckdb, write results/*.csv

The SQL does all the work; this file only executes it in order.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent
STAGING = sorted((ROOT / "sql" / "staging").glob("*.sql"))
ANALYSIS = sorted((ROOT / "sql" / "analysis").glob("*.sql"))
RAW = ROOT / "data" / "raw" / "online_retail_ii.parquet"


def build(con: duckdb.DuckDBPyConnection, raw_source: str | Path) -> None:
    """Load raw_lines from a Parquet/CSV file, then run the staging models."""
    con.execute(f"create or replace table raw_lines as select * from '{Path(raw_source).as_posix()}'")
    for path in STAGING:
        con.execute(path.read_text())


def analysis(con: duckdb.DuckDBPyConnection, name: str):
    """Run one analysis query by file stem (e.g. '03_cohort_retention')."""
    return con.sql((ROOT / "sql" / "analysis" / f"{name}.sql").read_text())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--db", default=str(ROOT / "data" / "retail.duckdb"))
    parser.add_argument("--raw", default=str(RAW))
    args = parser.parse_args()

    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    with duckdb.connect(args.db) as con:
        build(con, args.raw)
        for path in ANALYSIS:
            rel = analysis(con, path.stem)
            rel.write_csv(str(out / f"{path.stem}.csv"))
            print(f"\n== {path.stem} ({len(rel.fetchall())} rows)")
            print(rel.limit(12).df().to_string(index=False))


if __name__ == "__main__":
    main()
