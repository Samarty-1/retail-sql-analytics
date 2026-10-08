"""SQL unit tests: every model and analysis run against a hand-built fixture
whose correct answers are known."""
from datetime import date

from run import analysis


def rows(con, sql):
    return con.sql(sql).fetchall()


def test_line_classification(fx):
    got = dict(rows(fx, """
        select line_type, count(*) from stg_lines where not is_duplicate_copy group by 1"""))
    assert got == {"sale": 8, "cancellation": 1, "non_product": 1,
                   "bad_debt_adjustment": 1, "stock_adjustment": 1}


def test_sheet_overlap_dropped_and_duplicate_copy_flagged(fx):
    # 14 raw rows: 1 overlap row dropped, 1 duplicate copy flagged
    assert rows(fx, "select count(*) from stg_lines") == [(13,)]
    assert rows(fx, "select count(*) from stg_lines where is_duplicate_copy") == [(1,)]
    assert rows(fx, "select count(*) from stg_lines where invoice_no = '100008'") == [(1,)]


def test_reconciliation_accounts_for_every_raw_row(fx):
    rec = dict((step, n) for step, n, *_ in analysis(fx, "01_reconciliation").fetchall())
    raw = rec.pop("raw rows")
    assert raw == 14 and sum(rec.values()) == raw


def test_orders_exclude_anonymous_and_non_sales(fx):
    got = rows(fx, "select order_id, customer_id, order_value from fct_orders order by 1")
    assert [(o, c, float(v)) for o, c, v in got] == [
        ("100001", "1", 13.0), ("100002", "2", 5.0), ("100003", "1", 3.0),
        ("100008", "3", 15.0), ("100010", "3", 8.0)]


def test_customer_dimension(fx):
    got = {c: (cohort, n, float(net)) for c, cohort, n, net in rows(fx, """
        select customer_id, cohort_month, n_orders, net_sales from dim_customers""")}
    assert got == {"1": (date(2009, 12, 1), 2, 16.0),
                   "2": (date(2010, 1, 1), 1, 0.0),       # bought 5, cancelled 5
                   "3": (date(2010, 12, 1), 2, 23.0)}


def test_monthly_revenue_nets_cancellations(fx):
    got = {m: (float(g), float(c), float(n)) for m, g, c, n in rows(
        fx, "select month, gross_sales, cancellations, net_revenue from ("
            + open_sql("02_monthly_revenue") + ")")}
    assert got[date(2010, 1, 1)] == (5.0, 0.0, 5.0)         # duplicate copy not counted
    assert got[date(2010, 2, 1)] == (3.0, 5.0, -2.0)
    assert got[date(2011, 1, 1)] == (14.0, 0.0, 14.0)       # anonymous sale included


def test_cohort_retention_and_censoring_flags(fx):
    got = rows(fx, "select cohort_month, months_since_first, active_customers, is_left_censored, "
                   "is_partial_period from (" + open_sql("03_cohort_retention") + ") order by 1, 2")
    assert got == [
        (date(2009, 12, 1), 0, 1, True, False),
        (date(2009, 12, 1), 2, 1, True, False),
        (date(2010, 1, 1), 0, 1, False, False),
        (date(2010, 12, 1), 0, 1, False, False),
        (date(2010, 12, 1), 1, 1, False, True),   # 2011-01 is the fixture's last month
    ]


def test_concentration(fx):
    got = dict((p, float(s)) for p, _, s in analysis(fx, "06_customer_concentration").fetchall())
    # customers with positive net sales: 3 (23) and 1 (16); the top half is customer 3
    assert got[50] == round(100 * 23 / 39, 1)


def test_time_to_second_order(fx):
    got = rows(fx, "select cohort_quarter, new_customers, median_days_to_second from ("
                   + open_sql("08_repeat_purchase") + ") order by 1")
    assert got == [(date(2009, 10, 1), 1, 60.0),      # 2009-12-05 -> 2010-02-03
                   (date(2010, 1, 1), 1, None),       # never reordered
                   (date(2010, 10, 1), 1, 49.0)]      # 2010-12-02 -> 2011-01-20


def open_sql(name):
    from run import ROOT
    return (ROOT / "sql" / "analysis" / f"{name}.sql").read_text().rstrip().rstrip(";")
