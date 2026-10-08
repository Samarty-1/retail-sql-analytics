-- Monthly trading: gross sales, cancellations, net revenue and growth.
-- Covers all customers, including the anonymous ones.
with monthly as (
    select
        invoice_month                                                   as month,
        sum(line_amount) filter (where line_type = 'sale')              as gross_sales,
        -sum(line_amount) filter (where line_type = 'cancellation')     as cancellations,
        count(distinct invoice_no) filter (where line_type = 'sale')    as orders,
        count(distinct customer_id) filter (where line_type = 'sale')   as active_customers,
        max(invoice_date)                                               as last_trading_day
    from stg_lines
    where not is_duplicate_copy
    group by invoice_month
),
flagged as (
    select
        *,
        gross_sales - coalesce(cancellations, 0)                        as net_revenue,
        -- the data stops on 2011-12-09, so the final month is partial
        month = max(month) over () and last_trading_day < last_day(month) as is_partial_month
    from monthly
)
select
    month,
    gross_sales,
    coalesce(cancellations, 0)                                  as cancellations,
    net_revenue,
    orders,
    active_customers,
    round(gross_sales / orders, 2)                              as avg_order_value,
    round(100.0 * coalesce(cancellations, 0) / gross_sales, 1)  as cancel_rate_pct,
    -- Growth on net revenue: gross is distorted by bulk orders that were
    -- cancelled minutes later (09_bulk_reversals). lag(12) is "same month last
    -- year" only because the series has no gaps (asserted in the tests), and a
    -- partial month is never compared with a full one.
    case when not is_partial_month then
        round(100.0 * (net_revenue / lag(net_revenue, 12) over (order by month) - 1), 1)
    end                                                         as yoy_growth_pct,
    is_partial_month
from flagged
order by month;
