"""Download UCI Online Retail II and land it as one raw Parquet file.

The source is a single .xlsx with two sheets ("Year 2009-2010", "Year 2010-2011").
Rows are landed untouched apart from types, plus a `source_sheet` column so the
staging layer can reason about where each row came from (the sheets overlap).
"""
from __future__ import annotations

import io
import sys
import urllib.request
import zipfile
from pathlib import Path

import pandas as pd

URL = "https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"
RAW = Path(__file__).resolve().parents[1] / "data" / "raw"
XLSX = RAW / "online_retail_II.xlsx"
OUT = RAW / "online_retail_ii.parquet"

DTYPES = {
    "Invoice": "string",
    "StockCode": "string",
    "Description": "string",
    "Country": "string",
    "Customer ID": "Int64",
}


def download() -> None:
    if XLSX.exists():
        return
    RAW.mkdir(parents=True, exist_ok=True)
    print(f"downloading {URL}")
    with urllib.request.urlopen(URL) as resp:
        payload = resp.read()
    with zipfile.ZipFile(io.BytesIO(payload)) as zf:
        zf.extract("online_retail_II.xlsx", RAW)


def land() -> None:
    sheets = pd.read_excel(XLSX, sheet_name=None, dtype=DTYPES)
    frames = [df.assign(source_sheet=name) for name, df in sheets.items()]
    raw = pd.concat(frames, ignore_index=True)
    raw = raw.rename(columns={"Customer ID": "CustomerID"})
    raw.to_parquet(OUT, index=False)
    print(f"landed {len(raw):,} rows from {len(frames)} sheets -> {OUT}")


if __name__ == "__main__":
    download()
    land()
    sys.exit(0)
