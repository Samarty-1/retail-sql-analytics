-- Monthly acquisition cohorts: of the customers whose first order fell in
-- month M, what share ordered again k months later?
--
-- The data starts on 2009-12-01, so the 2009-12 "cohort" is every customer
-- already trading with the shop, not new ones. It is left-censored and retains
-- far better than any true acquisition cohort; it is flagged, not mixed in.
-- Likewise any cell that lands in 2011-12 covers only nine days of trading
-- and is flagged as a partial period.
with activity as (
    select distinct
        o.customer_id,
        c.cohort_month,
        datediff('month', c.cohort_month, o.order_month) as months_since_first
    from fct_orders o
    join dim_customers c using (customer_id)
),
cohort_size as (
    select cohort_month, count(*) as customers
    from dim_customers
    group by cohort_month
)
select
    a.cohort_month,
    s.customers                                 as cohort_customers,
    a.months_since_first,
    count(*)                                    as active_customers,
    round(100.0 * count(*) / s.customers, 1)    as retention_pct,
    a.cohort_month = (select min(order_month) from fct_orders) as is_left_censored,
    a.cohort_month + to_months(a.months_since_first) = (select max(order_month) from fct_orders)
                                                as is_partial_period
from activity a
join cohort_size s using (cohort_month)
group by a.cohort_month, s.customers, a.months_since_first
order by a.cohort_month, a.months_since_first;
