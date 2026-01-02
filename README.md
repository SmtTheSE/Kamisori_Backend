# Local Clothing Brand E-Commerce Backend

This is a secure, scalable e-commerce backend built with Supabase for a local clothing brand. It implements industry-standard security practices and follows e-commerce best practices.

## Architecture Overview

- **Frontend never sends prices** - All pricing is calculated server-side
- **Cart = calculation layer** - Cart calculates total based on current prices
- **Order = immutable snapshot** - Prices are locked at checkout
- **RLS enforced at database level** - Row Level Security on all tables
- **Manual KBZ Pay verification** - Payment verification requires admin approval

## Core Components

1. **Google OAuth** authentication for reliable customer identity
2. Season/year product categorization
3. Shopping cart with server-side calculation
4. Immutable order snapshots
5. Payment slip verification system
6. Professional email notifications (Gmail SMTP):
   - **Admin**: "Forwarded" from buyer via `Reply-To`.
   - **Customer**: Formal updates from "The Kamisori Team".
   - **Quick Actions**: One-click status updates directly from the admin email.
7. Secure admin panel for centralized management

## Tech Stack

- PostgreSQL (Supabase)
- Supabase Auth
- Supabase Storage
- Supabase Edge Functions
- Row Level Security (RLS)

## Database Schema

### User Roles

```sql
create table public.user_roles (
  user_id uuid references auth.users(id) on delete cascade,
  role text check (role in ('admin', 'customer')) not null,
  primary key (user_id)
);
```

### Product Categories (Season + Year)

#### Season Enum
```sql
create type season_enum as enum ('summer', 'fall', 'winter');
```

#### Categories Table
```sql
create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  season season_enum not null,
  year int not null check (year >= 2024),
  is_active boolean default true,
  is_featured boolean default false,
  created_at timestamptz default now(),
  unique (season, year)
);
```

#### Category Label View
```sql
create view public.product_category_labels as
select
  id,
  initcap(season) || ' ' || year as label,
  season,
  year,
  is_active
from public.product_categories;
```

### Products

```sql
create table public.products (
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
```

### Product Images

```sql
create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  image_url text not null,
  alt_text text,
  is_primary boolean default false,
  sort_order int default 0,
  created_at timestamptz default now()
);
```

### Cart System (Price Calculation)

#### Cart
```sql
create table public.carts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  updated_at timestamptz default now()
);

create trigger update_cart_updated_at
before update on public.carts
for each row
execute procedure moddatetime(updated_at);
```

#### Cart Items
```sql
create table public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid references public.carts(id) on delete cascade,
  product_id uuid references public.products(id),
  quantity int not null check (quantity > 0),
  size text default null,
  color text default null,
  unique (cart_id, product_id, coalesce(size, ''), coalesce(color, ''))
);
```

#### Cart Totals (Read-Only)
```sql
create view public.cart_totals as
select
  c.user_id,
  sum(ci.quantity * p.price) as total_amount
from public.carts c
join public.cart_items ci on ci.cart_id = c.id
join public.products p on p.id = ci.product_id
where p.is_active = true
group by c.user_id;
```

### Orders (Immutable Snapshot)

```sql
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  total_amount numeric(10,2) not null,
  payment_method text check (payment_method in ('kbz_pay','cod')) not null,
  status text not null,
  created_at timestamptz default now()
);
```

### Order Items (Price Locked)

```sql
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  quantity int not null,
  price numeric(10,2) not null,
  size text default null,
  color text default null
);
```

### Delivery Address Snapshot

```sql
create table public.delivery_addresses (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  full_name text not null,
  phone text not null,
  address text not null,
  created_at timestamptz default now()
);
```

### KBZ Pay Payment Slips

```sql
create table public.payment_slips (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  image_url text not null,
  verified boolean default false,
  uploaded_at timestamptz default now(),
  verified_at timestamptz
);
```

## Database Functions

### Admin Helper Function

```sql
create or replace function is_admin()
returns boolean language sql stable as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
    and role = 'admin'
  );
$$;
```

### Checkout Function (Critical)

```sql
create or replace function public.checkout_cart(
  p_payment_method text,
  p_full_name text,
  p_phone text,
  p_address text
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
```

### Admin: Delete and Cleanup Functions

- `admin_delete_product(product_uuid)` - Safely delete product and its images.
- `admin_delete_category(category_uuid)` - Delete category and all its products (cascade).
- `admin_delete_order(order_uuid)` - Completely remove an order and all related notifications/slips.
- `admin_cleanup_old_orders(older_than_date)` - Bulk delete orders older than a specific date for storage management.
- `admin_count_old_orders(older_than_date)` - Preview how many orders will be affected by cleanup.

## NEW: Admin CRUD Functions

