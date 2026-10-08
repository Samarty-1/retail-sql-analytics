-- dim_customers: one row per identified customer, with lifetime behaviour.
create or replace table dim_customers as
with orders as (
    select
        customer_id,
        min(ordered_at)                 as first_order_at,
        max(ordered_at)                 as last_order_at,
        min(order_month)                as cohort_month,
        count(*)                        as n_orders,
        sum(order_value)                as gross_sales
    from fct_orders
    group by customer_id
),
cancellations as (
    select customer_id, -sum(line_amount) as cancelled_value
    from stg_lines
    where line_type = 'cancellation' and not is_duplicate_copy and customer_id is not null
    group by customer_id
),
home_country as (
    -- the country a customer orders from most; ties broken alphabetically
    select customer_id, country
    from fct_orders
    group by customer_id, country
    qualify row_number() over (partition by customer_id order by count(*) desc, country) = 1
)
select
    o.*,
    coalesce(c.cancelled_value, 0)                  as cancelled_value,
    o.gross_sales - coalesce(c.cancelled_value, 0)  as net_sales,
    h.country
from orders o
left join cancellations c using (customer_id)
left join home_country h using (customer_id);
