-- Kamisori Backend - Security Warning Fixes
-- This migration addresses "Search Path Mutable" (Lint 0011) and "Extension in Public" (Lint 0014) warnings

-- 1. Address "Extension in Public" warning for moddatetime
create schema if not exists extensions;
alter extension moddatetime set schema extensions;

-- Update the trigger that uses moddatetime to use the schema-qualified name
drop trigger if exists update_cart_updated_at on public.carts;
create trigger update_cart_updated_at
  before update on public.carts
  for each row
  execute function extensions.moddatetime(updated_at);

-- 2. Address "Search Path Mutable" warnings by setting explicit search_path on functions
-- This is a security best practice to prevent search path hijacking.

-- Functions from 010_business_logic_functions.sql
alter function public.checkout_cart(text, text, text, text) set search_path = public;
alter function public.notify_admin_new_order() set search_path = public;
alter function public.admin_manage_category(uuid, season_enum, int) set search_path = public;
alter function public.admin_manage_product(uuid, text, text, numeric, int, boolean, boolean, uuid, text[], text[]) set search_path = public;
alter function public.admin_manage_product_image(uuid, text, text, boolean, int) set search_path = public;
alter function public.admin_update_product_image(uuid, text, boolean, int) set search_path = public;
alter function public.admin_delete_product_image(uuid) set search_path = public;
alter function public.admin_toggle_active_status(text, uuid, boolean) set search_path = public;
alter function public.admin_update_order_status(uuid, text) set search_path = public;
alter function public.admin_verify_payment_slip(uuid, boolean) set search_path = public;

-- Functions from 011_admin_reporting_functions.sql
alter function public.get_all_orders_admin(int, int) set search_path = public;
alter function public.get_order_details_admin(uuid) set search_path = public;
alter function public.get_unverified_payment_slips() set search_path = public;
alter function public.get_business_metrics() set search_path = public;
alter function public.get_products_with_image_counts() set search_path = public;
alter function public.get_product_images(uuid) set search_path = public;

-- Functions from 012_security_policies_triggers.sql
alter function public.notify_customer_order_status() set search_path = public;
alter function public.notify_admin_payment() set search_path = public;

-- Functions from 015_admin_delete_functions.sql
alter function public.admin_delete_product(uuid) set search_path = public;
alter function public.admin_delete_category(uuid) set search_path = public;
alter function public.admin_delete_order(uuid) set search_path = public;