The system includes comprehensive admin functions for managing the e-commerce platform:

### Order Management Functions

- `get_all_orders_admin(page_offset, page_limit)` - Retrieve paginated list of all orders with customer details
- `get_order_details_admin(order_uuid)` - Get detailed information about a specific order
- `admin_update_order_status(order_uuid, new_status)` - Update the status of an order
- `admin_verify_payment_slip(slip_uuid, verified_status)` - Verify or unverify a payment slip

### Product Management Functions

- `admin_manage_product(...)` - Create or update a product with all its details
- `admin_manage_category(...)` - Create or update a product category
- `admin_toggle_active_status(table_name, record_uuid, active_status)` - Activate or deactivate products/categories

### Business Intelligence Functions

- `get_unverified_payment_slips()` - Get all payment slips requiring verification
- `get_business_metrics()` - Retrieve key business metrics

## Row Level Security (RLS)

### Carts
```sql
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
```

### Orders
```sql
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
```

### Categories & Products
```sql
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
```

## Storage Buckets

| Bucket | Access |
|--------|--------|
| product-images | Public read / Admin write |
| payment-slips | Private / Admin read |

## Email Notifications (Triggers)

```sql
-- Trigger for new orders
create or replace function notify_admin_new_order()
returns trigger as $$
begin
  perform net.http_post(
    url := 'https://PROJECT.functions.supabase.co/notify-admin',
    body := json_build_object(
      'order_id', NEW.id,
      'notification_type', 'new_order'
    )::text
  );
  return NEW;
end;
$$ language plpgsql;

create trigger new_order_notification
  after insert on public.orders
  for each row execute function notify_admin_new_order();

-- Trigger for payment slip uploads
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

## Order Status Lifecycle

| Status | Meaning |
|--------|---------|
| pending_payment | KBZ Pay waiting |
| pending_confirmation | COD waiting |
| paid | Payment verified |
| confirmed | Admin approved |
| shipped | Sent |
| delivered | Completed |
| cancelled | Cancelled |

## API Endpoints for Frontend

### Authentication

- `auth.signUp()` - User registration
- `auth.signIn()` - User login
- `auth.signOut()` - User logout

### Product & Category Discovery (Public)

- `GET /products` - Get all active products
- `GET /products?category=categoryId` - Get products by category
- `GET /product_categories` - Get all active product categories

### Shopping Cart (Customer)

- `GET /cart` - Get user's cart (calculates total server-side)
- `POST /cart/items` - Add item to cart (with size/color support)
- `PUT /cart/items/{id}` - Update quantity
- `DELETE /cart/items/{id}` - Remove item
- `GET /cart/total` - Get current cart total amount

### Checkout & Orders (Customer)

- `POST /checkout` - Process checkout (creates immutable order snapshot)
- `GET /orders` - Get history of user's orders
- `GET /orders/{id}` - Get detailed order info and status
- `POST /payment_slips` - Upload KBZ Pay verification slip

### Admin Panel (RPC Functions)

All admin functions require the `admin` role and are protected by RLS and manual role checks.

####  Product Management (CRUD)
- `admin_manage_product(...)` - Comprehensive function to **Create or Update** products (names, prices, stock, variants, categories).
- `admin_delete_product(product_uuid)` - Safely **Delete** a product and its associated images.
- `admin_toggle_active_status('products', uuid, bool)` - Quickly activate/deactivate products.

####  Category Management (CRUD)
- `admin_manage_category(...)` - **Create or Update** seasonal categories.
- `admin_delete_category(category_uuid)` - **Delete** category and all its products (cascade).
- `admin_toggle_active_status('product_categories', uuid, bool)` - Quickly activate/deactivate categories.

####  Order & Payment Management
- `get_all_orders_admin(offset, limit)` - Full paginated list of all orders with customer details.
- `get_order_details_admin(order_uuid)` - Deep dive into a single order's items and address.
- `admin_update_order_status(order_uuid, status)` - Move orders through the lifecycle (paid, confirmed, shipped, etc).
- `get_unverified_payment_slips()` - List of KBZ Pay slips awaiting manual approval.
- `admin_verify_payment_slip(slip_uuid, bool)` - Mark a payment as verified (automatically updates order to `paid`).
- `admin_delete_order(order_uuid)` - Completely remove an order and its logs.

####  Reporting & Maintenance
- `get_business_metrics()` - Quick snapshot of total revenue, orders, and customer counts.
- `admin_cleanup_old_orders(date)` - Bulk delete legacy orders to manage database storage.
- `admin_count_old_orders(date)` - Preview tool for the cleanup process.

## React/TypeScript Integration Guide

This guide is for **Zwe Lin Naing** and **Thu Htet Naing** to integrate the backend with the React/TypeScript frontend.

### 1. Setup Supabase Client

```typescript
import { createClient } from '@supabase/supabase-js';

