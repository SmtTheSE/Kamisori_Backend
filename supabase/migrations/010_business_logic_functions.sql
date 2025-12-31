-- Kamisori Backend - Business Logic Functions
-- This migration provides all core business logic functions for the application
-- including checkout, product management, and order processing

-- Checkout function - processes cart and creates an order
create or replace function public.checkout_cart(
  p_payment_method text,
  p_full_name text,
  p_phone text,
  p_address text
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_cart_id uuid;
  v_order_id uuid;
  v_total numeric;
  v_user_email text;
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
  select sum(ci.quantity * p.price)
  into v_total
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = v_cart_id;

  -- Create the order
  insert into public.orders (
    user_id, total_amount, payment_method, status
  ) values (
    auth.uid(),
    v_total,
    p_payment_method,
    case
      when p_payment_method = 'kbz_pay' then 'pending_payment'
      else 'pending_confirmation'
    end
  ) returning id into v_order_id;

  -- Create order items from cart items
  insert into public.order_items (
    order_id, product_id, quantity, price, size, color
  )
  select
    v_order_id,
    ci.product_id,
    ci.quantity,
    p.price,
    ci.size,
    ci.color
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = v_cart_id;

  -- Save delivery address
  insert into public.delivery_addresses (
    order_id, full_name, phone, address
  ) values (
    v_order_id, p_full_name, p_phone, p_address
  );

  -- Update stock for non-preorder items
  update public.products p
  set stock = stock - ci.quantity
  from public.cart_items ci
  where p.id = ci.product_id
    and p.is_preorder = false
    and ci.cart_id = v_cart_id;

  -- Get user email for notification logging
  select email into v_user_email from auth.users where id = auth.uid();

  -- Clear the cart
  delete from public.cart_items where cart_id = v_cart_id;

  return v_order_id;
end;

$$;

-- Function to notify admin of new order with complete information
create table if not exists public.debug_triggers (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  message text,
  payload jsonb
);

create or replace function notify_admin_new_order()
returns trigger as $$
declare
  v_order_id uuid;
  v_user_id uuid;
  v_user_email text;
  v_total_amount numeric;
  v_payment_method text;
  v_status text;
  v_created_at timestamptz;
begin
  -- Resolve order ID based on which table triggered this
  if (TG_TABLE_NAME = 'delivery_addresses') then
    v_order_id := NEW.order_id;
  else
    v_order_id := NEW.id;
  end if;

  -- Get order details
  select user_id, total_amount, payment_method, status, created_at
  into v_user_id, v_total_amount, v_payment_method, v_status, v_created_at
  from public.orders
  where id = v_order_id;

  -- Get user email from auth.users
  select email into v_user_email
  from auth.users
  where id = v_user_id;
  
  -- DEBUG LOG
  insert into public.debug_triggers (message, payload)
  values ('Trigger firing', json_build_object('order_id', v_order_id, 'user_email', v_user_email));

  -- Send notification with comprehensive order information
  perform net.http_post(
    url := 'https://ffsldhalkpxhzrhoukzh.functions.supabase.co/notify-admin',
    body := json_build_object(
      'order_id', v_order_id,
      'notification_type', 'new_order',
      'user_id', v_user_id,
      'user_email', v_user_email,
      'total_amount', v_total_amount,
      'payment_method', v_payment_method,
      'status', v_status,
      'created_at', v_created_at
    )::jsonb
  );
  return NEW;
end;
$$ language plpgsql;


-- Explicitly drop the old premature trigger if it still exists
drop trigger if exists new_order_notification on public.orders;


-- Function to manage product categories (admin only)
create or replace function admin_manage_category(
  category_uuid uuid default null,  -- If null, create new category
  category_season season_enum default null,
  category_year int default null
)
returns uuid
language plpgsql
as $$
declare
  v_category_id uuid;
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can manage categories';
  end if;

  -- Validate required fields for creation
  if category_uuid is null then
    if category_season is null or category_year is null then
      raise exception 'For category creation: season and year are required';
    end if;

    -- Create new category
    insert into public.product_categories (
      season,
      year
    ) values (
      category_season,
      category_year
    ) returning id into v_category_id;
  else
    -- Update existing category
    update public.product_categories
    set
      season = coalesce(category_season, season),
      year = coalesce(category_year, year)
    where id = category_uuid;

    if not found then
      raise exception 'Category not found: %', category_uuid;
    end if;

    v_category_id := category_uuid;
  end if;

  return v_category_id;
end;
$$;

-- Function to manage products (admin only)
create or replace function admin_manage_product(
  product_uuid uuid default null,  -- If null, create new product
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
      product_name, product_description, product_price, product_stock, product_is_preorder, product_is_active, category_uuid, product_sizes, product_colors
    ) returning id into v_product_id;
  end if;

  return v_product_id;
end;
$$;

-- Function to manage product images (admin only)
create or replace function admin_manage_product_image(
  product_uuid uuid,
  image_url text,
  alt_text text default null,
  is_primary boolean default false,
  sort_order int default 0
)
returns uuid
language plpgsql
as $$
declare
  v_image_id uuid;
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can manage product images';
  end if;

  -- Validate required fields
  if product_uuid is null or image_url is null then
    raise exception 'Product ID and image URL are required';
  end if;

  -- Validate product exists
  if not exists (select 1 from public.products where id = product_uuid) then
    raise exception 'Product not found: %', product_uuid;
  end if;

  -- If setting as primary, unset other primary images for this product
  if is_primary then
    update public.product_images
    set is_primary = false
    where product_id = product_uuid;
  end if;

  -- Insert the new image
  insert into public.product_images (
    product_id,
    image_url,
    alt_text,
    is_primary,
    sort_order
  ) values (
    product_uuid,
    image_url,
    alt_text,
    is_primary,
    sort_order
  ) returning id into v_image_id;

  return v_image_id;
end;
$$;

-- Function to update product image (admin only)
create or replace function admin_update_product_image(
  image_uuid uuid,
  new_alt_text text default null,
  new_is_primary boolean default null,
  new_sort_order int default null
)
returns void
language plpgsql
as $$
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can update product images';
  end if;

  -- Validate image exists
  if not exists (select 1 from public.product_images where id = image_uuid) then
    raise exception 'Image not found: %', image_uuid;
  end if;

  -- Update the image
  update public.product_images
  set
    alt_text = coalesce(new_alt_text, alt_text),
    sort_order = coalesce(new_sort_order, sort_order)
  where id = image_uuid;

  -- If updating primary status
  if new_is_primary is not null then
    if new_is_primary then
      -- Unset other primary images for this product
      update public.product_images
      set is_primary = false
      where product_id = (select product_id from public.product_images where id = image_uuid)
        and id != image_uuid;
      
      -- Set this image as primary
      update public.product_images
      set is_primary = true
      where id = image_uuid;
    end if;
  end if;

end;
$$;

-- Function to delete product image (admin only)
create or replace function admin_delete_product_image(
  image_uuid uuid
)
returns void
language plpgsql
as $$
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can delete product images';
  end if;

  -- Delete the image
  delete from public.product_images
  where id = image_uuid;

  if not found then
    raise exception 'Image not found: %', image_uuid;
  end if;
end;
$$;

-- Function to toggle active status of products/categories (admin only)
create or replace function admin_toggle_active_status(
  table_name text,
  record_uuid uuid,
  active_status boolean
)
returns void
language plpgsql
as $$
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can manage active status';
  end if;

  case table_name
    when 'products' then
      update public.products
      set is_active = active_status
      where id = record_uuid;
      
      if not found then
        raise exception 'Product not found: %', record_uuid;
      end if;
    when 'product_categories' then
      update public.product_categories
      set is_active = active_status
      where id = record_uuid;
      
      if not found then
        raise exception 'Category not found: %', record_uuid;
      end if;
    else
      raise exception 'Invalid table name: %', table_name;
  end case;
end;
$$;

-- Function to update order status (admin only)
create or replace function admin_update_order_status(
  order_uuid uuid,
  new_status text
)
returns void
language plpgsql
as $$
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can update order status';
  end if;

  -- Validate status
  if new_status not in ('pending_payment', 'pending_confirmation', 'paid', 'confirmed', 'shipped', 'delivered', 'cancelled') then
    raise exception 'Invalid status: %', new_status;
  end if;

  -- Update order status
  update public.orders
  set status = new_status
  where id = order_uuid;

  if not found then
    raise exception 'Order not found: %', order_uuid;
  end if;
end;
$$;

-- Function to verify payment slip (admin only)
create or replace function admin_verify_payment_slip(
  slip_uuid uuid,
  verified_status boolean default true
)
returns void
language plpgsql
as $$
declare
  v_order_id uuid;
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can verify payment slips';
  end if;

  -- Get the order ID before updating
  select order_id into v_order_id
  from public.payment_slips
  where id = slip_uuid;

  if not found then
    raise exception 'Payment slip not found: %', slip_uuid;
  end if;

  -- Update payment slip verification status
  update public.payment_slips
  set 
    verified = verified_status,
    verified_at = case 
      when verified_status then now()
      else null
    end
  where id = slip_uuid;

  -- If verified, update order status to 'paid'
  if verified_status then
    update public.orders
    set status = 'paid'
    where id = v_order_id;
  end if;
end;
$$;