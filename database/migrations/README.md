# Kamisori Backend - Database Migration Structure

This document explains the organized database migration structure for the Kamisori Backend project. This structure is designed to be clear and easy to understand for frontend developers and other team members.

## Migration Files Overview

### 001-008: Legacy Migration Files
These are the original migration files that were used to build the system. They are kept for historical reference but are replaced by the new organized structure.

### 009: Clean Schema Setup (`009_clean_schema_setup.sql`)
- Complete schema definition with all tables, enums, and base functions
- Clean organization of all database objects
- No business logic, only structure

### 010: Business Logic Functions (`010_business_logic_functions.sql`)
- All core business logic functions
- Checkout process
- Product management functions
- Order processing functions
- All functions marked as `security definer`

### 011: Admin and Reporting Functions (`011_admin_reporting_functions.sql`)
- Admin dashboard functions
- Reporting functions
- Order management functions for admin
- Business metrics functions

### 012: Security Policies and Triggers (`012_security_policies_triggers.sql`)
- All Row Level Security (RLS) policies
- Notification triggers
- Access control policies

### 013: Storage Policies (`013_storage_policies.sql`)
- Storage bucket policies
- Image and payment slip access controls

## Frontend Developer Guide

### Key Functions for Frontend Integration

#### Customer Functions
- `checkout_cart(payment_method)` - Process cart and create order
- Available payment methods: `'kbz_pay'` or `'cod'`

#### Admin Functions
- `get_all_orders_admin(page_offset, page_limit)` - Get orders for admin dashboard
- `get_order_details_admin(order_uuid)` - Get detailed order information
- `admin_update_order_status(order_uuid, new_status)` - Update order status
- `admin_verify_payment_slip(slip_uuid, verified_status)` - Verify payment slip
- `get_business_metrics()` - Get business metrics for dashboard
- `get_products_with_image_counts()` - Get products with image information
- `admin_manage_product(...)` - Create/update products
- `admin_manage_product_image(...)` - Manage product images
- `admin_toggle_active_status(table_name, record_uuid, active_status)` - Toggle active status

#### Order Status Options
- `'pending_payment'` - Awaiting payment confirmation
- `'pending_confirmation'` - Awaiting admin confirmation (for COD)
- `'paid'` - Payment confirmed
- `'confirmed'` - Order confirmed by admin
- `'shipped'` - Order shipped
- `'delivered'` - Order delivered
- `'cancelled'` - Order cancelled

## Migration Execution Order

When setting up a new environment, execute the migration files in this order:

1. `009_clean_schema_setup.sql`
2. `010_business_logic_functions.sql`
3. `011_admin_reporting_functions.sql`
4. `012_security_policies_triggers.sql`
5. `013_storage_policies.sql`

## Important Notes

- All admin functions require admin privileges and check using the `is_admin()` function
- All functions that modify data use proper error handling
- RLS (Row Level Security) is enabled for all tables with appropriate policies
- The system handles both COD (Cash on Delivery) and KBZ Pay payment methods
- Notification triggers are set up for both customer and admin notifications
- All customer data access is properly secured with RLS policies

## Database Structure Overview

- **Products**: Managed with categories, sizes, colors, and images
- **Orders**: Complete order management with status tracking
- **Carts**: Shopping cart functionality
- **Payments**: Support for multiple payment methods
- **Delivery**: Delivery address management
- **Notifications**: Customer and admin notifications
- **Storage**: Secure file storage for product images and payment slips