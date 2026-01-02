# Local Clothing Brand E-Commerce Backend Setup Guide

This guide will help you set up the complete e-commerce backend system using Supabase.

## Prerequisites

- Node.js (v14 or higher)
- npm or yarn
- A Supabase account
- Git

## Step 1: Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) and sign up for an account
2. Create a new project
3. Note down your:
   - Project URL
   - Anonymous/Service Role Key

## Step 2: Database Setup

### Run the Database Migrations

Execute the SQL in the following order:

1. Run [001_initial_schema.sql](file:///Users/sittminthar/Desktop/Kamisori%20Backend/database/migrations/001_initial_schema.sql)
2. Run [002_order_status_trigger.sql](file:///Users/sittminthar/Desktop/Kamisori%20Backend/database/migrations/002_order_status_trigger.sql)
... (Run all migrations in order) ...

> [!IMPORTANT]
> **Update Notification Triggers**: 
> Before running migrations `012` and `014`, open them and replace:
> - `YOUR_PROJECT_REF` with your Supabase Project Reference.
> - `YOUR_SUPABASE_ANON_KEY` with your project's Anonymous Key.
> 
> This is necessary for the database triggers to securely call your Edge Functions.

You can run these migrations in the Supabase SQL Editor or using the Supabase CLI.

### Enable Row Level Security

The migrations already include RLS policies, but make sure RLS is enabled on your tables.

## Step 3: Configure Storage Buckets

1. Go to Storage in your Supabase dashboard
2. Create two buckets:
   - `product-images` - Set to public read, admin write
   - `payment-slips` - Set to private, admin read

## Step 4: Set up Auth & Google OAuth

1. In your Supabase dashboard, go to **Authentication** -> **Providers**.
2. **Setup Google OAuth**:
   - Enable the Google provider.
   - Enter your **Google Client ID** and **Client Secret** (obtained from [Google Cloud Console](https://console.cloud.google.com/)).
   - Add the Supabase Redirect URI to your Google Cloud Console "Authorized redirect URIs".
3. In Authentication -> **URL Configuration**, set your "Site URL" to your frontend URL (e.g., `http://localhost:3000` or your domain).

## Step 5: Configure Environment Variables

For the Edge Functions, you'll need to set the following environment variables in your Supabase project:

- `SUPABASE_URL` - Your Supabase project URL.
- `SUPABASE_SERVICE_ROLE_KEY` - Your service role key (for database access).
- `ADMIN_EMAIL` - The Gmail address where **you** want to receive order notifications.
- `ADMIN_SECRET_TOKEN` - A secret string of your choice to protect the email "Status Update" buttons.
- `SMTP_USER` - A dedicated Gmail address to act as the "Postman" (System Sender).
- `SMTP_PASSWORD` - The 16-character **Google App Password** for the `SMTP_USER` account.

> [!TIP]
> **How to get a Gmail App Password:**
> 1. Enable **2-Step Verification** in your Google Account.
> 2. Go to [App Passwords](https://myaccount.google.com/apppasswords).
> 3. Create a new "Mail" password for "Kamisori Backend".

## Step 6: Deploy Edge Functions

1. Install the Supabase CLI:
   ```bash
   brew install supabase/tap/supabase
   ```

2. Log in to your Supabase account:
   ```bash
   supabase login
   ```

3. Link your project:
   ```bash
   supabase link --project-ref <your-project-ref>
   ```

4. Deploy the functions:
   ```bash
   # Deploy core notification functions
   supabase functions deploy notify-admin
   supabase functions deploy notify-customer

   # IMPORTANT: Deploy the status update function without JWT verification
   # (This allows the buttons in the email to work directly)
   supabase functions deploy update-order-status --no-verify-jwt
   ```

## Step 7: Configure Database Webhooks

The triggers for notifications are already created in the migration files. The `notify_admin_payment` function will trigger when a payment slip is uploaded, and the `notify_customer_order_status` function will trigger when an order status is updated.

## Step 8: Create Initial Admin User

To create an initial admin user, you can run this SQL after a user has registered:

```sql
INSERT INTO public.user_roles (user_id, role) 
VALUES ('user-uuid-here', 'admin');
```

## Step 9: Frontend Integration

### Install Dependencies

```bash
npm install @supabase/supabase-js
```

### Initialize Supabase Client

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)
```

### Using the Helper Functions

You can use the helper functions provided in [utils/supabase-helpers.ts](file:///Users/sittminthar/Desktop/Kamisori%20Backend/utils/supabase-helpers.ts) to handle common operations.

## Step 10: Testing the System

### Test User Registration and Login

```javascript
// Sign up
const { user, error } = await supabase.auth.signUp({
  email: 'test@example.com',
  password: 'password123'
});

// Sign in
const { user, error } = await supabase.auth.signInWithPassword({
  email: 'test@example.com',
  password: 'password123'
});
```

### Test Product Operations

```javascript
// Get all active products
const { data: products, error } = await supabase
  .from('products')
  .select('*')
  .eq('is_active', true);
```

### Test Cart Operations

```javascript
// Add item to cart
await addToCart('product-uuid', 2);

// Get cart items
const cartItems = await getCartItems();

// Get cart total
const total = await getCartTotal();
```

### Test Checkout Process

```javascript
// Process checkout
const orderId = await processCheckout('kbz_pay'); // or 'cod'
```

## Troubleshooting

### Common Issues

1. **Row Level Security Errors**: Make sure all RLS policies are correctly set up
2. **Function Deployment Errors**: Check that environment variables are set correctly
3. **Storage Access Issues**: Verify bucket policies match the requirements

### Checking Database Logs

You can check the database logs in your Supabase dashboard under Database -> Logs to troubleshoot issues.

## Security Best Practices

1. **Never trust frontend prices**: All price calculations happen server-side
2. **Use RLS everywhere**: All tables have Row Level Security enabled
3. **Validate user roles**: Admin functions check for admin role
4. **Protect sensitive data**: Use proper access controls for payment information

## Next Steps

1. Implement the frontend application using the API documentation
2. Set up email service for actual notifications
3. Add additional security measures as needed
4. Perform load testing
5. Set up monitoring and alerting

## Dashboard-Friendly Deployment (Alternative to Terminal)

If you or your team prefer not to use the terminal for every update, you can set up **GitHub Actions**. This allows the functions to deploy automatically whenever you click a button on GitHub or push code.

### Option A: GitHub Actions (Automated)

1. Connect your repository to Supabase via the [Supabase Dashboard](https://supabase.com/dashboard/project/_/settings/integrations).
2. Add your `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_ID` as GitHub Secrets.
3. Use the `.github/workflows/deploy.yml` template to automate deployment.

### Option B: Managing Secrets via Dashboard

While the code itself needs to be deployed via CLI or GitHub, you can manage all **Secrets** (like Gmail passwords) manually without any terminal commands:

1. Go to your **Supabase Dashboard**.
2. Navigate to **Edge Functions** in the left sidebar.
3. Select the function (e.g., `notify-admin`).
4. Click on the **Settings** tab.
5. Under **Environment Variables**, you can add, edit, or delete `SMTP_USER`, `SMTP_PASSWORD`, etc.
6. Click **Save** to apply changes instantly.

### Option C: Manual Testing via Dashboard

You can test your functions directly from the dashboard:
1. Go to **Edge Functions** -> **notify-admin**.
2. Click the **Test** tab.
3. Enter your JSON payload (e.g., `{"notification_type": "test_ping"}`).
4. Click **Run**.