// Use environment variables for security
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
```

### 2. Product Integration (with Images and Variants)

When fetching products, you can include primary images and categories in a single call.

```typescript
export interface Product {
  id: string;
  name: string;
  price: number;
  stock: number;
  sizes: string[] | null;
  colors: string[] | null;
  product_images: { image_url: string; is_primary: boolean }[];
}

export async function fetchProducts(categoryId?: string) {
  let query = supabase
    .from('products')
    .select(`
      *,
      product_images (image_url, is_primary)
    `)
    .eq('is_active', true);

  if (categoryId) {
    query = query.eq('category_id', categoryId);
  }

  const { data, error } = await query;
  return { products: data as Product[], error };
}
```

### 3. Cart Management (with Variants)

When adding to cart, you **must** specify `size` and `color` if the product has them.

```typescript
export async function addToCart(productId: string, quantity: number, size?: string, color?: string) {
  // 1. Get or create cart ID (see utils/supabase-helpers.ts)
  const cartId = await getOrCreateCartId(); 

  const { error } = await supabase
    .from('cart_items')
    .insert([{ 
      cart_id: cartId, 
      product_id: productId, 
      quantity, 
      size: size || null, 
      color: color || null 
    }]);

  if (error && error.code === '23505') {
    // Unique violation: update existing item quantity instead
    // Implementation in utils/supabase-helpers.ts
  }
}
```

### 4. Checkout and Delivery

Checkout requires the delivery address upfront.

```typescript
export async function handleCheckout(paymentMethod: 'kbz_pay' | 'cod', addressData: any) {
  const { data: orderId, error } = await supabase.rpc('checkout_cart', {
    p_payment_method: paymentMethod,
    p_full_name: addressData.fullName,
    p_phone: addressData.phone,
    p_address: addressData.address
  });

  if (error) throw error;
  return orderId;
}
```

### 5. KBZ Pay Payment Flow

If `kbz_pay` is chosen:
1. Show the QR Code (generated using `KBZPAY:${orderId}:${totalAmount}`).
2. User uploads payment slip.

```typescript
export async function uploadSlip(orderId: string, file: File) {
  // 1. Upload to storage
  const filePath = `receipts/${orderId}_${Date.now()}`;
  const { data, error: uploadError } = await supabase.storage
    .from('payment-slips')
    .upload(filePath, file);

  if (uploadError) throw uploadError;

  // 2. Get public URL and save to DB
  const { data: { publicUrl } } = supabase.storage.from('payment-slips').getPublicUrl(data.path);

  const { error: dbError } = await supabase
    .from('payment_slips')
    .insert([{ order_id: orderId, image_url: publicUrl }]);

  if (dbError) throw dbError;
}
```

### 6. Admin Panel Hooks

Admins can use RPC functions for high-level tasks.

```typescript
// Update order status
await supabase.rpc('admin_update_order_status', {
  order_uuid: '...',
  new_status: 'paid' // paid, confirmed, shipped, etc.
});

// Verify payment
await adminVerifyPayment('slip-uuid', true);

// Delete product
await adminDeleteProduct('product-uuid');

// Delete category
await adminDeleteCategory('category-uuid');

// Delete order
await adminDeleteOrder('order-uuid');
```

## Security Considerations

- Never trust frontend prices - all prices are validated server-side
- RLS prevents unauthorized access to data
- Cart calculations happen server-side
- Order prices are locked at checkout
- Admin functions are protected by RLS
- Payment verification requires admin approval
- NEW: All admin functions include role validation

## NEW: KBZ Pay QR Code Integration

The system now includes comprehensive KBZ Pay integration with:

1. **QR Code Generation**: Dynamically generates QR codes for each order with payment details
2. **Payment Slip Upload**: Customers can upload payment verification slips
3. **Admin Verification**: Admins can verify payment slips before confirming orders
4. **Status Tracking**: Complete tracking of payment status from pending to confirmed

### Frontend Payment Flow

1. Customer selects "KBZ Pay" as payment method
2. System generates unique QR code containing order ID and amount
3. Customer scans QR code and makes payment via KBZ Pay app
4. Customer uploads payment slip to verify transaction
5. Admin verifies payment slip and updates order status
6. Order progresses through fulfillment workflow

### Key Features

- **Secure QR Generation**: Each QR code contains encrypted order information
- **Real-time Status Updates**: Payment status updates automatically
- **Verification Workflow**: Multiple verification steps for security
- **Admin Dashboard Integration**: Complete payment management in admin panel
- **Delivery Address Collection**: Integrated address collection for both payment methods
