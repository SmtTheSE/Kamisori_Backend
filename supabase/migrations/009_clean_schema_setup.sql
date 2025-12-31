-- Kamisori Backend - Clean Schema Setup
-- This migration provides a complete, organized setup of the database schema
-- with all necessary tables, types, and base functions

-- Enable required extensions
create extension if not exists "uuid-ossp";
create extension if not exists "moddatetime";

-- Create season enum for product categories (Idempotent)
do $$ begin
  create type season_enum as enum ('summer', 'fall', 'winter', 'spring');
exception
  when duplicate_object then null;
end $$;


-- User roles table for access control
create table if not exists public.user_roles (
  user_id uuid references auth.users(id) on delete cascade,
  role text check (role in ('admin', 'customer')) not null,
  primary key (user_id)
);


-- Function to check if current user is admin
create or replace function is_admin()
returns boolean language sql stable as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
    and role = 'admin'
  );
$$;

-- Product categories table
create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  season season_enum not null,
  year int not null check (year >= 2024),
  is_active boolean default true,
  is_featured boolean default false,
  created_at timestamptz default now(),
  unique (season, year)
);


-- Product categories label view
create or replace view public.product_category_labels as
select
  id,
  initcap(season::text) || ' ' || year as label,
  season,
  year,
  is_active
from public.product_categories;


-- Products table
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  price numeric(10,2) not null,
  stock int,
  is_preorder boolean default false,
  is_active boolean default true,
  category_id uuid references public.product_categories(id),
  sizes text[] default null,
  colors text[] default null,
  created_at timestamptz default now()
);


-- Product images table
create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  image_url text not null,
  alt_text text,
  is_primary boolean default false,
  sort_order int default 0,
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
  size text default null,
  color text default null,
  unique (cart_id, product_id, coalesce(size, ''), coalesce(color, ''))
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
create table if not exists public.orders (
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
  price numeric(10,2) not null,
  size text default null,
  color text default null
);

-- Delivery addresses table
create table if not exists public.delivery_addresses (
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

-- Notifications tables
create table public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  notification_type text not null,
  message text not null,
  recipient_email text not null,
  sent_at timestamptz default now()
);

create table if not exists public.payment_notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  notification_type text not null,
  message text not null,
  sent_at timestamptz default now()
);


-- Enable Row Level Security on all tables
alter table public.user_roles enable row level security;
alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.delivery_addresses enable row level security;
alter table public.payment_slips enable row level security;
alter table public.customer_notifications enable row level security;
alter table public.payment_notifications enable row level security;