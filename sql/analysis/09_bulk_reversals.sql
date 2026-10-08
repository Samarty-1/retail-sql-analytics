-- Bulk reversals: cancellation lines of >= 1,000 units, matched to the sale
-- they reverse (same customer, product, quantity and price, invoiced earlier),
-- and checked for a re-bill: the identical line invoiced to a *different*
-- customer within the 7 days before the cancellation.
--
-- These are data-entry corrections, not product returns. They inflate gross
-- sales in the month of the original order and wreck unit-based return rates.
with big_cancels as (
    select invoice_no, invoiced_at, customer_id, stock_code, description,
           -quantity as units, unit_price, -line_amount as value
    from stg_lines
    where line_type = 'cancellation' and not is_duplicate_copy and quantity <= -1000
),
reversed_sale as (
    -- the latest matching sale before the cancellation
    select
        c.invoice_no                    as cancel_invoice,
        c.stock_code,
        s.invoice_no                    as sale_invoice,
        s.invoiced_at                   as sale_at
    from big_cancels c
    join stg_lines s
      on  s.line_type = 'sale'
      and s.customer_id = c.customer_id
      and s.stock_code = c.stock_code
      and s.quantity = c.units
      and s.unit_price = c.unit_price
      and s.invoiced_at <= c.invoiced_at
    qualify row_number() over (partition by c.invoice_no, c.stock_code order by s.invoiced_at desc) = 1
),
rebill as (
    select
        c.invoice_no                    as cancel_invoice,
        c.stock_code,
        any_value(s.customer_id)        as rebilled_to
    from big_cancels c
    join stg_lines s
      on  s.line_type = 'sale'
      and s.customer_id <> c.customer_id
      and s.stock_code = c.stock_code
      and s.quantity = c.units
      and s.invoiced_at between c.invoiced_at - interval 7 day and c.invoiced_at
    group by c.invoice_no, c.stock_code
)
select
    c.invoice_no                                            as cancel_invoice,
    c.invoiced_at::date                                     as cancelled_on,
    c.customer_id,
    c.stock_code,
    c.description,
    c.units,
    round(c.value, 0)                                       as value,
    r.sale_invoice,
    round(datediff('minute', r.sale_at, c.invoiced_at) / 60.0, 1) as hours_after_sale,
    b.rebilled_to,
    case
        when r.sale_invoice is null                         then 'unmatched'
        when b.rebilled_to is not null                      then 'rebilled to another customer'
        when datediff('minute', r.sale_at, c.invoiced_at) <= 60 then 'reversed within the hour'
        else 'reversed later'
    end                                                     as pattern
from big_cancels c
left join reversed_sale r on r.cancel_invoice = c.invoice_no and r.stock_code = c.stock_code
left join rebill b on b.cancel_invoice = c.invoice_no and b.stock_code = c.stock_code
order by c.value desc;
