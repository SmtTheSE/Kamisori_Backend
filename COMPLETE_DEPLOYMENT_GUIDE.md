# 🚀 Kamisori Backend: Complete Deployment Guide

This guide is for developers who want to set up the **Kamisori Backend** from scratch. Even if you have never used the Supabase CLI, this guide will walk you through every click and command.

---

## 📋 Prerequisites
- **Google Account** (to handle emails and login)
- **Node.js** [Download here](https://nodejs.org/)
- **Supabase Account** [Sign up here](https://supabase.com/)

---

## 1️⃣ Phase One: The Supabase Dashboard
No terminal needed for this part.

### 1.1 Create the Project
1. Log in to your [Supabase Dashboard](https://supabase.com/dashboard).
2. Click **New Project** and choose an organization.
3. Give it a name (e.g., `Kamisori-Backend`) and a secure password.
4. **Wait** for the database to finish provisioning.

### 1.2 Database Setup (The Migrations)
1. Go to the **SQL Editor** tab (on the left sidebar).
2. You will find several `.sql` files in the `supabase/migrations` folder of this repository.
3. **Important**: Copy and run them in order (001, 002, 003...). 
4. **Special Step for Triggers (012 & 014)**:
   - Before running `012` and `014`, find the lines that look like:
     `url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/...'`
   - Replace `YOUR_PROJECT_REF` with your actual project reference (found in Project Settings -> API).
   - Replace `YOUR_SUPABASE_ANON_KEY` with your project's `anon` key.

### 1.3 Storage Buckets
1. Go to **Storage** -> **New Bucket**.
2. Create `product-images` (Make it **Public**).
3. Create `payment-slips` (Keep it **Private**).

### 1.4 Authentication & Google OAuth
1. Go to **Authentication** -> **Providers** -> **Google**.
2. Enable the provider.
3. You need a **Client ID** and **Client Secret** from the [Google Cloud Console](https://console.cloud.google.com/).
4. In Google Cloud Console, add the **Callback URL** provided by Supabase.
5. In Supabase **Authentication** -> **URL Configuration**, set your "Site URL" to where your website is hosted.

---

## 2️⃣ Phase Two: Environment Secrets
These are the most important settings for the system to work.

1. Go to **Settings** -> **Edge Functions**.
2. Under **Environment Variables**, add these:
   - `ADMIN_EMAIL`: Your email (where you get order alerts).
   - `ADMIN_SECRET_TOKEN`: A secret password for your email buttons (e.g., `kamisori-super-secret`).
   - `SMTP_USER`: A dedicated Gmail address to send emails.
   - `SMTP_PASSWORD`: A 16-character **Google App Password**.
   - `SUPABASE_URL`: Your project URL.
   - `SUPABASE_SERVICE_ROLE_KEY`: Your project's `service_role` key.

---

## 3️⃣ Phase Three: The Supabase CLI
This part puts the logic (Edge Functions) onto the server.

### 3.1 Install the CLI
Open your Terminal and run:
- **Mac/Linux**: `brew install supabase/tap/supabase` (or `npm install supabase --save-dev`)
- **Windows**: `scoop bucket add supabase https://github.com/supabase/scoop-bucket.git` then `scoop install supabase`

### 3.2 Login and Link
1. Run `supabase login` and follow the link to authorize.
2. Inside the project folder, run:
   `supabase link --project-ref your-project-ref-code`

### 3.3 Deploy the logic
Run these three commands. One of them is special:

```bash
# 1. Deploy the basic notification functions
supabase functions deploy notify-admin
supabase functions deploy notify-customer

# 2. Deploy the Status Update function (Unlock it for email use)
supabase functions deploy update-order-status --no-verify-jwt
```

---

## 4️⃣ Phase Four: Create your Admin Account
1. Go to your frontend (`demo-frontend.html`) and **Sign in with Google**.
2. Go to the Supabase Dashboard -> **SQL Editor**.
3. Run this to give yourself Admin powers:
   ```sql
   INSERT INTO public.user_roles (user_id, role) 
   VALUES ('YOUR_USER_ID_FROM_AUTH_USERS', 'admin');
   ```

---

## ✅ Deployment Checklist
- [ ] Database tables exist?
- [ ] Storage buckets created?
- [ ] Google OAuth enabled?
- [ ] Environment variables (Secrets) added to Edge Functions?
- [ ] All 3 Edge Functions deployed successfully?
- [ ] No `NOT_FOUND` or `Unauthorized` errors when clicking email buttons?

**You are now fully set up!** 🍱
