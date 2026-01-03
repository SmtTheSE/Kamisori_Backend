-- Kamisori Backend - Performance Optimization and Final Security Fixes
-- This migration adds performance indices and resolves persistent security warnings

-- 1. Performance Optimization - Indices on Foreign Keys
-- These indices significantly speed up joins and existence checks in application logic
create index if not exists idx_product_images_product_id on public.product_images(product_id);
create index if not exists idx_order_items_order_id on public.order_items(order_id);
create index if not exists idx_cart_items_cart_id on public.cart_items(cart_id);
create index if not exists idx_delivery_addresses_order_id on public.delivery_addresses(order_id);

-- 2. Refactor Product Count Query for better performance
-- Re-defining with SET search_path to satisfy linter and optimize query
create or replace function public.get_products_with_image_counts()
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
set search_path = public, pg_temp
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
    (select count(*) from public.product_images pi where pi.product_id = p.id)::bigint as image_count,
    p.sizes,
    p.colors
  from public.products p
  order by p.created_at desc;
$$;

-- 3. Force-fix "Search Path Mutable" for core business functions
-- Re-defining instead of just ALTER to ensure linter compliance

-- checkout_cart
create or replace function public.checkout_cart(
  p_payment_method text default 'bank_transfer',
  p_full_name text default null,
  p_phone text default null,
  p_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cart_id uuid;
  v_order_id uuid;
  v_total numeric;
begin
  -- Get the user's cart
  select id into v_cart_id
  from public.carts
  where user_id = auth.uid();

  -- Check if cart exists
  if v_cart_id is null then
    raise exception 'Cart is empty';
  end if;

  -- Calculate total amount
  select sum(ci.quantity * p.price) into v_total
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = v_cart_id;

  if v_total is null or v_total = 0 then
    raise exception 'Cart total is zero';
  end if;

  -- Create the order
  insert into public.orders (
    user_id, total_amount, payment_method, status
  ) values (
    auth.uid(), v_total, p_payment_method, 'pending'
  ) returning id into v_order_id;

  -- Move items from cart to order_items
  insert into public.order_items (
    order_id, product_id, quantity, price, size, color
  )
  select 
    v_order_id, ci.product_id, ci.quantity, p.price, ci.size, ci.color
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = v_cart_id;

  -- Add delivery address if provided
  insert into public.delivery_addresses (
    order_id, full_name, phone, address
  ) values (
    v_order_id, p_full_name, p_phone, p_address
  );

  -- Update stock for non-preorder items
  update public.products p
  set stock = p.stock - ci.quantity
  from public.cart_items ci
  where p.id = ci.product_id
    and p.is_preorder = false
    and ci.cart_id = v_cart_id;

  -- Clear the cart
  delete from public.cart_items where cart_id = v_cart_id;

  return v_order_id;
end;
$$;

-- admin_manage_product
create or replace function public.admin_manage_product(
  product_uuid uuid default null,
  product_name text default null,
  product_description text default null,
  product_price numeric default null,
  product_stock int default 0,
  product_is_preorder boolean default false,
  product_is_active boolean default true,
  category_uuid uuid default null,
  product_sizes text[] default null,
  product_colors text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_product_id uuid;
begin
  if not is_admin() then
    raise exception 'Access denied: Admin privileges required';
  end if;

  if product_uuid is not null then
    -- Update existing product
    update public.products
    set
      name = coalesce(product_name, name),
      description = coalesce(product_description, description),
      price = coalesce(product_price, price),
      stock = coalesce(product_stock, stock),
      is_preorder = coalesce(product_is_preorder, is_preorder),
      is_active = coalesce(product_is_active, is_active),
      category_id = coalesce(category_uuid, category_id),
      sizes = product_sizes,
      colors = product_colors
    where id = product_uuid
    returning id into v_product_id;
  else
    -- Insert new product
    insert into public.products (
      name, description, price, stock, is_preorder, is_active, category_id, sizes, colors
    ) values (
      product_name, product_description, product_price, product_stock, 
      product_is_preorder, product_is_active, category_uuid, product_sizes, product_colors
    ) returning id into v_product_id;
  end if;

  return v_product_id;
end;
$$;

-- Ensure is_admin is also fully secured
alter function public.is_admin() set search_path = public, pg_temp;
