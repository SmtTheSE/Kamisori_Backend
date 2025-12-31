import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.5";

// This function is called when an order status is updated to 'paid' or 'confirmed'
// It sends an email notification to the customer
serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    // Get the payload from the trigger
    const payload = await req.json();
    const { order_id, new_status } = payload;

    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get order details
    const { data: order, error: orderError } = await supabaseClient
      .from("orders")
      .select(`
        id,
        total_amount,
        payment_method,
        status,
        created_at,
        users:auth.users!user_id (email, user_metadata)
      `)
      .eq("id", order_id)
      .single();

    if (orderError) {
      throw new Error(`Error fetching order: ${orderError.message}`);
    }

    // Prepare different notifications based on status
    let subject = "";
    let htmlContent = "";

    switch (new_status) {
      case "paid":
        subject = `Payment Verified for Order #${order_id}`;
        htmlContent = `
          <h2>Payment Verified</h2>
          <p>Hi ${order.users.user_metadata?.full_name || 'Customer'},</p>
          <p>Your payment for order #${order_id} has been verified.</p>
          <p><strong>Order Details:</strong></p>
          <ul>
            <li>Order ID: ${order_id}</li>
            <li>Total Amount: ${order.total_amount}</li>
            <li>Payment Method: ${order.payment_method}</li>
            <li>Order Date: ${order.created_at}</li>
          </ul>
          <p>We will process your order shortly.</p>
        `;
        break;
        
      case "confirmed":
        subject = `Order #${order_id} Confirmed`;
        htmlContent = `
          <h2>Order Confirmed</h2>
          <p>Hi ${order.users.user_metadata?.full_name || 'Customer'},</p>
          <p>Your order #${order_id} has been confirmed and will be shipped soon.</p>
          <p><strong>Order Details:</strong></p>
          <ul>
            <li>Order ID: ${order_id}</li>
            <li>Total Amount: ${order.total_amount}</li>
            <li>Payment Method: ${order.payment_method}</li>
            <li>Order Date: ${order.created_at}</li>
          </ul>
        `;
        break;
        
      case "shipped":
        subject = `Order #${order_id} Shipped`;
        htmlContent = `
          <h2>Order Shipped</h2>
          <p>Hi ${order.users.user_metadata?.full_name || 'Customer'},</p>
          <p>Your order #${order_id} has been shipped.</p>
          <p><strong>Order Details:</strong></p>
          <ul>
            <li>Order ID: ${order_id}</li>
            <li>Total Amount: ${order.total_amount}</li>
            <li>Payment Method: ${order.payment_method}</li>
            <li>Order Date: ${order.created_at}</li>
          </ul>
          <p>Tracking information will be sent when available.</p>
        `;
        break;
        
      case "delivered":
        subject = `Order #${order_id} Delivered`;
        htmlContent = `
          <h2>Order Delivered</h2>
          <p>Hi ${order.users.user_metadata?.full_name || 'Customer'},</p>
          <p>Your order #${order_id} has been delivered.</p>
          <p><strong>Order Details:</strong></p>
          <ul>
            <li>Order ID: ${order_id}</li>
            <li>Total Amount: ${order.total_amount}</li>
            <li>Payment Method: ${order.payment_method}</li>
            <li>Order Date: ${order.created_at}</li>
          </ul>
          <p>Thank you for shopping with us!</p>
        `;
        break;
        
      case "cancelled":
        subject = `Order #${order_id} Cancelled`;
        htmlContent = `
          <h2>Order Cancelled</h2>
          <p>Hi ${order.users.user_metadata?.full_name || 'Customer'},</p>
          <p>Your order #${order_id} has been cancelled.</p>
          <p><strong>Order Details:</strong></p>
          <ul>
            <li>Order ID: ${order_id}</li>
            <li>Total Amount: ${order.total_amount}</li>
            <li>Payment Method: ${order.payment_method}</li>
            <li>Order Date: ${order.created_at}</li>
          </ul>
          <p>If you have any questions, please contact our support team.</p>
        `;
        break;
        
      default:
        return new Response(
          JSON.stringify({ message: "No notification needed for this status" }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        );
    }

    // Send email notification to customer
    const customerEmail = order.users.email;

    console.log("Email notification would be sent to:", customerEmail);
    console.log("Subject:", subject);
    console.log("Content:", htmlContent);

    // Store this notification in a log table if needed
    const { error: logError } = await supabaseClient
      .from("customer_notifications")
      .insert({
        order_id,
        notification_type: `order_${new_status}`,
        message: `Order ${order_id} status updated to ${new_status}`,
        recipient_email: customerEmail,
      });

    if (logError) {
      console.error("Error logging notification:", logError);
    }

    return new Response(
      JSON.stringify({ message: "Customer notification sent successfully" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error in notify-customer function:", error);
    return new Response(
      JSON.stringify({ error: error?.message || "An error occurred" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});