# retail-sql-analytics

Customer and product analytics in plain SQL (DuckDB) on **1,067,371 real
transactions** from a UK online gift wholesaler (UCI *Online Retail II*,
Dec 2009 – Dec 2011, 5,852 customers in 43 countries).

The analysis is the easy part. Most of the work went into the data, which has
four problems that each change the answer if they're ignored.

## What's wrong with the raw data, and what it would have cost

| Problem | Size | If ignored |
|---|---|---|
| The workbook's two sheets **overlap on 1–9 Dec 2010**: every row is repeated verbatim in both | 22,523 rows, £377k | Nine days of revenue counted twice |
| **Exact duplicate lines** within a sheet (same invoice, item, qty, price, minute) | 11,812 rows, £54k | Double-scans counted as sales |
| **Bulk orders reversed minutes later**: 80,995 paper birdies (£168k) and 74,215 storage jars (£77k) | 4 lines, £250k | Gross sales and AOV spike in Jan and Dec 2011 |
| **Billing corrections that look like returns**: goods invoiced to customer A, re-invoiced to B, then cancelled on A | 25 lines | Ordinary products show a 49% unit "return rate" |

Non-product lines are separated out too: postage, Amazon fees, manual
adjustments, bad-debt write-offs, stock write-offs and test SKUs. Every raw row
is accounted for (`01_reconciliation`, asserted in the tests):

```
1,067,371 raw = 22,523 overlap + 11,812 duplicate copies
              + 1,003,340 sales + 17,915 cancellations + 5,980 stock adjustments
              + 5,795 non-product + 6 bad-debt adjustments
```

## Findings

**Retention: the first cohort is a trap.** The data starts on 1 Dec 2009, so
the "Dec 2009 cohort" is every customer *already* trading with the shop. It
retains at roughly twice the rate of real acquisition cohorts. Pooled into a
benchmark, it would overstate retention badly:

| | month 1 | month 3 | month 6 | month 12 |
|---|---|---|---|---|
| Dec 2009 "cohort" (left-censored) | 35.0% | 42.5% | 37.6% | 37.6% |
| True new-customer cohorts, pooled | 21.0% | 21.1% | 18.4% | 18.4% |

Cells that land in Dec 2011 (nine days of data) are flagged as partial and kept
out of the pooled figures. The Dec 2010 cohort's naive month-12 retention reads
2.6% for that reason.

**Revenue is very concentrated.** The top 1% of customers (59) bring in 31% of
net sales, the top 10% bring in 63%, and the top 20% bring in 77%. RFM
segmentation shows the same thing from the other side: *Champions* are 23% of
customers and 70% of net sales.

| RFM segment | customers | share of net sales | median recency (days) |
|---|---|---|---|
| Champions | 22.7% | 69.8% | 17 |
| Loyal | 23.3% | 15.7% | 67 |
| Cannot lose them | 6.0% | 6.3% | 334 |
| At risk | 19.5% | 5.3% | 402 |
| New / promising | 7.5% | 1.0% | 26 |
| Needs attention | 6.4% | 1.0% | 97 |
| Lost | 14.5% | 0.9% | 458 |

**Growth is flat once the noise is removed.** Net revenue for Dec 2010 – Nov
2011 was £9.33m against £9.16m a year earlier, up 1.9%. Q4 seasonality is
strong: November is about 2.5× February.

**Baskets are driven by product families.** The highest-lift pairs are variants
of the same range, such as skull paper cups with plates (lift 77, 81%
confidence) or the four rooms of *Poppy's Playhouse*. These are bundling
candidates, not cross-category discoveries.

**Cancellations, measured honestly.** Counted by customers instead of units,
the most-cancelled products are cake stands and teapots: fragile, bulky items
where 15–22% of buyers cancel. The unit-based ranking was entirely billing
artefacts.

Full outputs are in [`results/`](results).

## The SQL

| File | Technique |
|---|---|
| `sql/staging/01_stg_lines.sql` | multiset de-duplication, `row_number()` copy detection, rule-based line typing |
| `sql/staging/02_fct_orders.sql`, `03_dim_customers.sql` | fact/dimension build, `qualify` for modal country |
| `01_reconciliation` | row-level audit trail from raw to modelled |
| `02_monthly_revenue` | `filter` aggregates, `lag(12)` YoY guarded against gaps and partial months |
| `03_cohort_retention` | cohort matrix with left- and right-censoring flags |
| `04_rfm_segments` | `ntile` scoring with deterministic tie-breaks |
| `05_basket_affinity` | self-join pair counting, support / confidence / lift |
| `06_customer_concentration` | Pareto cuts via ranked window totals |
| `07_product_returns` | buyer-based cancellation rates |
| `08_repeat_purchase` | time-to-second-order per cohort, censoring-aware |
| `09_bulk_reversals` | time-windowed self-joins to classify reversals and re-bills |

## Run it

```bash
pip install -r requirements.txt
python scripts/ingest.py     # download (~45 MB) and land as Parquet
python run.py                # build data/retail.duckdb, write results/*.csv
pytest                       # 17 tests
```

The tests come in two layers:
- `tests/test_sql_logic.py` runs every model against a 14-row hand-built
  fixture where each row exercises one rule and the right answers are known.
- `tests/test_full_data.py` checks invariants on the real data: the sheet
  overlap is an exact multiset duplicate, every raw row reconciles, the monthly
  series has no gaps (which `lag(12)` depends on), net revenue ties out to line
  level, and cohorts cover every customer.

CI runs both layers.

## Assumptions

- Lines that are identical on every field within one invoice are treated as
  double-scans. That removes 1.1% of rows. If some were genuine, sales are
  understated by at most £54k.
- Cancellations have no link to the invoice they reverse in the source, so they
  are attributed to customer and product, not to the original order.
- Customer-level analyses exclude anonymous sales: 13% of gross sales have no
  customer ID.

Data: Chen, D. (2012). *Online Retail II*. UCI Machine Learning Repository.
https://doi.org/10.24432/C5CG6D (CC BY 4.0).
