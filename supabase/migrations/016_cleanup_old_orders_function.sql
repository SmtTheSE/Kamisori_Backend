-- Function to clean up old orders for storage management (admin only)

-- Function to delete old orders based on date threshold
create or replace function admin_cleanup_old_orders(
  older_than_date timestamptz default now() - interval '6 months'
)
returns table (
  orders_deleted int,
  items_deleted int,
  addresses_deleted int,
  payment_slips_deleted int,
  notifications_deleted int
)
language plpgsql
as $$
declare
  v_orders_deleted int := 0;
  v_items_deleted int := 0;
  v_addresses_deleted int := 0;
  v_payment_slips_deleted int := 0;
  v_notifications_deleted int := 0;
  v_order_ids uuid[];
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can clean up old orders';
  end if;

  -- Get IDs of orders that are older than the specified date
  select array_agg(id) into v_order_ids
  from public.orders
  where created_at < older_than_date;

  if v_order_ids is null or array_length(v_order_ids, 1) is null then
    -- Return 0 values if no orders to delete
    return query select 0, 0, 0, 0;
    return;
  end if;

  -- Delete related records in the correct order to avoid constraint violations
  -- 1. Delete from notification tables
  delete from public.customer_notifications where order_id = any(v_order_ids);
  get diagnostics v_notifications_deleted = row_count;
  
  delete from public.payment_notifications where order_id = any(v_order_ids);
  delete from public.order_notifications where order_id = any(v_order_ids);
  
  -- 2. Delete payment slips
  delete from public.payment_slips where order_id = any(v_order_ids);
  get diagnostics v_payment_slips_deleted = row_count;
  
  -- 3. Delete delivery addresses
  delete from public.delivery_addresses where order_id = any(v_order_ids);
  get diagnostics v_addresses_deleted = row_count;
  
  -- 4. Delete order items
  delete from public.order_items where order_id = any(v_order_ids);
  get diagnostics v_items_deleted = row_count;
  
  -- 5. Finally delete the orders themselves
  delete from public.orders where id = any(v_order_ids);
  get diagnostics v_orders_deleted = row_count;

  -- Return the counts of deleted records
  return query 
    select 
      v_orders_deleted,
      v_items_deleted,
      v_addresses_deleted,
      v_payment_slips_deleted,
      v_notifications_deleted + v_payment_slips_deleted as notifications_deleted; -- combine both notification counts
end;
$$;

-- Function to count old orders that would be affected by cleanup
create or replace function admin_count_old_orders(
  older_than_date timestamptz default now() - interval '6 months'
)
returns table (
  total_count bigint,
  pending_count bigint,
  paid_count bigint,
  cancelled_count bigint
)
language plpgsql
as $$
begin
  -- Check if user is admin
  if not is_admin() then
    raise exception 'Permission denied: Only admins can count old orders';
  end if;

  return query
  select 
    count(*)::bigint as total_count,
    count(case when status = 'pending_payment' then 1 end)::bigint as pending_count,
    count(case when status in ('paid', 'confirmed', 'shipped', 'delivered') then 1 end)::bigint as paid_count,
    count(case when status = 'cancelled' then 1 end)::bigint as cancelled_count
  from public.orders
  where created_at < older_than_date;
end;
$$;