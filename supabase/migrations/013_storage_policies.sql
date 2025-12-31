-- Kamisori Backend - Storage Policies
-- This migration provides all storage policies for Supabase storage buckets
-- including product images and payment slips

-- RLS policies for storage buckets

-- RLS policies for product-images bucket
-- Only authenticated users with admin role can upload images
DROP POLICY IF EXISTS "Admin can upload product images" ON storage.objects;
CREATE POLICY "Admin can upload product images" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'product-images' AND (SELECT is_admin()));

-- Only authenticated users with admin role can update product images  
DROP POLICY IF EXISTS "Admin can update product images" ON storage.objects;
CREATE POLICY "Admin can update product images" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'product-images' AND (SELECT is_admin()));

-- Only authenticated users with admin role can delete product images
DROP POLICY IF EXISTS "Admin can delete product images" ON storage.objects;
CREATE POLICY "Admin can delete product images" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'product-images' AND (SELECT is_admin()));

-- Everyone can read product images
DROP POLICY IF EXISTS "Public can read product images" ON storage.objects;
CREATE POLICY "Public can read product images" ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'product-images');

-- RLS policies for payment-slips bucket
-- Only authenticated users with admin role can upload payment slips
DROP POLICY IF EXISTS "Admin can upload payment slips" ON storage.objects;
CREATE POLICY "Admin can upload payment slips" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'payment-slips' AND (SELECT is_admin()));

-- Only authenticated users with admin role can update payment slips
DROP POLICY IF EXISTS "Admin can update payment slips" ON storage.objects;
CREATE POLICY "Admin can update payment slips" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'payment-slips' AND (SELECT is_admin()));

-- Only authenticated users with admin role can delete payment slips
DROP POLICY IF EXISTS "Admin can delete payment slips" ON storage.objects;
CREATE POLICY "Admin can delete payment slips" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'payment-slips' AND (SELECT is_admin()));

-- Only authenticated users with admin role can read payment slips
DROP POLICY IF EXISTS "Admin can read payment slips" ON storage.objects;
CREATE POLICY "Admin can read payment slips" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'payment-slips' AND (SELECT is_admin()));