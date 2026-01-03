-- Kamisori Backend - RLS Performance and Policy Consolidation
-- This migration optimizes RLS policies for scalability and resolves all lingering linter warnings

-- 0. Update is_admin to use optimized subquery pattern
create or replace function public.is_admin()
returns boolean 
language sql 
stable 
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = (select auth.uid())
    and role = 'admin'
  );
$$;

-- 1. Orders Consolidation & Optimization
drop policy if exists "Customers view own orders" on public.orders;
drop policy if exists "Customer view own orders" on public.orders;
drop policy if exists "Admin view all orders" on public.orders;
drop policy if exists "View orders" on public.orders;
create policy "View orders" on public.orders 
for select to authenticated 
using (((select auth.uid()) = user_id) or is_admin());

drop policy if exists "Customers insert orders" on public.orders;
drop policy if exists "Customer insert orders" on public.orders;
drop policy if exists "Admin insert orders" on public.orders;
drop policy if exists "Insert orders" on public.orders;
create policy "Insert orders" on public.orders 
for insert to authenticated 
with check (((select auth.uid()) = user_id) or is_admin());

drop policy if exists "Admin update orders" on public.orders;
create policy "Admin update orders" on public.orders 
for update to authenticated 
using (is_admin());

-- 2. Order Items Consolidation & Optimization
drop policy if exists "Customers view order items" on public.order_items;
drop policy if exists "Customer view order items" on public.order_items;
drop policy if exists "Admin view all order items" on public.order_items;
drop policy if exists "View order items" on public.order_items;
create policy "View order items" on public.order_items 
for select to authenticated 
using (
  is_admin() or
  exists (
    select 1 from public.orders
    where id = order_items.order_id
    and user_id = (select auth.uid())
  )
);

-- 3. Delivery Addresses Consolidation & Optimization
drop policy if exists "Customers view own delivery addresses" on public.delivery_addresses;
drop policy if exists "Customer view own delivery addresses" on public.delivery_addresses;
drop policy if exists "Admin view all delivery addresses" on public.delivery_addresses;
drop policy if exists "View delivery addresses" on public.delivery_addresses;
create policy "View delivery addresses" on public.delivery_addresses 
for select to authenticated 
using (
  is_admin() or
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = (select auth.uid())
  )
);

drop policy if exists "Customers insert delivery addresses" on public.delivery_addresses;
drop policy if exists "Customer insert delivery addresses" on public.delivery_addresses;
drop policy if exists "Admin insert delivery addresses" on public.delivery_addresses;
drop policy if exists "Insert delivery addresses" on public.delivery_addresses;
create policy "Insert delivery addresses" on public.delivery_addresses 
for insert to authenticated 
with check (
  is_admin() or
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = (select auth.uid())
  )
);

drop policy if exists "Customers update delivery addresses" on public.delivery_addresses;
drop policy if exists "Customer update delivery addresses" on public.delivery_addresses;
drop policy if exists "Admin update delivery addresses" on public.delivery_addresses;
drop policy if exists "Update delivery addresses" on public.delivery_addresses;
create policy "Update delivery addresses" on public.delivery_addresses 
for update to authenticated 
using (
  is_admin() or
  exists (
    select 1 from public.orders
    where orders.id = delivery_addresses.order_id
    and user_id = (select auth.uid())
  )
);

drop policy if exists "Admin delete delivery addresses" on public.delivery_addresses;
create policy "Admin delete delivery addresses" on public.delivery_addresses 
for delete to authenticated 
using (is_admin());

-- 4. Carts & Cart Items Optimization
drop policy if exists "User owns cart" on public.carts;
create policy "User owns cart" on public.carts 
for all to authenticated 
using (user_id = (select auth.uid())) 
with check (user_id = (select auth.uid()));

drop policy if exists "User owns cart items" on public.cart_items;
create policy "User owns cart items" on public.cart_items 
for all to authenticated 
using (
  exists (
    select 1 from public.carts
    where id = cart_id
    and user_id = (select auth.uid())
  )
);

-- 5. Products & Categories Public Access Consolidation
drop policy if exists "Public view active products" on public.products;
drop policy if exists "Admin manage products" on public.products;
drop policy if exists "Manage or view products" on public.products;
create policy "Manage or view products" on public.products
for all to anon, authenticated 
using (is_active = true or is_admin())
with check (is_admin());

drop policy if exists "Public view active categories" on public.product_categories;
drop policy if exists "Admin manage categories" on public.product_categories;
drop policy if exists "Manage or view categories" on public.product_categories;
create policy "Manage or view categories" on public.product_categories
for all to anon, authenticated 
using (is_active = true or is_admin())
with check (is_admin());

drop policy if exists "Public read access to product_images" on public.product_images;
drop policy if exists "Admin manage product_images" on public.product_images;
drop policy if exists "Manage or view product_images" on public.product_images;
create policy "Manage or view product_images" on public.product_images
for all to anon, authenticated 
using (true or is_admin())
with check (is_admin());

-- 6. User Roles policy optimization
drop policy if exists "Admin manage user roles" on public.user_roles;
create policy "Admin manage user roles" on public.user_roles
for all to authenticated 
using (is_admin()) 
with check (is_admin());

-- 7. High-Performance Indices for common queries
-- Speed up order history for users and admin management
create index if not exists idx_orders_created_at on public.orders(created_at desc);
create index if not exists idx_orders_user_id on public.orders(user_id);

-- Speed up product listings and active checks
create index if not exists idx_products_is_active on public.products(is_active);
create index if not exists idx_product_categories_is_active on public.product_categories(is_active);

-- 8. Final Definitive Search Path Fixes
-- These functions were redefined in migration 019 with SET search_path in the CREATE statement.
-- However, the linter may still flag them if the migration hasn't been applied yet.
-- This ALTER ensures the search_path is set regardless of migration state.

-- The current signature has default values (from migration 019)
alter function public.checkout_cart(text, text, text, text) set search_path = public, pg_temp;
alter function public.admin_manage_product(uuid, text, text, numeric, int, boolean, boolean, uuid, text[], text[]) set search_path = public, pg_temp;
