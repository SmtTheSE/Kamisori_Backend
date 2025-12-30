# KBZ Pay and COD Payment Integration Guide

This document provides a detailed guide on how to integrate KBZ Pay and Cash on Delivery (COD) payment options into your e-commerce frontend.

## Overview

The Kamisori Backend supports two payment methods:
- Cash on Delivery (COD)
- KBZ Pay (mobile payment system)

This guide will walk you through the implementation details for both options.

## Payment Method Selection

### HTML Structure

```html
<div id="paymentOptions">
    <h4>Payment Method:</h4>
    <div>
        <input type="radio" id="cod" name="paymentMethod" value="cod" checked>
        <label for="cod">Cash on Delivery (COD)</label>
    </div>
    <div>
        <input type="radio" id="kbz" name="paymentMethod" value="kbz_pay">
        <label for="kbz">KBZ Pay</label>
    </div>
</div>

<div id="kbzQRSection" class="hidden" style="text-align: center; margin-top: 15px;">
    <h4>Scan QR Code to Pay with KBZ Pay</h4>
    <img id="kbzQRCode" src="" alt="KBZ Pay QR Code" style="width: 200px; height: 200px; margin: 10px auto;">
    <p>Please make payment via KBZ Pay and upload your payment slip</p>
    <input type="file" id="paymentSlipUpload" accept="image/*">
    <button id="uploadPaymentSlipBtn">Upload Payment Slip</button>
</div>
```

### JavaScript Implementation

```javascript
// DOM Elements
const paymentOptions = document.getElementById('paymentOptions');
const kbzQRSection = document.getElementById('kbzQRSection');
const kbzQRCode = document.getElementById('kbzQRCode');
const paymentSlipUpload = document.getElementById('paymentSlipUpload');
const uploadPaymentSlipBtn = document.getElementById('uploadPaymentSlipBtn');

// Toggle payment options visibility based on selection
function togglePaymentOptions() {
    const selectedPayment = document.querySelector('input[name="paymentMethod"]:checked').value;
    
    if (selectedPayment === 'kbz_pay') {
        kbzQRSection.classList.remove('hidden');
    } else {
        kbzQRSection.classList.add('hidden');
    }
}

// Add event listeners for payment method changes
document.querySelectorAll('input[name="paymentMethod"]').forEach((radio) => {
    radio.addEventListener('change', togglePaymentOptions);
});
```

## Checkout Process

### Processing Checkout with Selected Payment Method

```javascript
async function checkout() {
    if (!confirm('Proceed with checkout?')) return;

    try {
        const selectedPayment = document.querySelector('input[name="paymentMethod"]:checked').value;
        
        const { data: orderId, error } = await supabaseClient.rpc('checkout_cart', {
            p_payment_method: selectedPayment
        });

        if (error) throw error;

        showStatus(`Order placed successfully! Order ID: ${orderId}`);
        loadCart(); // Refresh cart
        
        // If KBZ Pay was selected, show upload instructions and generate QR code
        if (selectedPayment === 'kbz_pay') {
            // Generate and show the QR code for this specific order
            const totalAmount = parseFloat(document.getElementById('cartTotal').textContent);
            kbzQRCode.src = generateKBZPayQRCode(orderId, totalAmount);
            
            showStatus('Order placed successfully! Please scan the QR code to pay with KBZ Pay, then upload your payment slip.');
        }
    } catch (error) {
        console.error('Error during checkout:', error.message);
        showStatus(`Error during checkout: ${error.message}`, false);
    }
}

// KBZ Pay QR code generator function
function generateKBZPayQRCode(orderId, amount) {
  // This is a simplified SVG representation of a QR code
  // In production, use a proper QR code library
  const paymentData = `KBZPAY:${orderId}:${amount}`;
  
  return `data:image/svg+xml;base64,${btoa(`
    <svg width="200" height="200" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
      <rect width="200" height="200" fill="#ffffff"/>
      <g fill="#000000">
        <rect x="10" y="10" width="40" height="40"/>
        <rect x="150" y="10" width="40" height="40"/>
        <rect x="10" y="150" width="40" height="40"/>
        <rect x="30" y="30" width="20" height="20"/>
        <rect x="160" y="30" width="20" height="20"/>
        <rect x="30" y="160" width="20" height="20"/>
        
        ${generateRandomQRPattern()}
        
        <text x="100" y="185" font-size="12" text-anchor="middle" fill="#000000">
          KBZ Pay: Order #${orderId ? orderId.substring(0, 8) : 'TEMP'}
        </text>
      </g>
    </svg>
  `.trim())}`;
}

// Helper function to generate random pattern for QR code
function generateRandomQRPattern() {
  let pattern = '';
  for (let i = 0; i < 50; i++) {
    const x = 20 + Math.floor(Math.random() * 160);
    const y = 20 + Math.floor(Math.random() * 160);
    const size = 5 + Math.floor(Math.random() * 10);
    
    // Avoid placing blocks in the alignment marker areas
    if (!((x < 60 && y < 60) || (x > 140 && y < 60) || (x < 60 && y > 140))) {
      pattern += `<rect x="${x}" y="${y}" width="${size}" height="${size}"/>`;
    }
  }
  return pattern;
}
```

