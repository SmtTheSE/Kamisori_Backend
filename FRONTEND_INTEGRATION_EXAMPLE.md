# Frontend Integration Example

This document shows how frontend developers can easily integrate with the e-commerce backend API with minimal complexity.

## Setup

First, install the Supabase client:

```bash
npm install @supabase/supabase-js
```

Initialize the client:

```javascript
// lib/supabaseClient.js
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)

export default supabase
```

## Common Operations

### 1. Product Catalog Page

```javascript
// pages/products.js
import { useState, useEffect } from 'react'
import supabase from '../lib/supabaseClient'

export default function ProductsPage() {
  const [products, setProducts] = useState([])
  const [categories, setCategories] = useState([])
  const [selectedCategory, setSelectedCategory] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadProducts()
    loadCategories()
  }, [])

  const loadProducts = async () => {
    setLoading(true)
    try {
      let query = supabase
        .from('products')
        .select(`
          id,
          name,
          description,
          price,
          stock,
          is_preorder,
          product_categories!inner (
            id,
            season,
            year
          )
        `)
        .eq('is_active', true)

      if (selectedCategory) {
        query = query.eq('category_id', selectedCategory)
      }

      const { data, error } = await query
      if (error) throw error
      setProducts(data)
    } catch (error) {
      console.error('Error loading products:', error.message)
    } finally {
      setLoading(false)
    }
  }

  const loadCategories = async () => {
    try {
      const { data, error } = await supabase
        .from('product_categories')
        .select('*')
        .eq('is_active', true)
      
      if (error) throw error
      setCategories(data)
    } catch (error) {
      console.error('Error loading categories:', error.message)
    }
  }

  const handleCategoryChange = (categoryId) => {
    setSelectedCategory(categoryId || null)
  }

  if (loading) return <div>Loading...</div>

  return (
    <div>
      <h1>Products</h1>
      
      <div>
        <label>Filter by Category:</label>
        <select onChange={(e) => handleCategoryChange(e.target.value)} value={selectedCategory || ''}>
          <option value="">All Categories</option>
          {categories.map(category => (
            <option key={category.id} value={category.id}>
              {category.season} {category.year}
            </option>
          ))}
        </select>
      </div>
      
      <div className="products-grid">
        {products.map(product => (
          <div key={product.id} className="product-card">
            <h3>{product.name}</h3>
            <p>{product.description}</p>
            <p>Price: ${product.price}</p>
            <p>Stock: {product.stock || 'Out of stock'}</p>
            {product.is_preorder && <span>Pre-order</span>}
            <button onClick={() => addToCart(product.id, 1)}>Add to Cart</button>
          </div>
        ))}
      </div>
    </div>
  )
}

// Function to add to cart
const addToCart = async (productId, quantity) => {
  try {
    // Get or create user's cart
    let { data: cart, error: cartError } = await supabase
      .from('carts')
      .select('id')
      .eq('user_id', supabase.auth.user().id)
      .single()

    if (cartError) {
      // Create cart if it doesn't exist
      const { data, error } = await supabase
        .from('carts')
        .insert([{ user_id: supabase.auth.user().id }])
        .select('id')
        .single()
      
      if (error) throw error
      cart = data
    }

    // Add item to cart
    const { error } = await supabase
      .from('cart_items')
      .insert([{ 
        cart_id: cart.id, 
        product_id: productId, 
        quantity: quantity 
      }])

    if (error) {
      if (error.code === '23505') { // Unique violation - item already in cart
        // Update quantity instead
        const { error: updateError } = await supabase.rpc('update_cart_item_quantity', {
          product_id: productId,
          quantity: quantity
        })
        
        if (updateError) throw updateError
      } else {
        throw error
      }
    }
    
    alert('Added to cart!')
  } catch (error) {
    console.error('Error adding to cart:', error.message)
    alert('Error adding to cart: ' + error.message)
  }
}
```

### 2. Shopping Cart Page

