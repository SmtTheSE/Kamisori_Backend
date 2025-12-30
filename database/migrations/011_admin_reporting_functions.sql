-- Kamisori Backend - Admin and Reporting Functions
-- This migration provides admin functions for order management, reporting,
-- and business metrics to support the admin panel

-- Admin function to get all orders with customer details (for admin dashboard)
create or replace function get_all_orders_admin(
  page_offset int default 0,
  page_limit int default 50
)
returns table (
  id uuid,
  user_id uuid,
  customer_email text,
  customer_full_name text,
  total_amount numeric,
  payment_method text,
  status text,
  created_at timestamptz,
  delivery_address jsonb,
  order_items jsonb
)
language sql
security definer
as $$
  select 
    o.id,
    o.user_id,
    au.email as customer_email,
    au.raw_user_meta_data->>'full_name' as customer_full_name,
    o.total_amount,
    o.payment_method,
    o.status,
    o.created_at,
    coalesce(
      (select jsonb_build_object(
        'full_name', da.full_name,
        'phone', da.phone,
        'address', da.address
      ) 
      from public.delivery_addresses da 
      where da.order_id = o.id limit 1), 
      '{}'::jsonb
    ) as delivery_address,
    coalesce(
      (select jsonb_agg(
        jsonb_build_object(
          'id', oi.id,
          'product_id', oi.product_id,
          'quantity', oi.quantity,
          'price', oi.price,
          'product_name', p.name,
          'size', oi.size,
          'color', oi.color
        )
      ) 
      from public.order_items oi
      join public.products p on oi.product_id = p.id
      where oi.order_id = o.id), 
      '[]'::jsonb
    ) as order_items
  from public.orders o
  left join auth.users au on o.user_id = au.id
  order by o.created_at desc
  limit page_limit
  offset page_offset;
$$;

-- Admin function to get order details with all related information
create or replace function get_order_details_admin(order_uuid uuid)
returns table (
  order_data jsonb,
  customer_data jsonb,
  items_data jsonb,
  address_data jsonb,
  payment_slip_data jsonb
)
language sql
security definer
as $$
  select 
    jsonb_build_object(
      'id', o.id,
      'user_id', o.user_id,
      'total_amount', o.total_amount,
      'payment_method', o.payment_method,
      'status', o.status,
      'created_at', o.created_at
    ) as order_data,
    jsonb_build_object(
      'email', au.email,
      'full_name', au.raw_user_meta_data->>'full_name',
      'phone', au.raw_user_meta_data->>'phone'
    ) as customer_data,
    coalesce(items_json.items_data, '[]'::jsonb) as items_data,
    coalesce(address_json.address_data, '{}') as address_data,
    coalesce(payment_json.payment_data, '{}') as payment_slip_data
  from public.orders o
  left join auth.users au on o.user_id = au.id
  left join (
    select 
      order_id,
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'product_id', product_id,
          'quantity', quantity,
          'price', price,
          'product_name', (select name from public.products where id = order_items.product_id),
          'size', size,
          'color', color
        )
      ) as items_data
    from public.order_items
    group by order_id
  ) items_json on o.id = items_json.order_id
  left join (
    select 
      order_id,
      jsonb_build_object(
        'id', id,
        'full_name', full_name,
        'phone', phone,
        'address', address,
        'created_at', created_at
      ) as address_data
    from public.delivery_addresses
  ) address_json on o.id = address_json.order_id
  left join (
    select 
      order_id,
      jsonb_build_object(
        'id', id,
        'image_url', image_url,
        'verified', verified,
        'uploaded_at', uploaded_at,
        'verified_at', verified_at
      ) as payment_data
    from public.payment_slips
  ) payment_json on o.id = payment_json.order_id
  where o.id = order_uuid;
$$;

-- Admin function to get all payment slips for verification
create or replace function get_unverified_payment_slips()
returns table (
  id uuid,
  order_id uuid,
  order_total numeric,
  customer_name text,
  customer_email text,
  image_url text,
  uploaded_at timestamptz
)
language sql
as $$
  select 
    ps.id,
    ps.order_id,
    o.total_amount as order_total,
    au.raw_user_meta_data->>'full_name' as customer_name,
    au.email as customer_email,
    ps.image_url,
    ps.uploaded_at
  from public.payment_slips ps
  join public.orders o on ps.order_id = o.id
  join auth.users au on o.user_id = au.id
  where ps.verified = false
  order by ps.uploaded_at desc;
$$;

-- Admin function to get basic business metrics
create or replace function get_business_metrics()
returns table (
  total_customers bigint,
  total_orders bigint,
  total_revenue numeric,
  pending_orders bigint,
  processing_orders bigint
)
language sql
as $$
  select
    (select count(*) from auth.users)::bigint as total_customers,
    (select count(*) from public.orders)::bigint as total_orders,
    coalesce((select sum(total_amount) from public.orders where status in ('paid', 'confirmed', 'shipped', 'delivered')), 0) as total_revenue,
    (select count(*) from public.orders where status = 'pending_payment')::bigint as pending_orders,
    (select count(*) from public.orders where status in ('paid', 'confirmed', 'shipped'))::bigint as processing_orders;
$$;

-- Function to get all products with their image counts
create or replace function get_products_with_image_counts()
returns table (
  id uuid,
  name text,
  description text,
  price numeric,
  stock int,
  is_preorder boolean,
  is_active boolean,
  category_id uuid,
  image_count bigint,
  sizes text[],
  colors text[]
)
language sql
security definer
as $$
  select 
    p.id,
    p.name,
    p.description,
    p.price,
    p.stock,
    p.is_preorder,
    p.is_active,
    p.category_id,
    coalesce(img_counts.image_count, 0)::bigint as image_count,
    p.sizes,
    p.colors
  from public.products p
  left join (
    select 
      product_id,
      count(*) as image_count
    from public.product_images
    group by product_id
  ) img_counts on p.id = img_counts.product_id
  order by p.created_at desc;
$$;

-- Function to get product images
create or replace function get_product_images(p_product_id uuid)
returns table (
  id uuid,
  image_url text,
  alt_text text,
  is_primary boolean,
  sort_order int,
  created_at timestamptz
)
language sql
as $$
  select 
    pi.id,
    pi.image_url,
    pi.alt_text,
    pi.is_primary,
    pi.sort_order,
    pi.created_at
  from public.product_images pi
  where pi.product_id = p_product_id
  order by pi.sort_order, pi.created_at;
$$;