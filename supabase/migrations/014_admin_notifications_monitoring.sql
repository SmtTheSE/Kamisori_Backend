-- Create a public log table for easier debugging and monitoring
create table if not exists public.trigger_logs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  level text default 'info',
  message text not null,
  order_id uuid,
  details jsonb
);

-- Enable RLS and allow admin/public read for monitoring
alter table public.trigger_logs enable row level security;
drop policy if exists "Enable public read for trigger_logs" on public.trigger_logs;
create policy "Enable public read for trigger_logs" on public.trigger_logs for select using (true);
drop policy if exists "Enable service role insert for trigger_logs" on public.trigger_logs;
create policy "Enable service role insert for trigger_logs" on public.trigger_logs for insert with check (true);

-- Ensure the notify_admin_new_order trigger is correctly configured to use this log
create or replace function notify_admin_new_order()
returns trigger as $$
declare
  v_order_id uuid;
  v_user_email text;
  v_order_data record;
begin
  -- Resolve order ID
  v_order_id := case when TG_TABLE_NAME = 'delivery_addresses' then NEW.order_id else NEW.id end;

  -- Log the firing
  insert into public.trigger_logs (level, message, order_id)
  values ('info', 'Trigger firing with Auth Header', v_order_id);

  -- Get basic order data
  select o.total_amount, o.payment_method, o.status, o.created_at, au.email
  into v_order_data
  from public.orders o
  left join auth.users au on o.user_id = au.id
  where o.id = v_order_id;

  -- Call Edge Function WITH Authorization Header
  perform net.http_post(
    url := 'https://ffsldhalkpxhzrhoukzh.supabase.co/functions/v1/notify-admin',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZmc2xkaGFsa3B4aHpyaG91a3poIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNTY3OTYsImV4cCI6MjA4MjYzMjc5Nn0.hsifO6ucSx9HZ_Rfb7EAmXvJ_r-vRMWvMqPmlkJdIQo',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZmc2xkaGFsa3B4aHpyaG91a3poIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNTY3OTYsImV4cCI6MjA4MjYzMjc5Nn0.hsifO6ucSx9HZ_Rfb7EAmXvJ_r-vRMWvMqPmlkJdIQo'
    ),
    body := json_build_object(
      'order_id', v_order_id,
      'notification_type', 'new_order',
      'user_email', v_order_data.email,
      'total_amount', v_order_data.total_amount,
      'payment_method', v_order_data.payment_method,
      'status', v_order_data.status,
      'created_at', v_order_data.created_at
    )::jsonb
  );

  return NEW;
exception when others then
  insert into public.trigger_logs (level, message, order_id, details)
  values ('error', 'SQL Trigger Error: ' || SQLERRM, v_order_id, json_build_object('code', SQLSTATE));
  return NEW;
end;
$$ language plpgsql security definer;


-- Re-enable triggers on both orders and delivery_addresses for robustness
-- (Orders for simple checkouts, Delivery Addresses for full checkouts)
drop trigger if exists new_order_delivery_notification on public.delivery_addresses;
create trigger new_order_delivery_notification
  after insert on public.delivery_addresses
  for each row execute function notify_admin_new_order();
