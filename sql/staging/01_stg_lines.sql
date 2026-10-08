-- stg_lines: one row per genuine invoice line, typed and classified.
--
-- Input: raw_lines (Invoice, StockCode, Description, Quantity, InvoiceDate, Price,
--                   CustomerID, Country, source_sheet), landed untouched by ingest.py.
create or replace table stg_lines as
with
-- The workbook's two sheets overlap on 2010-12-01 .. 2010-12-09: every row the
-- 2009-2010 sheet holds for those days is repeated verbatim in the 2010-2011 sheet
-- (22,523 rows, multiset-equal). Keep the later sheet's copy.
deoverlapped as (
    select *
    from raw_lines
    where not (source_sheet = 'Year 2009-2010' and InvoiceDate >= timestamp '2010-12-01')
),

-- Within a sheet, some lines appear more than once with every field identical,
-- down to the minute. Treated as double-scans: keep the first copy.
numbered as (
    select
        *,
        row_number() over (
            partition by Invoice, StockCode, Description, Quantity, InvoiceDate,
                         Price, CustomerID, Country
            order by source_sheet
        ) as copy_no
    from deoverlapped
),

typed as (
    select
        trim(Invoice)                                   as invoice_no,
        upper(trim(StockCode))                          as stock_code,
        nullif(trim(Description), '')                   as description,
        Quantity::integer                               as quantity,
        Price::decimal(12, 2)                           as unit_price,
        (Quantity * Price)::decimal(14, 2)              as line_amount,
        InvoiceDate                                     as invoiced_at,
        InvoiceDate::date                               as invoice_date,
        date_trunc('month', InvoiceDate)::date          as invoice_month,
        CustomerID::varchar                             as customer_id,
        trim(Country)                                   as country,
        copy_no > 1                                     as is_duplicate_copy
    from numbered
)

select
    *,
    case
        -- 'A' invoices are accounting entries ("Adjust bad debt"), not sales
        when invoice_no like 'A%' then 'bad_debt_adjustment'
        -- postage, fees, manual corrections, discounts, vouchers, test SKUs
        when stock_code in ('POST', 'DOT', 'M', 'C2', 'C3', 'D', 'S', 'B',
                            'BANK CHARGES', 'AMAZONFEE', 'CRUK', 'GIFT')
          or stock_code like 'ADJUST%'
          or stock_code like 'TEST%'
          or stock_code like 'GIFT_%'
            then 'non_product'
        when invoice_no like 'C%' then 'cancellation'
        -- stock write-offs ("damaged", "lost", "?"): price 0, usually no customer
        when unit_price = 0 or quantity < 0 then 'stock_adjustment'
        else 'sale'
    end as line_type
from typed;
