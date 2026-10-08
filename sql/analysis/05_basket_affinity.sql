-- Market-basket affinity: which products are bought together far more often
-- than chance would predict?
--   support(A,B)      = share of baskets containing both
--   confidence(A->B)  = P(B | A)
--   lift              = P(A,B) / (P(A) * P(B))      (1 = independent)
-- A pair needs >= 300 shared baskets so lift is not driven by a few orders.
with baskets as (
    select distinct invoice_no, stock_code
    from stg_lines
    where line_type = 'sale' and not is_duplicate_copy
),
n as (
    select count(distinct invoice_no) as baskets from baskets
),
item as (
    select stock_code, count(*) as baskets_with
    from baskets
    group by stock_code
),
pair as (
    select a.stock_code as item_a, b.stock_code as item_b, count(*) as together
    from baskets a
    join baskets b on a.invoice_no = b.invoice_no and a.stock_code < b.stock_code
    group by all
    having count(*) >= 300
),
names as (
    -- descriptions drift over time; use the most common one per stock code
    select stock_code, mode(description) as description
    from stg_lines
    where line_type = 'sale'
    group by stock_code
)
select
    p.item_a,
    na.description                                          as description_a,
    p.item_b,
    nb.description                                          as description_b,
    p.together                                              as baskets_together,
    round(100.0 * p.together / n.baskets, 2)                as support_pct,
    round(100.0 * p.together / ia.baskets_with, 1)          as confidence_a_to_b_pct,
    round(100.0 * p.together / ib.baskets_with, 1)          as confidence_b_to_a_pct,
    round(p.together * n.baskets / (ia.baskets_with * ib.baskets_with)::double, 1) as lift
from pair p
cross join n
join item ia on ia.stock_code = p.item_a
join item ib on ib.stock_code = p.item_b
left join names na on na.stock_code = p.item_a
left join names nb on nb.stock_code = p.item_b
order by lift desc, p.together desc
limit 25;
