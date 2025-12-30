import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.5";

// This function is called when a payment slip is uploaded
// It sends an email notification to the admin
serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    // Get the payload from the trigger
    const payload = await req.json();
    const { order_id, slip_url } = payload;

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
        created_at,
        total_amount,
        payment_method,
        users:auth.users!user_id (email, user_metadata)
      `)
      .eq("id", order_id)
      .single();

    if (orderError) {
      throw new Error(`Error fetching order: ${orderError.message}`);
    }

    // Get admin email (in a real app, you might have a specific admin email or fetch from a table)
    const adminEmail = Deno.env.get("ADMIN_EMAIL") || "admin@example.com";

    // Prepare email content
    const subject = `New Payment Slip Uploaded for Order #${order_id}`;
    const htmlContent = `
      <h2>New Payment Slip Uploaded</h2>
      <p><strong>Order ID:</strong> ${order_id}</p>
      <p><strong>Order Date:</strong> ${order.created_at}</p>
      <p><strong>Total Amount:</strong> ${order.total_amount}</p>
      <p><strong>Payment Method:</strong> ${order.payment_method}</p>
      <p><strong>Customer:</strong> ${order.users.user_metadata?.full_name || order.users.email}</p>
      <p><a href="${slip_url}" target="_blank">View Payment Slip</a></p>
      <p>Please verify this payment slip and update the order status accordingly.</p>
    `;

    // In a real implementation, you would use your email service here
    // For example, with SendGrid, Mailgun, or other email APIs
    console.log("Email notification would be sent to:", adminEmail);
    console.log("Subject:", subject);
    console.log("Content:", htmlContent);

    // Example using a fictional email service
    // const emailResponse = await fetch('https://api.emailservice.com/send', {
    //   method: 'POST',
    //   headers: {
    //     'Content-Type': 'application/json',
    //     'Authorization': `Bearer ${Deno.env.get('EMAIL_SERVICE_KEY')}`
    //   },
    //   body: JSON.stringify({
    //     to: adminEmail,
    //     subject: subject,
    //     html: htmlContent
    //   })
    // });

    // You can also store this notification in a log table if needed
    const { error: logError } = await supabaseClient
      .from("payment_notifications")
      .insert({
        order_id,
        notification_type: "payment_uploaded",
        message: `Payment slip uploaded for order ${order_id}`,
      });

    if (logError) {
      console.error("Error logging notification:", logError);
    }

    return new Response(
      JSON.stringify({ message: "Notification sent successfully" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error in notify-admin function:", error);
    return new Response(
      JSON.stringify({ error: error?.message || "An error occurred" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});