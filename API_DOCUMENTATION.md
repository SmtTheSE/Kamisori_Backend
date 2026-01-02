# Exhaustive API Documentation for Frontend Developers

This document provides a complete reference for all API endpoints, database tables, and RPC functions in the Kamisori Backend.

## Authentication (Supabase Auth)

The system uses standard Supabase Auth. Use the `@supabase/supabase-js` client.

- `signUp(email, password)`: Register new customers.
- `signInWithPassword(email, password)`: Login for existing users.
- `signOut()`: Clear session.

---

## Database Schema (Public)

### products
- `id` (uuid, PK)
- `name` (text)
- `description` (text)
- `price` (numeric)
- `stock` (int)
- `is_preorder` (boolean)
- `is_active` (boolean)
- `category_id` (uuid, FK)
- `sizes` (text[]) - Array of available sizes (e.g. `['S', 'M', 'L']`)
- `colors` (text[]) - Array of available colors (e.g. `['Black', 'White']`)

### product_images
- `id` (uuid, PK)
- `product_id` (uuid, FK)
- `image_url` (text)
- `alt_text` (text)
- `is_primary` (boolean)
- `sort_order` (int)

### carts / cart_items
- `cart_items` table:
  - `id` (uuid, PK)
  - `cart_id` (uuid, FK)
  - `product_id` (uuid, FK)
  - `quantity` (int)
  - `size` (text, nullable)
  - `color` (text, nullable)

### orders / order_items
- `orders` table:
  - `id` (uuid, PK)
  - `user_id` (uuid, FK)
  - `total_amount` (numeric)
  - `payment_method` (text: 'kbz_pay' | 'cod')
  - `status` (text)
- `order_items` table:
  - `price` (numeric) - Locked at time of purchase
  - `size` (text, nullable)
  - `color` (text, nullable)

---

## RPC Functions (Primary API)

### 1. `checkout_cart` (Customer)
- **Params**:
  - `p_payment_method`: 'kbz_pay' | 'cod'
  - `p_full_name`: string
  - `p_phone`: string
  - `p_address`: string
- **Returns**: `uuid` (Order ID)
- **Logic**: Converts cart to order, reduces stock, clears cart, saves delivery address.

### 2. `get_all_orders_admin` (Admin Only)
- **Params**: `page_offset` (int), `page_limit` (int)
- **Returns**: Table with customer email, full name, total, status, delivery address, and order items.

### 3. `admin_update_order_status` (Admin Only)
- **Params**: `order_uuid`, `new_status`
- **Statuses**: `pending_payment`, `pending_confirmation`, `paid`, `confirmed`, `shipped`, `delivered`, `cancelled`.

### 4. `admin_verify_payment_slip` (Admin Only)
- **Params**: `slip_uuid`, `verified_status` (boolean)
- **Logic**: If verified, automatically updates order status to `paid`.

### 5. `admin_manage_product` (Admin Only)
- **Params**: Supports all product fields including `product_uuid` (for updates) and `product_sizes`/`product_colors`.

### 6. `admin_delete_product` (Admin Only)
- **Params**: `product_uuid`
- **Logic**: Safely deletes product and its images.

### 7. `admin_delete_category` (Admin Only)
- **Params**: `category_uuid`
- **Logic**: Deletes category and all related products (cascade).

### 8. `admin_delete_order` (Admin Only)
- **Params**: `order_uuid`
- **Logic**: Removes order and all linked slips/notifications.

### 9. `admin_cleanup_old_orders` (Admin Only)
- **Params**: `older_than_date` (timestamptz)
- **Logic**: Bulk deletes old orders and related data to save space.

---

## Storage Buckets

1. `product-images`: Public read, Admin write.
2. `payment-slips`: Admin read/write, Customers can upload only.

---

## RLS (Row Level Security)

- Customers can only see their own carts and orders.
- Active products and categories are public.
- Admin functions require the `admin` role in the `user_roles` table.