## KBZ Pay Payment Slip Upload

### Uploading Payment Verification

```javascript
// Upload payment slip
async function uploadPaymentSlip() {
    const file = paymentSlipUpload.files[0];
    if (!file) {
        showStatus('Please select a payment slip image', false);
        return;
    }

    try {
        // Get user
        const { data: { user } } = await supabaseClient.auth.getUser();
        if (!user) {
            showStatus('Please login first', false);
            return;
        }

        // Get the most recent order for this user that has kbz_pay method
        const { data: orders, error: ordersError } = await supabaseClient
            .from('orders')
            .select('id, payment_method, status')
            .eq('user_id', user.id)
            .eq('payment_method', 'kbz_pay')
            .order('created_at', { ascending: false })
            .limit(1);

        if (ordersError) throw ordersError;
        if (!orders || orders.length === 0) {
            showStatus('No KBZ Pay orders found', false);
            return;
        }

        const order = orders[0];
        if (order.status !== 'pending_payment') {
            showStatus('This order is not pending payment', false);
            return;
        }

        // Upload file to Supabase storage
        const fileExt = file.name.split('.').pop();
        const fileName = `${order.id}.${fileExt}`;
        const filePath = `payment-slips/${fileName}`;

        const { error: uploadError } = await supabaseClient.storage
            .from('payment-slips')
            .upload(filePath, file, { 
                cacheControl: '3600',
                upsert: false 
            });

        if (uploadError) throw uploadError;

        // Insert record into payment_slips table
        const { error: insertError } = await supabaseClient
            .from('payment_slips')
            .insert([{
                order_id: order.id,
                image_url: filePath
            }]);

        if (insertError) throw insertError;

        showStatus('Payment slip uploaded successfully! Admin will verify shortly.');
        paymentSlipUpload.value = '';
        
    } catch (error) {
        console.error('Error uploading payment slip:', error.message);
        showStatus(`Error uploading payment slip: ${error.message}`, false);
    }
}

// Add event listener for payment slip upload
uploadPaymentSlipBtn.addEventListener('click', uploadPaymentSlip);
```

## Order Status Flow

### COD Orders
1. Customer selects "Cash on Delivery"
2. Order status: `pending_confirmation`
3. Admin confirms order
4. Order status: `confirmed`
5. Admin ships order
6. Order status: `shipped`
7. Customer receives order
8. Order status: `delivered`

### KBZ Pay Orders
1. Customer selects "KBZ Pay"
2. QR code is displayed with order details
3. Customer makes payment via KBZ Pay app
4. Customer uploads payment slip
5. Order status: `pending_payment`
6. Admin verifies payment slip
7. Order status: `paid` → `confirmed`
8. Admin ships order
9. Order status: `shipped`
10. Customer receives order
11. Order status: `delivered`

## Security Considerations

1. **Payment Method Validation**: Payment methods are validated on the server side via the `checkout_cart` RPC function, preventing unauthorized changes.

2. **Order Verification**: KBZ Pay orders require manual verification by an admin before being confirmed.

3. **File Upload Security**: Payment slip uploads are restricted to image files only and stored in a dedicated Supabase storage bucket with appropriate RLS policies.

4. **User Permissions**: Only authenticated users can upload payment slips, and only for their own orders.

## Error Handling

Always implement proper error handling for payment operations:

```javascript
async function checkout() {
    try {
        // ... checkout logic
    } catch (error) {
        console.error('Error during checkout:', error.message);
        showStatus(`Error during checkout: ${error.message}`, false);
    }
}
```

## Best Practices

1. **Clear Instructions**: Provide clear instructions to users about each payment method.

2. **Visual Feedback**: Show appropriate visual feedback during payment processing.

3. **Secure Storage**: Ensure payment slips are securely stored and only accessible by authorized personnel.

4. **Order Tracking**: Allow users to track their order status after payment.

5. **Confirmation**: Always confirm payment method selection before processing checkout.

## Delivery Address Collection

### HTML Structure for Delivery Address

