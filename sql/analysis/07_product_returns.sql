-- Which products get cancelled most?
--
-- Measured by customers, not units. A units-based rate is dominated by a few
-- bulk lines that are billing corrections rather than returns (see
-- 09_bulk_reversals): e.g. 4,320 garden mugs invoiced to one customer, invoiced
-- again to another, then cancelled on the first account, which reads as a 49%
-- "return rate" for a product almost nobody returned.
--   customer_cancel_rate = customers who cancelled the product / customers who bought it
-- Products need >= 200 buyers.
with bought as (
    select stock_code, count(distinct customer_id) as buyers, sum(quantity) as units_sold
    from stg_lines
    where line_type = 'sale' and not is_duplicate_copy and customer_id is not null
    group by stock_code
),
cancelled as (
    select
        stock_code,
        count(distinct customer_id) as cancellers,
        -sum(quantity)              as units_cancelled,
        -min(quantity)              as largest_cancel_line
    from stg_lines
    where line_type = 'cancellation' and not is_duplicate_copy and customer_id is not null
    group by stock_code
),
names as (
    select stock_code, mode(description) as description
    from stg_lines
    where line_type = 'sale'
    group by stock_code
)
select
    b.stock_code,
    n.description,
    b.buyers,
    coalesce(c.cancellers, 0)                                           as cancellers,
    round(100.0 * coalesce(c.cancellers, 0) / b.buyers, 1)              as customer_cancel_rate_pct,
    round(100.0 * coalesce(c.units_cancelled, 0) / b.units_sold, 1)     as unit_cancel_rate_pct,
    coalesce(c.largest_cancel_line, 0)                                  as largest_cancel_line
from bought b
left join cancelled c using (stock_code)
left join names n using (stock_code)
where b.buyers >= 200
order by customer_cancel_rate_pct desc, b.stock_code
limit 20;
