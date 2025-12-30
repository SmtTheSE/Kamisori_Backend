# Local Clothing Brand E-Commerce Backend

This is a secure, scalable e-commerce backend built with Supabase for a local clothing brand. It implements industry-standard security practices and follows e-commerce best practices.

## Architecture Overview

- **Frontend never sends prices** - All pricing is calculated server-side
- **Cart = calculation layer** - Cart calculates total based on current prices
- **Order = immutable snapshot** - Prices are locked at checkout
- **RLS enforced at database level** - Row Level Security on all tables
- **Manual KBZ Pay verification** - Payment verification requires admin approval

## Core Components

1. User authentication with role-based access
2. Season/year product categorization
3. Shopping cart with server-side calculation
4. Immutable order snapshots
5. Payment slip verification system
6. Email notifications via Edge Functions
7. **NEW: Comprehensive admin CRUD functions**
8. Secure admin panel

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
  unique (cart_id, product_id)
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
  price numeric(10,2) not null
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
  p_payment_method text
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

## Email Verification (Trigger)

```sql
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

### Product Management

- `GET /products` - Get all active products
- `GET /products?category=categoryId` - Get products by category
- `GET /product_categories` - Get all active product categories

### Cart Management

- `GET /cart` - Get user's cart
- `POST /cart/items` - Add item to cart
- `PUT /cart/items/{id}` - Update cart item quantity
- `DELETE /cart/items/{id}` - Remove item from cart
- `GET /cart/total` - Get cart total

### Checkout

- `POST /checkout` - Process checkout (with payment method)

### Orders

- `GET /orders` - Get user's orders
- `GET /orders/{id}` - Get specific order details

### Payment

- `POST /payment_slips` - Upload payment slip for KBZ Pay
- `GET /payment_slips/{orderId}` - Get payment slip for order (admin only)

### Admin Functions

- `RPC get_all_orders_admin` - Get all orders with customer details (admin only), including delivery address and product variants
- `RPC get_order_details_admin` - Get detailed order information (admin only)
- `RPC admin_update_order_status` - Update order status (admin only)
- `RPC admin_verify_payment_slip` - Verify payment slip (admin only)
- `RPC admin_manage_product` - Create/update products (admin only)
- `RPC admin_manage_category` - Create/update categories (admin only)
- `RPC admin_toggle_active_status` - Activate/deactivate items (admin only)
- `RPC get_unverified_payment_slips` - Get unverified payment slips (admin only)
- `RPC get_business_metrics` - Get business metrics (admin only)

## Frontend Integration Guide

### Getting Products

```javascript
// Get all active products
const { data: products, error } = await supabase
  .from('products')
  .select('*')
  .eq('is_active', true);

// Get products by category
const { data: products, error } = await supabase
  .from('products')
  .select('*')
  .eq('is_active', true)
  .eq('category_id', categoryId);
```

### Managing Cart

```javascript
// Add item to cart
async function addToCart(productId, quantity) {
  // First get user's cart or create one
  let { data: cart, error } = await supabase
    .from('carts')
    .select('id')
    .eq('user_id', supabase.auth.user().id)
    .single();
  
  if (!cart) {
    const { data, error } = await supabase
      .from('carts')
      .insert([{ user_id: supabase.auth.user().id }])
      .select('id')
      .single();
    cart = data;
  }
  
  // Add item to cart
  const { error } = await supabase
    .from('cart_items')
    .insert([{ 
      cart_id: cart.id, 
      product_id: productId, 
      quantity: quantity 
    }]);
}

// Get cart items with product details
const { data: cartItems, error } = await supabase
  .from('cart_items')
  .select(`
    id,
    quantity,
    products!inner (
      id,
      name,
      price,
      description
    )
  `)
  .eq('carts.user_id', supabase.auth.user().id);
```

### Processing Checkout

```javascript
// Process checkout
const orderId = await supabase.rpc('checkout_cart', {
  p_payment_method: 'kbz_pay' // or 'cod'
});
```

### Getting Cart Total

```javascript
// Get cart total
const { data: cartTotal, error } = await supabase
  .from('cart_totals')
  .select('total_amount')
  .eq('user_id', supabase.auth.user().id)
  .single();
```

### Getting User Orders

```javascript
// Get user's orders
const { data: orders, error } = await supabase
  .from('orders')
  .select(`
    id,
    total_amount,
    payment_method,
    status,
    created_at,
    order_items (
      quantity,
      price,
      products (
        name
      )
    ),
    delivery_addresses (
      full_name,
      phone,
      address
    )
  `)
  .eq('user_id', supabase.auth.user().id)
  .order('created_at', { ascending: false });
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