```html
<div id="deliveryAddressSection" class="hidden" style="margin-top: 15px; padding: 15px; border: 1px solid #ddd; border-radius: 5px;">
    <h4>Delivery Address</h4>
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
        <div>
            <label for="fullName">Full Name:</label>
            <input type="text" id="fullName" placeholder="Full Name" required style="width: 100%; padding: 8px;">
        </div>
        <div>
            <label for="phone">Phone Number:</label>
            <input type="text" id="phone" placeholder="Phone Number" required style="width: 100%; padding: 8px;">
        </div>
        <div style="grid-column: span 2;">
            <label for="address">Delivery Address:</label>
            <textarea id="address" placeholder="Full Address" required style="width: 100%; padding: 8px; height: 80px;"></textarea>
        </div>
    </div>
</div>
```

### JavaScript Implementation for Delivery Address

```javascript
// DOM Elements
const deliveryAddressSection = document.getElementById('deliveryAddressSection');
const fullNameInput = document.getElementById('fullName');
const phoneInput = document.getElementById('phone');
const addressInput = document.getElementById('address');

// Save delivery address to database
async function saveDeliveryAddress(orderId) {
    const fullName = fullNameInput.value.trim();
    const phone = phoneInput.value.trim();
    const address = addressInput.value.trim();
    
    if (!fullName || !phone || !address) {
        showStatus('Please fill in all delivery address fields', false);
        return false;
    }
    
    try {
        const { error } = await supabaseClient
            .from('delivery_addresses')
            .insert([{
                order_id: orderId,
                full_name: fullName,
                phone: phone,
                address: address
            }]);
        
        if (error) throw error;
        
        return true;
    } catch (error) {
        console.error('Error saving delivery address:', error.message);
        showStatus(`Error saving delivery address: ${error.message}`, false);
        return false;
    }
}
```

## Admin Panel Integration

The admin panel now includes delivery address information in the orders table and properly displays product variants:

```html
<table id="ordersTable" style="width: 100%; border-collapse: collapse;">
    <thead>
        <tr style="background-color: #f2f2f2;">
            <th>Order ID</th>
            <th>Customer</th>
            <th>Products</th>
            <th>Total</th>
            <th>Payment</th>
            <th>Delivery Address</th>
            <th>Status</th>
            <th>Actions</th>
        </tr>
    </thead>
    <tbody id="ordersBody">
        <!-- Orders will be loaded here -->
    </tbody>
</table>
```

### JavaScript Implementation

```javascript
// Load recent orders
const { data: orders, error: ordersError } = await supabaseClient.rpc('get_all_orders_admin', {
    page_offset: 0,
    page_limit: 10
});

ordersBody.innerHTML = '';
orders.forEach(order => {
    // Format products list with size and color variants
    let productsList = 'N/A';
    if (order.order_items && Array.isArray(order.order_items)) {
        productsList = order.order_items.map(item => {
            let variantInfo = '';
            if (item.size || item.color) {
                const variants = [];
                if (item.size) variants.push(`Size: ${item.size}`);
                if (item.color) variants.push(`Color: ${item.color}`);
                variantInfo = ` (${variants.join(', ')})`;
            }
            return `${item.product_name}${variantInfo} x${item.quantity}`;
        }).join('<br>');
    }
    
    // Format delivery address
    let deliveryAddress = 'N/A';
    if (order.delivery_address && order.delivery_address.full_name) {
        deliveryAddress = `${order.delivery_address.full_name}<br>${order.delivery_address.phone}<br>${order.delivery_address.address}`;
    }

    const row = document.createElement('tr');
    row.innerHTML = `
        <td>${order.id.substring(0, 8)}...</td>
        <td>${order.customer_full_name || order.customer_email || 'N/A'}</td>
        <td>${productsList}</td>
        <td>$${order.total_amount}</td>
        <td>${order.payment_method}</td>
        <td>${deliveryAddress}</td>
        <td>
            <select onchange="updateOrderStatus('${order.id}', this.value)" id="status-${order.id}">
                <option value="pending_payment" ${order.status === 'pending_payment' ? 'selected' : ''}>Pending Payment</option>
                <option value="pending_confirmation" ${order.status === 'pending_confirmation' ? 'selected' : ''}>Pending Confirmation</option>
                <option value="paid" ${order.status === 'paid' ? 'selected' : ''}>Paid</option>
                <option value="confirmed" ${order.status === 'confirmed' ? 'selected' : ''}>Confirmed</option>
                <option value="shipped" ${order.status === 'shipped' ? 'selected' : ''}>Shipped</option>
                <option value="delivered" ${order.status === 'delivered' ? 'selected' : ''}>Delivered</option>
                <option value="cancelled" ${order.status === 'cancelled' ? 'selected' : ''}>Cancelled</option>
            </select>
        </td>
        <td>
            <button class="admin-btn" onclick="updateOrderStatus('${order.id}', document.getElementById('status-${order.id}').value)">
                Update
            </button>
        </td>
    `;
    ordersBody.appendChild(row);
});
```

