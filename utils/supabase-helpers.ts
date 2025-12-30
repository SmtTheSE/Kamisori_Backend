import { createClient, SupabaseClient } from '@supabase/supabase-js';

// Initialize Supabase client
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

/**
 * Gets the current user's cart or creates one if it doesn't exist
 */
export async function getOrCreateCart() {
  // First try to get existing cart
  const { data: existingCart, error: cartError } = await supabase
    .from('carts')
    .select('id')
    .eq('user_id', supabase.auth.currentSession?.user.id)
    .single();

  if (cartError && cartError.code !== 'DATA_RETURNED_NO_ROWS') {
    throw new Error(`Error fetching cart: ${cartError.message}`);
  }

  if (existingCart) {
    return existingCart.id;
  }

  // Create a new cart if one doesn't exist
  const { data: newCart, error: createError } = await supabase
    .from('carts')
    .insert([{ user_id: supabase.auth.currentSession?.user.id }])
    .select('id')
    .single();

  if (createError) {
    throw new Error(`Error creating cart: ${createError.message}`);
  }

  return newCart.id;
}

/**
 * Adds an item to the user's cart
 */
export async function addToCart(productId: string, quantity: number) {
  const cartId = await getOrCreateCart();
  
  const { error } = await supabase
    .from('cart_items')
    .insert([{ 
      cart_id: cartId, 
      product_id: productId, 
      quantity: quantity 
    }]);

  if (error) {
    if (error.code === '23505') { // Unique violation - item already in cart
      // Update quantity instead
      return await updateCartItemQuantityByProductId(productId, quantity);
    } else {
      throw new Error(`Error adding to cart: ${error.message}`);
    }
  }
}

/**
 * Updates the quantity of a cart item
 */
export async function updateCartItemQuantity(cartItemId: string, newQuantity: number) {
  if (newQuantity <= 0) {
    return await removeCartItem(cartItemId);
  }
  
  const { error } = await supabase
    .from('cart_items')
    .update({ quantity: newQuantity })
    .eq('id', cartItemId);

  if (error) {
    throw new Error(`Error updating cart item: ${error.message}`);
  }
}

/**
 * Updates the quantity of a cart item by product ID
 */
export async function updateCartItemQuantityByProductId(productId: string, additionalQuantity: number) {
  const { data: cartItem, error } = await supabase
    .from('cart_items')
    .select('id, quantity')
    .eq('product_id', productId)
    .eq('carts.user_id', supabase.auth.currentSession?.user.id)
    .single();

  if (error) {
    throw new Error(`Error fetching cart item: ${error.message}`);
  }

  const newQuantity = cartItem.quantity + additionalQuantity;
  if (newQuantity <= 0) {
    return await removeCartItem(cartItem.id);
  }
  
  const { error: updateError } = await supabase
    .from('cart_items')
    .update({ quantity: newQuantity })
    .eq('id', cartItem.id);

  if (updateError) {
    throw new Error(`Error updating cart item: ${updateError.message}`);
  }
}

/**
 * Removes an item from the cart
 */
export async function removeCartItem(cartItemId: string) {
  const { error } = await supabase
    .from('cart_items')
    .delete()
    .eq('id', cartItemId);

  if (error) {
    throw new Error(`Error removing cart item: ${error.message}`);
  }
}

/**
 * Gets all items in the current user's cart
 */
export async function getCartItems() {
  const { data, error } = await supabase
    .from('cart_items')
    .select(`
      id,
      quantity,
      product_id,
      products!inner (
        id,
        name,
        price,
        description,
        stock,
        is_preorder
      )
    `)
    .eq('carts.user_id', supabase.auth.currentSession?.user.id);

  if (error) {
    throw new Error(`Error fetching cart items: ${error.message}`);
  }

  return data;
}

/**
 * Gets the total amount for the current user's cart
 */
export async function getCartTotal() {
  const { data, error } = await supabase
    .from('cart_totals')
    .select('total_amount')
    .eq('user_id', supabase.auth.currentSession?.user.id)
    .single();

  if (error && error.code !== 'DATA_RETURNED_NO_ROWS') {
    throw new Error(`Error fetching cart total: ${error.message}`);
  }

  return data?.total_amount || 0;
}

/**
 * Processes checkout and creates an order
 */
export async function processCheckout(paymentMethod: 'kbz_pay' | 'cod') {
  const { data, error } = await supabase.rpc('checkout_cart', {
    p_payment_method: paymentMethod
  });

  if (error) {
    throw new Error(`Error processing checkout: ${error.message}`);
  }

  return data;
}

/**
 * Uploads a payment slip for KBZ Pay
 */
export async function uploadPaymentSlip(orderId: string, file: File) {
  // Upload file to storage
  const { data, error: uploadError } = await supabase
    .storage
    .from('payment-slips')
    .upload(`receipt_${orderId}_${Date.now()}`, file, {
      cacheControl: '3600',
      upsert: false
    });

  if (uploadError) {
    throw new Error(`Error uploading payment slip: ${uploadError.message}`);
  }

  // Get public URL
  const { data: publicUrlData } = supabase
    .storage
    .from('payment-slips')
    .getPublicUrl(data.path);

  // Save URL to payment_slips table
  const { error: dbError } = await supabase
    .from('payment_slips')
    .insert([{
      order_id: orderId,
      image_url: publicUrlData.publicUrl
    }]);

  if (dbError) {
    throw new Error(`Error saving payment slip: ${dbError.message}`);
  }

  return publicUrlData.publicUrl;
}

/**
 * Gets all active product categories
 */
export async function getProductCategories() {
  const { data, error } = await supabase
    .from('product_category_labels')
    .select('*')
    .eq('is_active', true);

  if (error) {
    throw new Error(`Error fetching product categories: ${error.message}`);
  }

  return data;
}

/**
 * Gets all active products, optionally filtered by category
 */
export async function getProducts(categoryId?: string) {
  let query = supabase
    .from('products')
    .select('*')
    .eq('is_active', true);

  if (categoryId) {
    query = query.eq('category_id', categoryId);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Error fetching products: ${error.message}`);
  }

  return data;
}

/**
 * Gets a specific product by ID
 */
export async function getProductById(productId: string) {
  const { data, error } = await supabase
    .from('products')
    .select('*')
    .eq('id', productId)
    .eq('is_active', true)
    .single();

  if (error) {
    throw new Error(`Error fetching product: ${error.message}`);
  }

  return data;
}

/**
 * Gets all orders for the current user
 */
export async function getUserOrders() {
  const { data, error } = await supabase
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
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(`Error fetching user orders: ${error.message}`);
  }

  return data;
}

/**
 * Gets a specific order for the current user
 */
export async function getUserOrder(orderId: string) {
  const { data, error } = await supabase
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
    .single();

  if (error) {
    throw new Error(`Error fetching user order: ${error.message}`);
  }

  return data;
}