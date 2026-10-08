"""Invariants on the real dataset. Skipped unless scripts/ingest.py has run."""
from run import analysis


def one(con, sql):
    return con.sql(sql).fetchone()[0]


def test_sheet_overlap_is_an_exact_duplicate(full):
    # the claim the staging layer relies on: every 2009-2010 row dated
    # 2010-12-01+ is repeated verbatim (as a multiset) in the 2010-2011 sheet
    a = """select * exclude (source_sheet) from raw_lines
           where source_sheet = 'Year 2009-2010' and InvoiceDate >= '2010-12-01'"""
    b = """select * exclude (source_sheet) from raw_lines
           where source_sheet = 'Year 2010-2011' and InvoiceDate < '2010-12-10'"""
    assert one(full, f"select count(*) from ({a})") == 22_523
    assert one(full, f"select count(*) from ({a} except all {b})") == 0
    assert one(full, f"select count(*) from ({b} except all {a})") == 0


def test_reconciliation_accounts_for_every_raw_row(full):
    rec = {step: n for step, n, *_ in analysis(full, "01_reconciliation").fetchall()}
    raw = rec.pop("raw rows")
    assert raw == 1_067_371 and sum(rec.values()) == raw


def test_monthly_series_has_no_gaps(full):
    # 02_monthly_revenue uses lag(12) as "same month last year"
    months = [r[0] for r in analysis(full, "02_monthly_revenue").fetchall()]
    assert len(months) == 25
    assert all((b.year - a.year) * 12 + b.month - a.month == 1 for a, b in zip(months, months[1:]))


def test_net_revenue_ties_out_to_line_level(full):
    monthly = one(full, "select sum(net_revenue) from (" + _sql("02_monthly_revenue") + ")")
    lines = one(full, """select sum(line_amount) from stg_lines
                         where line_type in ('sale', 'cancellation') and not is_duplicate_copy""")
    assert monthly == lines


def test_customer_cohorts_cover_every_customer(full):
    cohorts = one(full, "select sum(cohort_customers) from (" + _sql("03_cohort_retention")
                  + ") where months_since_first = 0")
    assert cohorts == one(full, "select count(*) from dim_customers")


def test_left_censored_cohort_retains_far_better(full):
    # why the 2009-12 cohort must be excluded from retention benchmarks
    sql = "from (" + _sql("03_cohort_retention") + ") where months_since_first = 12"
    censored = one(full, f"select avg(retention_pct) {sql} and is_left_censored")
    true_cohorts = one(full, f"select avg(retention_pct) {sql} and not is_left_censored "
                             "and not is_partial_period")
    assert censored > 1.8 * true_cohorts


def test_basket_metrics_are_consistent(full):
    for _, _, _, _, together, _, conf_ab, conf_ba, lift in analysis(full, "05_basket_affinity").fetchall():
        assert together >= 300 and lift > 1 and 0 < conf_ab <= 100 and 0 < conf_ba <= 100


def test_bulk_reversals_find_the_two_mistaken_orders(full):
    got = {inv: pattern for inv, *_, pattern in analysis(full, "09_bulk_reversals").fetchall()}
    assert got["C581484"] == "reversed within the hour"     # 80,995 paper birdies
    assert got["C541433"] == "reversed within the hour"     # 74,215 storage jars
    assert got["C524235"] == "rebilled to another customer"


def _sql(name):
    from run import ROOT
    return (ROOT / "sql" / "analysis" / f"{name}.sql").read_text().rstrip().rstrip(";")