```javascript
// pages/cart.js
import { useState, useEffect } from 'react'
import supabase from '../lib/supabaseClient'

export default function CartPage() {
  const [cartItems, setCartItems] = useState([])
  const [cartTotal, setCartTotal] = useState(0)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadCart()
  }, [])

  const loadCart = async () => {
    try {
      const { data, error } = await supabase
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
        .eq('carts.user_id', supabase.auth.user().id)

      if (error) throw error
      setCartItems(data)

      // Get cart total
      const { data: totalData, error: totalError } = await supabase
        .from('cart_totals')
        .select('total_amount')
        .eq('user_id', supabase.auth.user().id)
        .single()

      if (totalError) {
        setCartTotal(0)
      } else {
        setCartTotal(totalData.total_amount)
      }
    } catch (error) {
      console.error('Error loading cart:', error.message)
    } finally {
      setLoading(false)
    }
  }

  const updateQuantity = async (cartItemId, newQuantity) => {
    if (newQuantity <= 0) {
      removeFromCart(cartItemId)
      return
    }

    try {
      const { error } = await supabase
        .from('cart_items')
        .update({ quantity: newQuantity })
        .eq('id', cartItemId)

      if (error) throw error
      loadCart() // Reload cart to update total
    } catch (error) {
      console.error('Error updating quantity:', error.message)
    }
  }

  const removeFromCart = async (cartItemId) => {
    try {
      const { error } = await supabase
        .from('cart_items')
        .delete()
        .eq('id', cartItemId)

      if (error) throw error
      loadCart() // Reload cart
    } catch (error) {
      console.error('Error removing item:', error.message)
    }
  }

  if (loading) return <div>Loading cart...</div>

  return (
    <div>
      <h1>Your Cart</h1>
      
      {cartItems.length === 0 ? (
        <p>Your cart is empty</p>
      ) : (
        <>
          <div className="cart-items">
            {cartItems.map(item => (
              <div key={item.id} className="cart-item">
                <h3>{item.products.name}</h3>
                <p>Price: ${item.products.price}</p>
                <div>
                  <button onClick={() => updateQuantity(item.id, item.quantity - 1)}>-</button>
                  <span>{item.quantity}</span>
                  <button onClick={() => updateQuantity(item.id, item.quantity + 1)}>+</button>
                </div>
                <p>Total: ${(item.quantity * item.products.price).toFixed(2)}</p>
                <button onClick={() => removeFromCart(item.id)}>Remove</button>
              </div>
            ))}
          </div>
          
          <div className="cart-summary">
            <h2>Total: ${cartTotal.toFixed(2)}</h2>
            <button onClick={() => checkout()}>Proceed to Checkout</button>
          </div>
        </>
      )}
    </div>
  )
}

const checkout = async () => {
  if (!confirm('Proceed to checkout?')) return
  
  try {
    // First get the order ID by processing checkout
    const { data: orderId, error } = await supabase.rpc('checkout_cart', {
      p_payment_method: 'kbz_pay' // or 'cod'
    })

    if (error) throw error

    // Then redirect to checkout page with order ID
    window.location.href = `/checkout/${orderId}`
  } catch (error) {
    console.error('Error during checkout:', error.message)
    alert('Error during checkout: ' + error.message)
  }
}
```

### 3. Admin Dashboard Example

