-- fct_orders: one row per sales invoice placed by an identified customer.
-- Cancellations are attributed back to the customer, not to the original
-- invoice (the source has no link between a 'C' invoice and what it reverses).
create or replace table fct_orders as
select
    invoice_no                      as order_id,
    customer_id,
    min(invoiced_at)                as ordered_at,
    min(invoice_month)              as order_month,
    any_value(country)              as country,
    count(*)                        as n_lines,
    sum(quantity)                   as n_units,
    sum(line_amount)                as order_value
from stg_lines
where line_type = 'sale'
  and not is_duplicate_copy
  and customer_id is not null
group by invoice_no, customer_id;
