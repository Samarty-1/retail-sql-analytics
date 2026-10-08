-- Where every raw row went. The staging layer must account for all of them:
-- raw = sheet-overlap rows + duplicate copies + kept rows of each line type.
with raw as (
    select
        count(*) as raw_rows,
        count(*) filter (where source_sheet = 'Year 2009-2010'
                           and InvoiceDate >= timestamp '2010-12-01') as overlap_rows
    from raw_lines
),
staged as (
    select
        line_type,
        count(*) filter (where not is_duplicate_copy)                           as n_rows,
        count(*) filter (where is_duplicate_copy)                               as duplicate_copies,
        sum(line_amount) filter (where not is_duplicate_copy)                   as amount,
        count(*) filter (where not is_duplicate_copy and customer_id is null)   as no_customer
    from stg_lines
    group by line_type
)
select 'raw rows' as step, raw_rows as n_rows, null::decimal(14, 2) as amount, null::bigint as no_customer
from raw
union all
select 'dropped: sheet overlap', overlap_rows, null, null from raw
union all
select 'dropped: duplicate copy', sum(duplicate_copies), null, null from staged
union all
select 'kept: ' || line_type, n_rows, amount, no_customer from staged
order by n_rows desc;