```javascript
// pages/admin/dashboard.js
import { useState, useEffect } from 'react'
import supabase from '../../lib/supabaseClient'

export default function AdminDashboard() {
  const [metrics, setMetrics] = useState(null)
  const [orders, setOrders] = useState([])
  const [unverifiedSlips, setUnverifiedSlips] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (supabase.auth.user()) {
      loadDashboardData()
    }
  }, [])

  const loadDashboardData = async () => {
    try {
      // Get business metrics
      const { data: metricsData, error: metricsError } = await supabase.rpc('get_business_metrics')
      if (metricsError) throw metricsError
      setMetrics(metricsData[0])

      // Get recent orders
      const { data: ordersData, error: ordersError } = await supabase.rpc('get_all_orders_admin', {
        page_offset: 0,
        page_limit: 10
      })
      if (ordersError) throw ordersError
      setOrders(ordersData)

      // Get unverified payment slips
      const { data: slipsData, error: slipsError } = await supabase.rpc('get_unverified_payment_slips')
      if (slipsError) throw slipsError
      setUnverifiedSlips(slpsData)
    } catch (error) {
      console.error('Error loading dashboard:', error.message)
    } finally {
      setLoading(false)
    }
  }

  const updateOrderStatus = async (orderId, newStatus) => {
    try {
      const { error } = await supabase.rpc('admin_update_order_status', {
        order_uuid: orderId,
        new_status: newStatus
      })

      if (error) throw error

      alert('Order status updated!')
      loadDashboardData() // Refresh data
    } catch (error) {
      console.error('Error updating order status:', error.message)
      alert('Error updating order status: ' + error.message)
    }
  }

  const verifyPaymentSlip = async (slipId, verify = true) => {
    try {
      const { error } = await supabase.rpc('admin_verify_payment_slip', {
        slip_uuid: slipId,
        verified_status: verify
      })

      if (error) throw error

      alert(`Payment slip ${verify ? 'verified' : 'unverified'}!`)
      loadDashboardData() // Refresh data
    } catch (error) {
      console.error('Error updating payment slip:', error.message)
      alert('Error updating payment slip: ' + error.message)
    }
  }

  if (loading) return <div>Loading dashboard...</div>

  return (
    <div>
      <h1>Admin Dashboard</h1>

      {/* Business Metrics */}
      {metrics && (
        <div className="metrics">
          <div>Total Customers: {metrics.total_customers}</div>
          <div>Total Orders: {metrics.total_orders}</div>
          <div>Total Revenue: ${metrics.total_revenue}</div>
          <div>Pending Orders: {metrics.pending_orders}</div>
          <div>Processing Orders: {metrics.processing_orders}</div>
        </div>
      )}

      {/* Recent Orders */}
      <div className="recent-orders">
        <h2>Recent Orders</h2>
        <table>
          <thead>
            <tr>
              <th>Order ID</th>
              <th>Customer</th>
              <th>Total</th>
              <th>Payment Method</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {orders.map(order => (
              <tr key={order.id}>
                <td>{order.id}</td>
                <td>{order.customer_full_name || order.customer_email}</td>
                <td>${order.total_amount}</td>
                <td>{order.payment_method}</td>
                <td>{order.status}</td>
                <td>
                  <select 
                    value={order.status} 
                    onChange={(e) => updateOrderStatus(order.id, e.target.value)}
                  >
                    <option value="pending_payment">Pending Payment</option>
                    <option value="pending_confirmation">Pending Confirmation</option>
                    <option value="paid">Paid</option>
                    <option value="confirmed">Confirmed</option>
                    <option value="shipped">Shipped</option>
                    <option value="delivered">Delivered</option>
                    <option value="cancelled">Cancelled</option>
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Unverified Payment Slips */}
      <div className="payment-slips">
        <h2>Unverified Payment Slips</h2>
        {unverifiedSlips.length > 0 ? (
          <table>
            <thead>
              <tr>
                <th>Order ID</th>
                <th>Customer</th>
                <th>Order Total</th>
                <th>Uploaded At</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {unverifiedSlips.map(slip => (
                <tr key={slip.id}>
                  <td>{slip.order_id}</td>
                  <td>{slip.customer_name || slip.customer_email}</td>
                  <td>${slip.order_total}</td>
                  <td>{new Date(slip.uploaded_at).toLocaleString()}</td>
                  <td>
                    <button onClick={() => verifyPaymentSlip(slip.id, true)}>Verify</button>
                    <button onClick={() => verifyPaymentSlip(slip.id, false)}>Reject</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p>No unverified payment slips</p>
        )}
      </div>
    </div>
  )
}
```

## Key Points for Frontend Developers

1. **Simple API Calls**: All operations use straightforward Supabase API calls with clear function names.

2. **Built-in Security**: All sensitive operations are protected by RLS and role validation.

3. **Server-side Logic**: All price calculations and business logic happen on the server side, preventing frontend manipulation.

4. **Consistent Data Format**: All API responses follow a consistent format.

5. **Error Handling**: All operations return clear error messages that can be displayed to users.

6. **No Complex Setup**: Frontend developers only need to initialize Supabase and can immediately start making API calls.

The backend is designed to be developer-friendly while maintaining strong security. Frontend developers can implement complex functionality with just a few lines of code, without worrying about security implementation or business logic validation.