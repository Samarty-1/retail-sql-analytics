import sys
from datetime import datetime
from pathlib import Path

import duckdb
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import run  # noqa: E402

S1, S2 = "Year 2009-2010", "Year 2010-2011"
COLS = ["Invoice", "StockCode", "Description", "Quantity", "InvoiceDate", "Price",
        "CustomerID", "Country", "source_sheet"]

# Hand-built rows, each exercising one rule. Expected outcomes are in the tests.
FIXTURE = [
    # customer 1: cohort 2009-12 (left-censored), returns in 2010-02
    ("100001", "A1", "Alpha", 2, datetime(2009, 12, 5, 10), 5.0, 1, "UK", S1),
    ("100001", "B1", "Beta", 1, datetime(2009, 12, 5, 10), 3.0, 1, "UK", S1),
    # customer 2: cohort 2010-01; the second line is an exact duplicate copy
    ("100002", "A1", "Alpha", 1, datetime(2010, 1, 10, 9), 5.0, 2, "France", S1),
    ("100002", "A1", "Alpha", 1, datetime(2010, 1, 10, 9), 5.0, 2, "France", S1),
    ("100003", "B1", "Beta", 1, datetime(2010, 2, 3, 9), 3.0, 1, "UK", S1),
    # customer 2 cancels their alpha
    ("C100004", "A1", "Alpha", -1, datetime(2010, 2, 4, 9), 5.0, 2, "France", S1),
    # postage, a bad-debt adjustment and a stock write-off
    ("100005", "POST", "POSTAGE", 1, datetime(2010, 2, 4, 9), 18.0, 2, "France", S1),
    ("A100006", "B", "Adjust bad debt", 1, datetime(2010, 2, 5, 9), -50.0, None, "UK", S1),
    ("100007", "A1", "damaged", -10, datetime(2010, 2, 6, 9), 0.0, None, "UK", S1),
    # customer 3 (cohort 2010-12): the same line appears in both sheets
    ("100008", "A1", "Alpha", 3, datetime(2010, 12, 2, 9), 5.0, 3, "UK", S1),
    ("100008", "A1", "Alpha", 3, datetime(2010, 12, 2, 9), 5.0, 3, "UK", S2),
    # anonymous sale
    ("100009", "B1", "Beta", 2, datetime(2011, 1, 15, 9), 3.0, None, "UK", S2),
    # customer 3 returns a month later
    ("100010", "A1", "Alpha", 1, datetime(2011, 1, 20, 9), 5.0, 3, "UK", S2),
    ("100010", "B1", "Beta", 1, datetime(2011, 1, 20, 9), 3.0, 3, "UK", S2),
]


@pytest.fixture(scope="session")
def fx(tmp_path_factory):
    df = pd.DataFrame(FIXTURE, columns=COLS).astype({"CustomerID": "Int64"})
    path = tmp_path_factory.mktemp("fx") / "raw.parquet"
    df.to_parquet(path, index=False)
    con = duckdb.connect()
    run.build(con, path)
    yield con
    con.close()


@pytest.fixture(scope="session")
def full():
    if not run.RAW.exists():
        pytest.skip("full dataset not landed; run scripts/ingest.py")
    con = duckdb.connect()
    run.build(con, run.RAW)
    yield con
    con.close()
