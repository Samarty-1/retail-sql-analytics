-- Time to second order. For each quarterly acquisition cohort: the share of
-- new customers who ordered again within 90 days, and how long the median
-- repeat customer took. A cohort whose 90-day window runs past the end of the
-- data is flagged: its rate is right-censored, so biased low. The first
-- quarter is left-censored: it holds only 2009-12, i.e. pre-existing customers.
with ordered as (
    select
        customer_id,
        ordered_at,
        row_number() over (partition by customer_id order by ordered_at, order_id) as order_no
    from fct_orders
),
firsts as (
    select
        f.customer_id,
        date_trunc('quarter', f.ordered_at)::date       as cohort_quarter,
        f.ordered_at                                    as first_at,
        datediff('day', f.ordered_at, s.ordered_at)     as days_to_second
    from ordered f
    left join ordered s on s.customer_id = f.customer_id and s.order_no = 2
    where f.order_no = 1
),
data_end as (
    select max(ordered_at) as end_at from fct_orders
)
select
    cohort_quarter,
    count(*)                                                                    as new_customers,
    round(100.0 * count(*) filter (where days_to_second <= 90) / count(*), 1)   as second_order_90d_pct,
    median(days_to_second)                                                      as median_days_to_second,
    max(first_at) + interval 90 day > (select end_at from data_end)             as is_right_censored,
    cohort_quarter = min(cohort_quarter) over ()                                as is_left_censored
from firsts
group by cohort_quarter
order by cohort_quarter;
