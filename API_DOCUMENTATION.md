# API Documentation for Frontend Developers

This document provides detailed information about the API endpoints available in the e-commerce backend system, including how to call each endpoint and what data to expect.

## Authentication

The system uses Supabase Auth for user authentication. Here are the main authentication functions:

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient('your-supabase-url', 'your-anon-key')

// Sign up a new user
const { user, error } = await supabase.auth.signUp({
  email: 'email@example.com',
  password: 'user-password'
})

// Sign in an existing user
const { user, error } = await supabase.auth.signInWithPassword({
  email: 'email@example.com',
  password: 'user-password'
})

// Sign out the current user
await supabase.auth.signOut()
```

## User Roles

User roles are stored in the `user_roles` table. A user can be either an `admin` or `customer`. When a new user signs up, they are automatically assigned the `customer` role.

```javascript
// Assign role to new user (this would be in a Supabase Auth hook)
const { error } = await supabase
  .from('user_roles')
  .insert([
    { user_id: userId, role: 'customer' }
  ])
```

## Product Management

### Get All Active Products

```javascript
const { data: products, error } = await supabase
  .from('products')
  .select('*')
  .eq('is_active', true)
```

### Get Products by Category

```javascript
const { data: products, error } = await supabase
  .from('products')
  .select('*')
  .eq('is_active', true)
  .eq('category_id', categoryId)
```

### Get All Active Product Categories

```javascript
const { data: categories, error } = await supabase
  .from('product_category_labels')
  .select('*')
  .eq('is_active', true)
```

## Cart Management

### Get User's Cart Items

```javascript
const { data: cartItems, error } = await supabase
  .from('cart_items')
  .select(`
    id,
    quantity,
    products!inner (
      id,
      name,
      price,
      description,
      stock
    )
  `)
  .eq('carts.user_id', supabase.auth.currentSession?.user.id)
```

### Add Item to Cart

```javascript
// First get or create user's cart
let { data: cart, error } = await supabase
  .from('carts')
  .select('id')
  .eq('user_id', supabase.auth.currentSession?.user.id)
  .single();

if (error) {
  // Create cart if it doesn't exist
  const { data, error } = await supabase
    .from('carts')
    .insert([{ user_id: supabase.auth.currentSession?.user.id }])
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
  }])
```

### Update Cart Item Quantity

```javascript
const { error } = await supabase
  .from('cart_items')
  .update({ quantity: newQuantity })
  .eq('id', cartItemId)
```

### Remove Item from Cart

```javascript
const { error } = await supabase
  .from('cart_items')
  .delete()
  .eq('id', cartItemId)
```

### Get Cart Total

```javascript
const { data: cartTotal, error } = await supabase
  .from('cart_totals')
  .select('total_amount')
  .eq('user_id', supabase.auth.currentSession?.user.id)
  .single()
```

## Checkout Process

### Process Checkout

```javascript
// This RPC function creates an order from the user's cart
const { data: orderId, error } = await supabase.rpc('checkout_cart', {
  p_payment_method: 'kbz_pay' // or 'cod'
})
```

## Orders

### Get User's Orders

```javascript
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
  .eq('user_id', supabase.auth.currentSession?.user.id)
  .order('created_at', { ascending: false })
```

## Delivery Address Management

### Add Delivery Address

```javascript
const { error } = await supabase
  .from('delivery_addresses')
  .insert([{
    order_id: orderId,
    full_name: 'Customer Name',
    phone: 'Customer Phone',
    address: 'Delivery Address'
  }])
```

### Update Delivery Address

```javascript
const { error } = await supabase
  .from('delivery_addresses')
  .update({
    full_name: 'Updated Name',
    phone: 'Updated Phone',
    address: 'Updated Address'
  })
  .eq('id', addressId)
  .eq('order.user_id', supabase.auth.currentSession?.user.id)
```

### Delete Delivery Address

```javascript
const { error } = await supabase
  .from('delivery_addresses')
  .delete()
  .eq('id', addressId)
  .eq('order.user_id', supabase.auth.currentSession?.user.id)
```

### Get Specific Order

```javascript
const { data: order, error } = await supabase
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
        name,
        description
      )
    ),
    delivery_addresses (
      full_name,
      phone,
      address
    )
  `)
  .eq('id', orderId)
  .eq('user_id', supabase.auth.currentSession?.user.id)
  .single()
```

## Payment

### Process Checkout

```javascript
// This RPC function creates an order from the user's cart
const { data: orderId, error } = await supabase.rpc('checkout_cart', {
  p_payment_method: 'kbz_pay' // or 'cod'
})
```

### Select Payment Method

The system supports two payment methods:

1. **Cash on Delivery (COD)**: 
   - Payment is made when the customer receives the order
   - Order status starts as `pending_confirmation`
   - Admin confirms the order without needing payment verification

2. **KBZ Pay**:
   - Customer pays via KBZ mobile payment app
   - Order status starts as `pending_payment`
   - Customer needs to upload a payment slip after making the payment
   - Admin verifies the payment slip before confirming the order

### Upload Payment Slip for KBZ Pay

```javascript
// First upload the image to Supabase Storage
const { data, error } = await supabase
  .storage
  .from('payment-slips')
  .upload(`receipt_${orderId}_${Date.now()}`, file, {
    cacheControl: '3600',
    upsert: false
  })

// Then save the URL to the payment_slips table
if (!error) {
  const publicUrl = supabase
    .storage
    .from('payment-slips')
    .getPublicUrl(data.path)
  
  const { error } = await supabase
    .from('payment_slips')
    .insert([{
      order_id: orderId,
      image_url: publicUrl.data.publicUrl
    }])
}
```

