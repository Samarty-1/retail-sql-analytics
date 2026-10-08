-- RFM segmentation. Each customer gets quintile scores (5 = best) for
-- Recency (days since last order), Frequency (orders) and Monetary (net sales),
-- measured as of the day after the last order in the data.
with snapshot as (
    select max(ordered_at)::date + 1 as as_of from fct_orders
),
base as (
    select
        customer_id,
        datediff('day', last_order_at::date, (select as_of from snapshot)) as recency_days,
        n_orders,
        net_sales
    from dim_customers
),
scored as (
    select
        *,
        ntile(5) over (order by recency_days desc, customer_id)     as r,
        -- over a third of customers have exactly one order; break frequency ties
        -- by spend so they are ordered, not split across quintiles at random
        ntile(5) over (order by n_orders, net_sales, customer_id)   as f,
        ntile(5) over (order by net_sales, customer_id)             as m
    from base
),
segmented as (
    select
        *,
        case
            when r >= 4 and f >= 4 and m >= 4 then 'Champions'
            when r >= 3 and f >= 3             then 'Loyal'
            when r >= 4 and f <= 2             then 'New / promising'
            when r <= 2 and f >= 4             then 'Cannot lose them'
            when r <= 2 and f >= 2             then 'At risk'
            when r = 3                         then 'Needs attention'
            else                                    'Lost'
        end as segment
    from scored
)
select
    segment,
    count(*)                                                        as customers,
    round(100.0 * count(*) / sum(count(*)) over (), 1)              as pct_customers,
    round(sum(net_sales), 0)                                        as net_sales,
    round(100.0 * sum(net_sales) / sum(sum(net_sales)) over (), 1)  as pct_net_sales,
    round(median(recency_days), 0)                                  as median_recency_days,
    round(median(n_orders), 1)                                      as median_orders,
    round(median(net_sales), 0)                                     as median_net_sales
from segmented
group by segment
order by net_sales desc;
