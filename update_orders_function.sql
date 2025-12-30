-- Script to update the get_all_orders_admin function
-- This should be run in your Supabase SQL editor or via the command line

-- First, drop the existing function
drop function if exists get_all_orders_admin(int, int);

-- Create the updated function
create or replace function get_all_orders_admin(
  page_offset int default 0,
  page_limit int default 50
)
returns table (
  id uuid,
  user_id uuid,
  customer_email text,
  customer_full_name text,
  delivery_customer_full_name text,
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
    (select da.full_name 
     from public.delivery_addresses da 
     where da.order_id = o.id limit 1) as delivery_customer_full_name,
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