### KBZ Pay QR Code Generation

When a customer selects KBZ Pay as their payment method, the system generates a QR code containing:

- The order ID
- The total amount to pay
- A reference to KBZ Pay system

```javascript
// Example QR code data format
const qrCodeData = `KBZPAY:${orderId}:${totalAmount}`;
```

## Admin Functions

The following functions are only available to users with the `admin` role.

### Get All Orders (Admin Only)

```javascript
// Get paginated list of all orders
const { data: orders, error } = await supabase.rpc('get_all_orders_admin', {
  page_offset: 0,    // Page number (0-indexed)
  page_limit: 50     // Number of orders per page
})
```

### Get Order Details (Admin Only)

```javascript
// Get detailed information about a specific order
const { data: orderDetails, error } = await supabase.rpc('get_order_details_admin', {
  order_uuid: orderId
})
```

### Notification System

When customers place an order or upload payment slips, the system automatically notifies the admin via email using Gmail SMTP:

1. **New Order Notification**: Triggered when a customer completes checkout
2. **Payment Slip Notification**: Triggered when a customer uploads a payment slip for KBZ Pay orders

Both notifications include complete order details, customer information, and product list.

### Update Order Status (Admin Only)

```javascript
// Update the status of an order
const { error } = await supabase.rpc('admin_update_order_status', {
  order_uuid: orderId,
  new_status: 'shipped'  // Options: pending_payment, pending_confirmation, paid, confirmed, shipped, delivered, cancelled
})
```

### Verify Payment Slip (Admin Only)

```javascript
// Mark a payment slip as verified
const { error } = await supabase.rpc('admin_verify_payment_slip', {
  slip_uuid: slipId,
  verified_status: true  // Set to false to unverify
})
```

### Manage Product (Admin Only)

```javascript
// Create a new product
const { data: productId, error } = await supabase.rpc('admin_manage_product', {
  product_name: 'New Product',
  product_description: 'Product description',
  product_price: 29.99,
  product_stock: 100,
  product_is_preorder: false,
  product_is_active: true,
  category_uuid: categoryId
})

// Update an existing product
const { data: updatedId, error } = await supabase.rpc('admin_manage_product', {
  product_uuid: existingProductId,
  product_name: 'Updated Product Name',
  product_description: 'Updated description',
  product_price: 39.99,
  product_stock: 50,
  product_is_preorder: false,
  product_is_active: true,
  category_uuid: categoryId
})
```

### Manage Category (Admin Only)

```javascript
// Create a new category
const { data: categoryId, error } = await supabase.rpc('admin_manage_category', {
  category_season: 'summer',  // Options: summer, fall, winter
  category_year: 2025
})

// Update an existing category
const { data: updatedId, error } = await supabase.rpc('admin_manage_category', {
  category_uuid: existingCategoryId,
  category_season: 'winter',
  category_year: 2026
})
```

### Toggle Active Status (Admin Only)

```javascript
// Activate/deactivate a product
const { error } = await supabase.rpc('admin_toggle_active_status', {
  table_name: 'products',
  record_uuid: productId,
  active_status: false  // Set to true to activate
})

// Activate/deactivate a category
const { error } = await supabase.rpc('admin_toggle_active_status', {
  table_name: 'product_categories',
  record_uuid: categoryId,
  active_status: false  // Set to true to activate
})
```

### Get Unverified Payment Slips (Admin Only)

```javascript
// Get all payment slips that need verification
const { data: unverifiedSlips, error } = await supabase.rpc('get_unverified_payment_slips')
```

### Get Business Metrics (Admin Only)

```javascript
// Get overall business metrics
const { data: metrics, error } = await supabase.rpc('get_business_metrics')
```

## Storage Configuration

### Product Images (Public Read / Admin Write)

```javascript
// Upload product image (admin only)
const { data, error } = await supabase
  .storage
  .from('product-images')
  .upload(`product_${productId}_${Date.now()}`, file, {
    cacheControl: '3600',
    upsert: false
  })

// Get public URL for product image
const { data } = supabase
  .storage
  .from('product-images')
  .getPublicUrl(imagePath)
```

### Payment Slips (Private / Admin Read)

```javascript
// Upload payment slip (customer)
const { data, error } = await supabase
  .storage
  .from('payment-slips')
  .upload(`receipt_${orderId}_${Date.now()}`, file, {
    cacheControl: '3600',
    upsert: false
  })

// Get payment slip URL (admin only)
const { data } = supabase
  .storage
  .from('payment-slips')
  .getPublicUrl(imagePath)
```

## Order Status Lifecycle

Orders can have the following statuses:

- `pending_payment`: KBZ Pay waiting for admin verification
- `pending_confirmation`: COD waiting for admin confirmation
- `paid`: Payment verified
- `confirmed`: Admin approved
- `shipped`: Sent to customer
- `delivered`: Completed
- `cancelled`: Cancelled by admin or customer

## Important Notes

1. **Security**: All sensitive operations are protected by Row Level Security (RLS). Only admins can manage products, view all orders, and update order statuses.

2. **Price Protection**: Prices are never sent from the frontend. All pricing calculations happen on the server side through views and functions.

3. **Cart to Order**: When a user checks out, the cart items are converted to order items with locked prices. The original cart is emptied.

4. **Stock Management**: Stock is automatically reduced when an order is placed, except for preorder items.

5. **Notifications**: When a payment slip is uploaded, an automatic notification is sent to the admin via an Edge Function.

## Error Handling

Always check for errors in your API calls:

```javascript
const { data, error } = await supabase.from('table').select('*')

if (error) {
  console.error('Error:', error.message)
  // Handle error appropriately
} else {
  // Process data
}