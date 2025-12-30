# Step-by-Step Guide: Setting Up the Database Schema in Supabase

This guide will walk you through setting up the complete e-commerce database schema in your Supabase project.

## Step 1: Access Your Supabase Dashboard

1. Go to [supabase.com](https://supabase.com) and log into your account
2. Navigate to your project dashboard
3. Click on "SQL Editor" in the left sidebar

## Step 2: Run Migration 001 - Initial Schema

Copy and paste the following SQL code into the SQL Editor and click "Run":

```sql
-- Enable required extensions
create extension if not exists "uuid-ossp";
create extension if not exists "moddatetime";

-- Create season enum
create type season_enum as enum ('summer', 'fall', 'winter');

-- User roles table
create table public.user_roles (
  user_id uuid references auth.users(id) on delete cascade,
  role text check (role in ('admin', 'customer')) not null,
  primary key (user_id)
);

-- Product categories table
create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  season season_enum not null,
  year int not null check (year >= 2024),
  is_active boolean default true,
  is_featured boolean default false,
  created_at timestamptz default now(),
  unique (season, year)
);

-- Product categories label view
create view public.product_category_labels as
select
  id,
  initcap(season::text) || ' ' || year as label,
  season,
  year,
  is_active
from public.product_categories;

-- Products table
create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  price numeric(10,2) not null,
  stock int,
  is_preorder boolean default false,
  is_active boolean default true,
  category_id uuid references public.product_categories(id),
  created_at timestamptz default now()
);

-- Carts table
create table public.carts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  updated_at timestamptz default now()
);

-- Enable moddatetime trigger for carts
create trigger update_cart_updated_at
before update on public.carts
for each row
execute procedure moddatetime(updated_at);

-- Cart items table
create table public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid references public.carts(id) on delete cascade,
  product_id uuid references public.products(id),
  quantity int not null check (quantity > 0),
  unique (cart_id, product_id)
);

-- Cart totals view
create view public.cart_totals as
select
  c.user_id,
  sum(ci.quantity * p.price) as total_amount
from public.carts c
join public.cart_items ci on ci.cart_id = c.id
join public.products p on p.id = ci.product_id
where p.is_active = true
group by c.user_id;

-- Orders table
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  total_amount numeric(10,2) not null,
  payment_method text check (payment_method in ('kbz_pay','cod')) not null,
  status text not null,
  created_at timestamptz default now()
);

-- Order items table
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  quantity int not null,
  price numeric(10,2) not null
);

-- Delivery addresses table
create table public.delivery_addresses (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  full_name text not null,
  phone text not null,
  address text not null,
  created_at timestamptz default now()
);

-- Payment slips table
create table public.payment_slips (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  image_url text not null,
  verified boolean default false,
  uploaded_at timestamptz default now(),
  verified_at timestamptz
);

-- Admin helper function
create or replace function is_admin()
returns boolean language sql stable as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
    and role = 'admin'
  );
$$;

-- Checkout function
create or replace function public.checkout_cart(
  p_payment_method text
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_cart_id uuid;
  v_order_id uuid;
  v_total numeric;
begin
  select id into v_cart_id
  from public.carts
  where user_id = auth.uid();

  if v_cart_id is null then
    raise exception 'Cart is empty';
  end if;

  select sum(ci.quantity * p.price)
  into v_total
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = v_cart_id;

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

  insert into public.order_items (
    order_id, product_id, quantity, price
  )
  select
    v_order_id,
    ci.product_id,
    ci.quantity,
    p.price
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = v_cart_id;

  update public.products p
  set stock = stock - ci.quantity
  from public.cart_items ci
  where p.id = ci.product_id
    and p.is_preorder = false;

  delete from public.cart_items where cart_id = v_cart_id;

  return v_order_id;
end;
$$;

-- Enable Row Level Security

-- Carts
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;

create policy "User owns cart"
on public.carts for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "User owns cart items"
on public.cart_items for all
using (
  exists (
    select 1 from public.carts
    where id = cart_id
    and user_id = auth.uid()
  )
);

-- Orders
alter table public.orders enable row level security;

create policy "Customer view own orders"
on public.orders for select
using (user_id = auth.uid());

create policy "Admin view all orders"
on public.orders for select
using (is_admin());

create policy "Admin update orders"
on public.orders for update
using (is_admin());

-- Categories & Products
alter table public.product_categories enable row level security;
alter table public.products enable row level security;

create policy "Public view active categories"
on public.product_categories for select
using (is_active = true);

create policy "Admin manage categories"
on public.product_categories
for all
using (is_admin())
with check (is_admin());

create policy "Public view active products"
on public.products for select
using (is_active = true);

create policy "Admin manage products"
on public.products
for all
using (is_admin())
with check (is_admin());

-- Payment slips
alter table public.payment_slips enable row level security;

create policy "Admin manage payment slips"
on public.payment_slips for all
using (is_admin())
with check (is_admin());

-- Delivery addresses
alter table public.delivery_addresses enable row level security;

create policy "Customers view own delivery addresses"
on public.delivery_addresses for select
using (
  exists (
    select 1 from public.orders
    where orders.id = order_id
    and user_id = auth.uid()
  )
);

create policy "Admin view all delivery addresses"
on public.delivery_addresses for select
using (is_admin());

-- Create trigger for payment slip notifications
create or replace function notify_admin_payment()
returns trigger as $$
begin
  perform net.http_post(
    url := 'https://PROJECT.functions.supabase.co/notify-admin',
    body := json_build_object(
      'order_id', new.order_id,
      'slip_url', new.image_url
    )::text
  );
  return new;
end;
$$ language plpgsql;

create trigger payment_uploaded
after insert on public.payment_slips
for each row execute function notify_admin_payment();
```

Wait for the script to complete successfully before proceeding to the next step.

## Step 3: Run Migration 002 - Order Status Trigger

Copy and paste the following SQL code into the SQL Editor and click "Run":

```sql
-- Create a trigger function to notify customers when order status changes
create or replace function notify_customer_order_status()
returns trigger as $$
begin
  -- Only notify if status changed to one of the important statuses
  if (NEW.status in ('paid', 'confirmed', 'shipped', 'delivered', 'cancelled') 
      and OLD.status != NEW.status) then
    perform net.http_post(
      url := 'https://PROJECT.functions.supabase.co/notify-customer',
      body := json_build_object(
        'order_id', NEW.id,
        'new_status', NEW.status
      )::text
    );
  end if;
  
  return NEW;
end;
$$ language plpgsql;

-- Create the trigger on the orders table
create trigger order_status_updated
  after update of status on public.orders
  for each row execute function notify_customer_order_status();
  
-- Create table to log customer notifications
create table public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  notification_type text not null,
  message text not null,
  recipient_email text not null,
  sent_at timestamptz default now()
);

-- Create table to log payment notifications
create table public.payment_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  notification_type text not null,
  message text not null,
  sent_at timestamptz default now()
);

-- Add RLS to notification tables
alter table public.customer_notifications enable row level security;
alter table public.payment_notifications enable row level security;

-- Policies for notification tables
create policy "Admin manage customer notifications"
on public.customer_notifications for all
using (is_admin());

create policy "Admin manage payment notifications"
on public.payment_notifications for all
using (is_admin());
```

Wait for the script to complete successfully before proceeding to the next step.

## Step 4: Run Migration 003 - Admin CRUD Functions

Copy and paste the following SQL code into the SQL Editor and click "Run":

```sql
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
  created_at timestamptz
)
language sql
as $$
  select 
    o.id,
    o.user_id,
    au.email as customer_email,
    au.raw_user_meta_data->>'full_name' as customer_full_name,
    o.total_amount,
    o.payment_method,
    o.status,
    o.created_at
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
          'product_name', (select name from public.products where id = order_items.product_id)
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

-- Admin function to update order status
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

-- Admin function to verify payment slip
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

-- Admin function to create/update product
create or replace function admin_manage_product(
  product_uuid uuid default null,  -- If null, create new product
  product_name text default null,
  product_description text default null,
  product_price numeric default null,
  product_stock int default null,
  product_is_preorder boolean default false,
  product_is_active boolean default true,
  category_uuid uuid default null
)
returns uuid
language plpgsql
as $$
declare
  v_product_id uuid;
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can manage products';
  end if;

  -- Validate required fields for creation
  if product_uuid is null then
    if product_name is null or product_price is null or category_uuid is null then
      raise exception 'For product creation: name, price, and category are required';
    end if;
    
    -- Validate category exists
    if not exists (select 1 from public.product_categories where id = category_uuid) then
      raise exception 'Category not found: %', category_uuid;
    end if;

    -- Create new product
    insert into public.products (
      name,
      description,
      price,
      stock,
      is_preorder,
      is_active,
      category_id
    ) values (
      product_name,
      product_description,
      product_price,
      product_stock,
      product_is_preorder,
      product_is_active,
      category_uuid
    ) returning id into v_product_id;
  else
    -- Update existing product
    update public.products
    set
      name = coalesce(product_name, name),
      description = coalesce(product_description, description),
      price = coalesce(product_price, price),
      stock = coalesce(product_stock, stock),
      is_preorder = coalesce(product_is_preorder, is_preorder),
      is_active = coalesce(product_is_active, is_active),
      category_id = coalesce(category_uuid, category_id)
    where id = product_uuid;

    if not found then
      raise exception 'Product not found: %', product_uuid;
    end if;

    v_product_id := product_uuid;
  end if;

  return v_product_id;
end;
$$;

-- Admin function to create/update product category
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

-- Admin function to toggle category/product active status
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
        raise exception 'Category not found: %', category_uuid;
      end if;
    else
      raise exception 'Invalid table name: %', table_name;
  end case;
end;
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
```

Wait for the script to complete successfully before proceeding to the next step.

## Step 5: Configure Storage Buckets

1. In your Supabase dashboard, click on "Storage" in the left sidebar
2. Create a bucket named `product-images`:
   - Click "New Bucket"
   - Name: `product-images`
   - Public: Check this box (public read, admin write via RLS)
   - Click "Create"
3. Create a bucket named `payment-slips`:
   - Click "New Bucket"
   - Name: `payment-slips`
   - Public: Leave unchecked (private, admin read)
   - Click "Create"

## Step 6: Run Migration 004 - Storage RLS Policies

After creating the storage buckets, run the following SQL to set up RLS policies for storage:

```sql
-- RLS policies for storage buckets

-- RLS policies for product-images bucket
-- Only authenticated users with admin role can upload images
CREATE POLICY "Admin can upload product images" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'product-images' AND (SELECT is_admin()));

-- Only authenticated users with admin role can update product images  
CREATE POLICY "Admin can update product images" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'product-images' AND (SELECT is_admin()));

-- Only authenticated users with admin role can delete product images
CREATE POLICY "Admin can delete product images" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'product-images' AND (SELECT is_admin()));

-- Everyone can read product images
CREATE POLICY "Public can read product images" ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'product-images');

-- RLS policies for payment-slips bucket
-- Only authenticated users with admin role can upload payment slips
CREATE POLICY "Admin can upload payment slips" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'payment-slips' AND (SELECT is_admin()));

-- Only authenticated users with admin role can update payment slips
CREATE POLICY "Admin can update payment slips" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'payment-slips' AND (SELECT is_admin()));

-- Only authenticated users with admin role can delete payment slips
CREATE POLICY "Admin can delete payment slips" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'payment-slips' AND (SELECT is_admin()));

-- Only authenticated users with admin role can read payment slips
CREATE POLICY "Admin can read payment slips" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'payment-slips' AND (SELECT is_admin()));
```

## Step 7: Run Migration 005 - Product Images

Copy and paste the following SQL code into the SQL Editor and click "Run":

```sql
-- Create product_images table to store images associated with products
create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  image_url text not null,
  alt_text text,
  is_primary boolean default false,
  sort_order int default 0,
  created_at timestamptz default now()
);

-- Add RLS policies for product_images
alter table public.product_images enable row level security;

-- Policy: Allow public read access to product images
create policy "Public read access to product images" on public.product_images for select
  using (true);

-- Policy: Only admin can manage product images
create policy "Admin manage product images" on public.product_images for all
  using (is_admin())
  with check (is_admin());

-- Create index for better performance
create index idx_product_images_product_id on public.product_images (product_id);

-- Create function to get product images
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

-- Create function to manage product images
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

-- Create function to update product image
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

-- Create function to delete product image
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

-- Create function to get all products with their image counts
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
  image_count bigint
)
language sql
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
    coalesce(img_counts.image_count, 0)::bigint as image_count
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
```

## Step 8: Test the Setup

1. Open the [demo-frontend.html](file:///Users/sittminthar/Desktop/Kamisori%20Backend/demo-frontend.html) file in your browser
2. You can now test the frontend with your Supabase project
3. To test admin functions, you'll need to create a user and assign them the admin role:

```sql
-- In the SQL Editor, run this to make a user an admin:
-- Replace 'user-uuid-here' with the actual user ID from the Auth tab
INSERT INTO public.user_roles (user_id, role) 
VALUES ('user-uuid-here', 'admin');
```

## Troubleshooting

If you encounter any issues:

1. Check that all migration scripts have been run successfully
2. Ensure that Row Level Security (RLS) is enabled on all tables
3. Verify that the `is_admin()` function returns the correct results
4. Confirm that your storage buckets have the correct access settings and RLS policies

Your database schema is now fully set up and ready to use with the frontend!