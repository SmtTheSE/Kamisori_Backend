-- Kamisori Backend - Update category constraint to allow cascade delete

-- Update the foreign key constraint to cascade delete products when category is deleted
alter table public.products drop constraint if exists products_category_id_fkey;
alter table public.products add constraint products_category_id_fkey 
  foreign key (category_id) 
  references public.product_categories(id) 
  on delete cascade;

-- Update notification table constraints to allow cascade delete of orders
alter table public.customer_notifications drop constraint if exists customer_notifications_order_id_fkey;
alter table public.customer_notifications add constraint customer_notifications_order_id_fkey
  foreign key (order_id) 
  references public.orders(id) 
  on delete cascade;

alter table public.payment_notifications drop constraint if exists payment_notifications_order_id_fkey;
alter table public.payment_notifications add constraint payment_notifications_order_id_fkey
  foreign key (order_id) 
  references public.orders(id) 
  on delete cascade;

alter table public.order_notifications drop constraint if exists order_notifications_order_id_fkey;
alter table public.order_notifications add constraint order_notifications_order_id_fkey
  foreign key (order_id) 
  references public.orders(id) 
  on delete cascade;

-- Admin delete functions

-- Function to delete a product and its images (admin only)
create or replace function admin_delete_product(
  product_uuid uuid
)
returns void
language plpgsql
as $$
declare
  v_product_exists int;
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can delete products';
  end if;

  -- Check if product exists
  select count(*) into v_product_exists
  from public.products
  where id = product_uuid;

  if v_product_exists = 0 then
    raise exception 'Product not found: %', product_uuid;
  end if;

  -- Delete the product (this will cascade delete product_images due to foreign key constraint)
  delete from public.products
  where id = product_uuid;

  if not found then
    raise exception 'Product could not be deleted: %', product_uuid;
  end if;
end;
$$;

-- Function to delete a category and its products (admin only)
create or replace function admin_delete_category(
  category_uuid uuid
)
returns void
language plpgsql
as $$
declare
  v_category_exists int;
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can delete categories';
  end if;

  -- Check if category exists
  select count(*) into v_category_exists
  from public.product_categories
  where id = category_uuid;

  if v_category_exists = 0 then
    raise exception 'Category not found: %', category_uuid;
  end if;

  -- Delete the category (this will cascade delete products due to foreign key constraint,
  -- which in turn will cascade delete product_images)
  delete from public.product_categories
  where id = category_uuid;

  if not found then
    raise exception 'Category could not be deleted: %', category_uuid;
  end if;
end;
$$;

-- Function to delete an order (admin only)
create or replace function admin_delete_order(
  order_uuid uuid
)
returns void
language plpgsql
as $$
declare
  v_order_exists int;
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can delete orders';
  end if;

  -- Check if order exists
  select count(*) into v_order_exists
  from public.orders
  where id = order_uuid;

  if v_order_exists = 0 then
    raise exception 'Order not found: %', order_uuid;
  end if;

  -- Delete related records first to avoid constraint violations
  -- The order of deletion matters due to foreign key constraints
  delete from public.customer_notifications where order_id = order_uuid;
  delete from public.payment_notifications where order_id = order_uuid;
  delete from public.order_notifications where order_id = order_uuid;
  delete from public.payment_slips where order_id = order_uuid;
  delete from public.delivery_addresses where order_id = order_uuid;
  delete from public.order_items where order_id = order_uuid;
  
  -- Finally delete the order itself
  delete from public.orders where id = order_uuid;

  -- Check if the order was successfully deleted
  get diagnostics v_order_exists = row_count;
  if v_order_exists = 0 then
    raise exception 'Order could not be deleted: %', order_uuid;
  end if;
end;
$$;
