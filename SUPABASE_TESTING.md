# Supabase Backend Testing

This document provides instructions for testing the e-commerce backend functions with your Supabase project.

## Your Supabase Project

- **URL**: `https://ffsldhalkpxhzrhoukzh.supabase.co`
- **Anon Key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZmc2xkaGFsa3B4aHpyaG91a3poIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNTY3OTYsImV4cCI6MjA4MjYzMjc5Nn0.hsifO6ucSx9HZ_Rfb7EAmXvJ_r-vRMWvMqPmlkJdIQo`

## Setup Instructions

1. **Install Dependencies** (if not already installed):
   ```bash
   npm install @supabase/supabase-js
   ```

2. **Run the Test Script**:
   ```bash
   node test_supabase.js
   ```

3. **Open the Demo Frontend**:
   Open [demo-frontend.html](file:///Users/sittminthar/Desktop/Kamisori%20Backend/demo-frontend.html) in your browser to test the frontend integration.

## Testing the Backend Schema

Since you have a free Supabase account, you'll need to manually add the database schema to your project:

1. Go to your Supabase dashboard
2. Navigate to the "SQL Editor" section
3. Run each of the migration files in order:

### Migration 1: Initial Schema
Run the content of [database/migrations/001_initial_schema.sql](file:///Users/sittminthar/Desktop/Kamisori%20Backend/database/migrations/001_initial_schema.sql) in the SQL Editor

### Migration 2: Order Status Triggers
Run the content of [database/migrations/002_order_status_trigger.sql](file:///Users/sittminthar/Desktop/Kamisori%20Backend/database/migrations/002_order_status_trigger.sql) in the SQL Editor

### Migration 3: Admin CRUD Functions
Run the content of [database/migrations/003_admin_crud_functions.sql](file:///Users/sittminthar/Desktop/Kamisori%20Backend/database/migrations/003_admin_crud_functions.sql) in the SQL Editor

## Testing the Functions

### 1. Public Functions (Testable without admin access)
- Product and category queries
- Cart operations (require authentication)
- Checkout function (requires authentication)

### 2. Admin Functions (Require admin user)
- `get_business_metrics()`
- `get_all_orders_admin()`
- `admin_update_order_status()`
- `admin_verify_payment_slip()`
- `admin_manage_product()`
- `admin_manage_category()`

## Creating an Admin User

To test admin functions, you need to:

1. Create a user account through the authentication system
2. Add the user to the `user_roles` table with the `admin` role:

```sql
INSERT INTO public.user_roles (user_id, role) 
VALUES ('your-user-uuid-here', 'admin');
```

## Storage Configuration

In your Supabase dashboard, configure the storage buckets:

1. Go to the "Storage" section
2. Create a bucket named `product-images` with public read access
3. Create a bucket named `payment-slips` with private access

## Edge Functions

For a complete implementation, you would also need to deploy the Edge Functions:

1. `notify-admin` - For payment slip notifications
2. `notify-customer` - For order status updates

However, this requires the Supabase CLI and is optional for basic testing.

## Demo Frontend Features

The [demo-frontend.html](file:///Users/sittminthar/Desktop/Kamisori%20Backend/demo-frontend.html) file includes:

- Product catalog with category filtering
- Shopping cart functionality
- Checkout process
- Admin dashboard (visible only to admin users)
- Order management
- Payment slip verification

## Troubleshooting

### Common Issues

1. **Function not found**: Make sure you've run all migration scripts
2. **Permission denied**: Check that RLS policies are properly configured
3. **Storage access errors**: Verify bucket policies match the requirements

### Verifying Setup

Run the test script to verify all functions are working:
```bash
node test_supabase.js
```

## Security Notes

- All RLS policies should be enabled for proper security
- Admin functions will only work for users with the `admin` role
- Authentication is required for cart and order operations
- Prices are calculated server-side and cannot be manipulated by the frontend

The backend is designed to be secure and easy to use, with all complex business logic handled server-side.