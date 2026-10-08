-- How concentrated is revenue? Customers ranked by net sales, then the share
-- of total net sales captured by the top 1%, 5%, 10%, 20% and 50%.
with ranked as (
    select
        net_sales,
        row_number() over (order by net_sales desc, customer_id)    as rnk,
        count(*) over ()                                            as n,
        sum(net_sales) over ()                                      as total
    from dim_customers
    where net_sales > 0
),
cuts as (
    select unnest([1, 5, 10, 20, 50]) as top_pct
)
select
    c.top_pct,
    count(*)                                                    as customers,
    round(100.0 * sum(r.net_sales) / any_value(r.total), 1)     as pct_of_net_sales
from cuts c
join ranked r on r.rnk <= ceil(r.n * c.top_pct / 100.0)
group by c.top_pct
order by c.top_pct;
