import { createClient } from '@supabase/supabase-js';

// Initialize Supabase client
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

/**
 * Gets the current user ID safely
 */
async function getCurrentUserId() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  return user.id;
}

/**
 * Gets the current user's cart ID or creates one if it doesn't exist
 */
export async function getOrCreateCartId() {
  const userId = await getCurrentUserId();
  if (!userId) throw new Error('Authentication required');

  const { data: existingCart, error: cartError } = await supabase
    .from('carts')
    .select('id')
    .eq('user_id', userId)
    .single();

  if (cartError && cartError.code !== 'PGRST116') { // PGRST116 is no rows
    throw new Error(`Error fetching cart: ${cartError.message}`);
  }

  if (existingCart) return existingCart.id;

  const { data: newCart, error: createError } = await supabase
    .from('carts')
    .insert([{ user_id: userId }])
    .select('id')
    .single();

  if (createError) throw new Error(`Error creating cart: ${createError.message}`);
  return newCart.id;
}

/**
 * Adds an item to the user's cart (with variant support)
 */
export async function addToCart(productId: string, quantity: number, size?: string, color?: string) {
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

  if (error) {
    if (error.code === '23505') { // Unique violation
      return await updateCartItemQuantityVariant(cartId, productId, quantity, size, color);
    }
    throw new Error(`Error adding to cart: ${error.message}`);
  }
}

/**
 * Updates cart item quantity specifically for variants
 */
async function updateCartItemQuantityVariant(cartId: string, productId: string, additionalQty: number, size?: string, color?: string) {
  const { data, error } = await supabase
    .from('cart_items')
    .select('id, quantity')
    .eq('cart_id', cartId)
    .eq('product_id', productId)
    .eq('size', size || null)
    .eq('color', color || null)
    .single();

  if (error) throw error;

  return await supabase
    .from('cart_items')
    .update({ quantity: data.quantity + additionalQty })
    .eq('id', data.id);
}

/**
 * Gets all cart items with product details and images
 */
export async function getCartItems() {
  const userId = await getCurrentUserId();
  if (!userId) throw new Error('Authentication required');

  const { data, error } = await supabase
    .from('cart_items')
    .select(`
      id,
      quantity,
      size,
      color,
      products!inner (
        id,
        name,
        price,
        description,
        stock,
        is_preorder,
        sizes,
        colors,
        product_images (image_url, is_primary)
      )
    `)
    .eq('carts.user_id', userId);

  if (error) throw new Error(`Error fetching cart items: ${error.message}`);
  return data;
}

/**
 * Processes checkout (requires delivery details)
 */
export async function processCheckout(
  paymentMethod: 'kbz_pay' | 'cod',
  fullName: string,
  phone: string,
  address: string
) {
  const { data, error } = await supabase.rpc('checkout_cart', {
    p_payment_method: paymentMethod,
    p_full_name: fullName,
    p_phone: phone,
    p_address: address
  });

  if (error) throw new Error(`Checkout error: ${error.message}`);
  return data;
}

/**
 * Uploads payment slip for KBZ Pay
 */
export async function uploadPaymentSlip(orderId: string, file: File) {
  const filePath = `receipts/${orderId}_${Date.now()}`;
  const { data, error: uploadError } = await supabase.storage
    .from('payment-slips')
    .upload(filePath, file);

  if (uploadError) throw new Error(`Upload error: ${uploadError.message}`);

  const { data: { publicUrl } } = supabase.storage.from('payment-slips').getPublicUrl(data.path);

  const { error: dbError } = await supabase
    .from('payment_slips')
    .insert([{ order_id: orderId, image_url: publicUrl }]);

  if (dbError) throw new Error(`Database error: ${dbError.message}`);
  return publicUrl;
}

/**
 * ADMIN FUNCTIONS
 */

export async function adminGetAllOrders(pageOffset: number = 0, pageLimit: number = 50) {
  const { data, error } = await supabase.rpc('get_all_orders_admin', {
    page_offset: pageOffset,
    page_limit: pageLimit
  });
  if (error) throw new Error(`Admin error: ${error.message}`);
  return data;
}

export async function adminUpdateOrderStatus(orderId: string, status: string) {
  const { error } = await supabase.rpc('admin_update_order_status', {
    order_uuid: orderId,
    new_status: status
  });
  if (error) throw new Error(`Admin error: ${error.message}`);
}

export async function adminVerifyPayment(slipId: string, verified: boolean = true) {
  const { error } = await supabase.rpc('admin_verify_payment_slip', {
    slip_uuid: slipId,
    verified_status: verified
  });
  if (error) throw new Error(`Admin error: ${error.message}`);
}

export async function adminDeleteProduct(productId: string) {
  const { error } = await supabase.rpc('admin_delete_product', {
    product_uuid: productId
  });
  if (error) throw new Error(`Admin error: ${error.message}`);
}

export async function adminDeleteCategory(categoryId: string) {
  const { error } = await supabase.rpc('admin_delete_category', {
    category_uuid: categoryId
  });
  if (error) throw new Error(`Admin error: ${error.message}`);
}

export async function adminDeleteOrder(orderId: string) {
  const { error } = await supabase.rpc('admin_delete_order', {
    order_uuid: orderId
  });
  if (error) throw new Error(`Admin error: ${error.message}`);
}

export async function getMetrics() {
  const { data, error } = await supabase.rpc('get_business_metrics');
  if (error) throw error;
  return data[0];
}