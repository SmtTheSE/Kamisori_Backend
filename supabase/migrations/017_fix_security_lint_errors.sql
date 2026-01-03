-- Kamisori Backend - Security Lint Fixes
-- This migration addresses security vulnerabilities reported by the Supabase linter

-- 1. Update is_admin() to be SECURITY DEFINER
-- This is necessary to avoid infinite recursion/circular dependency when RLS is enabled on user_roles
-- search_path is set to public for security following best practices
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
    and role = 'admin'
  );
$$;

-- 2. Explicitly enable RLS on tables flagged for having policies but RLS disabled
-- Note: These tables were previously altered in 009_clean_schema_setup.sql, 
-- but the linter reports they are still disabled or were not correctly applied in the environment.
alter table public.order_items enable row level security;
alter table public.user_roles enable row level security;

-- 3. Update views to use SECURITY INVOKER (Postgres 15+ feature)
-- This ensures that the views respect the RLS policies of the querying user.

-- Update product_category_labels view
create or replace view public.product_category_labels 
with (security_invoker = true) 
as
select
  id,
  initcap(season::text) || ' ' || year as label,
  season,
  year,
  is_active
from public.product_categories;

-- Update cart_totals view
create or replace view public.cart_totals 
with (security_invoker = true)
as
select
  c.user_id,
  sum(ci.quantity * p.price) as total_amount
from public.carts c
join public.cart_items ci on ci.cart_id = c.id
join public.products p on p.id = ci.product_id
where p.is_active = true
group by c.user_id;
