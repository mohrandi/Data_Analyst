--Tabel Order

with cleaned_keys as(
  select
  trim(order_id) as order_id,
  * except(order_id)
  from sql009.orders
),
deduped AS (
  -- Step 1: Hapus duplikat order_id, simpan baris paling lengkap
  -- (prioritas: unit_price & ship_date yang tidak NULL)
  select
  *
  from (select 
          *,
          row_number() over(partition by order_id order by (unit_price is null), (ship_date is null)) as rn
        from cleaned_keys)
  where rn = 1
),
 standarlisasi as(
  --standarlisasi teks, casting angka, parsing date
  SELECT 
  order_id, 
  customer_id, 
  COALESCE(
        SAFE.PARSE_DATE('%m/%d/%Y', order_date),
        SAFE.PARSE_DATE('%d-%b-%Y', order_date),
        SAFE.PARSE_DATE('%B %d, %Y', order_date),
        SAFE.PARSE_DATE('%Y-%m-%d', order_date)
    ) AS order_date,
  coalesce(
    safe.parse_date('%d/%m/%Y', ship_date),
    safe.parse_date('%Y-%m-%d', ship_date),
    safe.parse_date('%m/%d/%Y', ship_date),
    safe.parse_date('%d-%b-%Y', ship_date)
  ) as ship_date,
  trim(product_name) as product_name, 
  initcap(trim(product_category)) as product_category, 
  quantity, 
  safe_cast(replace(trim(unit_price), '$', '') as decimal) as unit_price, 
  discount_pct,
  case 
    when lower(trim(order_status)) = 'complet' then 'Completed'
    when lower(trim(order_status)) = 'compl.' then 'Completed'
    when lower(trim(order_status)) = 'shiped' then 'Shipped'
    when lower(trim(order_status)) = 'pendng' then 'Pending'
    when lower(trim(order_status)) = 'canceled' then 'Cancelled' else initcap(trim(order_status)) end as order_status,
  case
    when lower(replace(trim(payment_method), '_', ' ')) = 'credit card' then 'Credit Card'
    else initcap(payment_method) end as payment_method
  FROM deduped
),
price_ref as(
  -- Step 3: Hitung median harga per produk (dari data yang lengkap)
  -- untuk imputasi unit_price yang NULL
  select
  product_name,
  approx_quantiles(unit_price, 2)[offset(1)] as median_price
  from standarlisasi
  where unit_price is not null
  group by 1
),
final as(
  select 
  s.order_id, 
  s.customer_id, 
  s.order_date, 
  s.ship_date, 
  s.product_name, 
  s.product_category, 
  s.quantity, 
  coalesce (s.unit_price, median_price) as unit_price,
  s.discount_pct, 
  s.order_status, 
  s.payment_method,
  -- flag, bukan hapus data mentahnya
  case when s.unit_price is null then true else false end as was_price_imputed,
  case when s.quantity <= 0 then true else false end as is_quantity_invalid,
  case when s.quantity > 100 then true else false end as is_quantity_outlier,
  case when s.discount_pct > 1 then true else false end as is_discount_invalid,
  case when s.ship_date is not null and ship_date < order_date then true else false end as is_ship_before_order
  from standarlisasi s
  left join price_ref p using(product_name)
)
select
*
from final



