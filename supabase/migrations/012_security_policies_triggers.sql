-- Kamisori Backend - Security Policies and Triggers

-- This migration provides all security policies (RLS) and notification triggers
-- to ensure proper access control and system notifications

-- Create table to log customer notifications (Idempotent)
create table if not exists public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  notification_type text not null,
  message text not null,
  recipient_email text not null,
  sent_at timestamptz default now()
);

-- Create table to log payment notifications (Idempotent)
create table if not exists public.payment_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  notification_type text not null,
  message text not null,
  sent_at timestamptz default now()
);

-- Create table to log order notifications to admin (Idempotent)
create table if not exists public.order_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  notification_type text not null,
  message text not null,
  sent_at timestamptz default now()
);

-- Add RLS to notification tables
alter table public.customer_notifications enable row level security;
alter table public.payment_notifications enable row level security;
alter table public.order_notifications enable row level security;

-- Create trigger function for order status notifications to customers
create or replace function notify_customer_order_status()
returns trigger as $$
begin
  -- Only notify if status changed to one of the important statuses
  if (NEW.status in ('paid', 'confirmed', 'shipped', 'delivered', 'cancelled') 
      and OLD.status != NEW.status) then
    perform net.http_post(
      url := 'https://ffsldhalkpxhzrhoukzh.functions.supabase.co/notify-customer',
      body := json_build_object(
        'order_id', NEW.id,
        'new_status', NEW.status
      )::jsonb
    );
  end if;
  
  return NEW;
end;
$$ language plpgsql;

-- Drop the trigger if it exists, then create it
drop trigger if exists order_status_updated on public.orders;
create trigger order_status_updated
  after update of status on public.orders
  for each row execute function notify_customer_order_status();
  
-- Create trigger function for payment slip notifications to admin
create or replace function notify_admin_payment()
returns trigger as $$
begin
  perform net.http_post(
    url := 'https://ffsldhalkpxhzrhoukzh.functions.supabase.co/notify-admin',
    body := json_build_object(
      'order_id', new.order_id,
      'slip_url', new.image_url
    )::jsonb
  );
  return new;
end;
$$ language plpgsql;

drop trigger if exists payment_uploaded on public.payment_slips;
create trigger payment_uploaded
after insert on public.payment_slips
for each row execute function notify_admin_payment();

-- RLS policies for user roles
drop policy if exists "Admin manage user roles" on public.user_roles;
create policy "Admin manage user roles" on public.user_roles
for all using (is_admin()) with check (is_admin());

-- RLS policies for product categories
drop policy if exists "Public view active categories" on public.product_categories;
create policy "Public view active categories" on public.product_categories 
for select using (is_active = true);

drop policy if exists "Admin manage categories" on public.product_categories;
create policy "Admin manage categories" on public.product_categories
for all using (is_admin()) with check (is_admin());

-- RLS policies for products
drop policy if exists "Public view active products" on public.products;
create policy "Public view active products" on public.products 
for select using (is_active = true);

drop policy if exists "Admin manage products" on public.products;
create policy "Admin manage products" on public.products
for all using (is_admin()) with check (is_admin());

-- RLS policies for product images
drop policy if exists "Public read access to product_images" on public.product_images;
create policy "Public read access to product_images" on public.product_images
for select using (true);

drop policy if exists "Admin manage product_images" on public.product_images;
create policy "Admin manage product_images" on public.product_images
for all using (is_admin()) with check (is_admin());

-- RLS policies for carts
drop policy if exists "User owns cart" on public.carts;
create policy "User owns cart" on public.carts 
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "User owns cart items" on public.cart_items;
create policy "User owns cart items" on public.cart_items 
for all using (
  exists (
    select 1 from public.carts
    where id = cart_id
    and user_id = auth.uid()
  )
);

-- RLS policies for orders
drop policy if exists "Customers view own orders" on public.orders;
create policy "Customers view own orders" on public.orders 
for select using (user_id = auth.uid());

drop policy if exists "Admin view all orders" on public.orders;
create policy "Admin view all orders" on public.orders 
for select using (is_admin());

drop policy if exists "Admin update orders" on public.orders;
create policy "Admin update orders" on public.orders 
for update using (is_admin());

drop policy if exists "Customers insert orders" on public.orders;
create policy "Customers insert orders" on public.orders 
for insert with check (user_id = auth.uid());

drop policy if exists "Admin insert orders" on public.orders;
create policy "Admin insert orders" on public.orders 
for insert with check (is_admin());

-- RLS policies for order items
drop policy if exists "Customers view order items" on public.order_items;
create policy "Customers view order items" on public.order_items 
for select using (
  exists (
    select 1 from public.orders
    where id = order_items.order_id
    and user_id = auth.uid()
  )
);

drop policy if exists "Admin view all order items" on public.order_items;
create policy "Admin view all order items" on public.order_items 
for select using (is_admin());

-- RLS policies for delivery addresses
drop policy if exists "Customers view own delivery addresses" on public.delivery_addresses;
create policy "Customers view own delivery addresses" on public.delivery_addresses 
for select using (
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = auth.uid()
  )
);

drop policy if exists "Admin view all delivery addresses" on public.delivery_addresses;
create policy "Admin view all delivery addresses" on public.delivery_addresses 
for select using (is_admin());

drop policy if exists "Customers insert delivery addresses" on public.delivery_addresses;
create policy "Customers insert delivery addresses" on public.delivery_addresses 
for insert with check (
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = auth.uid()
  )
);

drop policy if exists "Customers update delivery addresses" on public.delivery_addresses;
create policy "Customers update delivery addresses" on public.delivery_addresses 
for update using (
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = auth.uid()
  )
);

drop policy if exists "Admin update delivery addresses" on public.delivery_addresses;
create policy "Admin update delivery addresses" on public.delivery_addresses 
for update using (is_admin());

drop policy if exists "Admin delete delivery addresses" on public.delivery_addresses;
create policy "Admin delete delivery addresses" on public.delivery_addresses 
for delete using (is_admin());

-- RLS policies for payment slips
drop policy if exists "Admin manage payment slips" on public.payment_slips;
create policy "Admin manage payment slips" on public.payment_slips 
for all using (is_admin()) with check (is_admin());

-- RLS policies for notification tables
drop policy if exists "Admin manage customer notifications" on public.customer_notifications;
create policy "Admin manage customer notifications" on public.customer_notifications 
for all using (is_admin());

drop policy if exists "Admin manage payment notifications" on public.payment_notifications;
create policy "Admin manage payment notifications" on public.payment_notifications 
for all using (is_admin());

drop policy if exists "Admin manage order notifications" on public.order_notifications;
create policy "Admin manage order notifications" on public.order_notifications 
for all using (is_admin());
-- Trigger for new order notifications (Fired after delivery address is saved)
drop trigger if exists new_order_delivery_notification on public.delivery_addresses;
create trigger new_order_delivery_notification
  after insert on public.delivery_addresses
  for each row execute function notify_admin_new_order();


