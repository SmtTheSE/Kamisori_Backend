-- Kamisori Backend - Security Policies and Triggers
-- This migration provides all security policies (RLS) and notification triggers
-- to ensure proper access control and system notifications

-- Create trigger function for order status notifications to customers
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
  
-- Create trigger function for payment slip notifications to admin
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

-- RLS policies for user roles
create policy "Admin manage user roles" on public.user_roles
for all using (is_admin()) with check (is_admin());

-- RLS policies for product categories
create policy "Public view active categories" on public.product_categories 
for select using (is_active = true);

create policy "Admin manage categories" on public.product_categories
for all using (is_admin()) with check (is_admin());

-- RLS policies for products
create policy "Public view active products" on public.products 
for select using (is_active = true);

create policy "Admin manage products" on public.products
for all using (is_admin()) with check (is_admin());

-- RLS policies for product images
create policy "Public read access to product images" on public.product_images 
for select using (true);

create policy "Admin manage product images" on public.product_images
for all using (is_admin()) with check (is_admin());

-- RLS policies for carts
create policy "User owns cart" on public.carts 
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "User owns cart items" on public.cart_items 
for all using (
  exists (
    select 1 from public.carts
    where id = cart_id
    and user_id = auth.uid()
  )
);

-- RLS policies for orders
create policy "Customers view own orders" on public.orders 
for select using (user_id = auth.uid());

create policy "Admin view all orders" on public.orders 
for select using (is_admin());

create policy "Admin update orders" on public.orders 
for update using (is_admin());

create policy "Customers insert orders" on public.orders 
for insert with check (user_id = auth.uid());

create policy "Admin insert orders" on public.orders 
for insert with check (is_admin());

-- RLS policies for order items
create policy "Customers view order items" on public.order_items 
for select using (
  exists (
    select 1 from public.orders
    where id = order_items.order_id
    and user_id = auth.uid()
  )
);

create policy "Admin view all order items" on public.order_items 
for select using (is_admin());

-- RLS policies for delivery addresses
create policy "Customers view own delivery addresses" on public.delivery_addresses 
for select using (
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = auth.uid()
  )
);

create policy "Admin view all delivery addresses" on public.delivery_addresses 
for select using (is_admin());

create policy "Customers insert delivery addresses" on public.delivery_addresses 
for insert with check (
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = auth.uid()
  )
);

create policy "Customers update delivery addresses" on public.delivery_addresses 
for update using (
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = auth.uid()
  )
);

create policy "Admin update delivery addresses" on public.delivery_addresses 
for update using (is_admin());

create policy "Admin delete delivery addresses" on public.delivery_addresses 
for delete using (is_admin());

-- RLS policies for payment slips
create policy "Admin manage payment slips" on public.payment_slips 
for all using (is_admin()) with check (is_admin());

-- RLS policies for notification tables
create policy "Admin manage customer notifications" on public.customer_notifications 
for all using (is_admin());

create policy "Admin manage payment notifications" on public.payment_notifications 
for all using (is_admin());