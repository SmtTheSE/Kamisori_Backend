import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.5";

// This function is called when a payment slip is uploaded or when a new order is placed
// It sends an email notification to the admin
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get the payload from the trigger
    const payload = await req.json();
    const { order_id, slip_url, notification_type } = payload;

    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    console.log("Notification trigger received:", { order_id, notification_type });

    // Handle TEST PING (Diagnostic)
    if (notification_type === 'test_ping') {
      const adminEmail = Deno.env.get("ADMIN_EMAIL") || "sittminthar005@gmail.com";
      const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

      await supabaseClient.from("trigger_logs").insert({
        level: 'info',
        message: 'TEST PING STARTED',
        details: { adminEmail, hasKey: !!RESEND_API_KEY }
      });

      if (!RESEND_API_KEY) {
        return new Response(JSON.stringify({ error: "RESEND_API_KEY missing" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        });
      }

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${RESEND_API_KEY}`,
        },
        body: JSON.stringify({
          from: 'Kamisori Diagnostic <onboarding@resend.dev>',
          to: [adminEmail],
          subject: '🔔 Diagnostic Test Email',
          html: '<h1>It Works!</h1><p>If you see this, your Edge Function and Resend configuration are working perfectly.</p>',
        }),
      });

      const resData = await res.json();
      await supabaseClient.from("trigger_logs").insert({
        level: res.ok ? 'info' : 'error',
        message: res.ok ? 'TEST EMAIL SENT' : 'TEST EMAIL FAILED',
        details: resData
      });

      return new Response(JSON.stringify({ success: res.ok, data: resData }), {
        status: res.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Normal flow starts here
    await supabaseClient.from("trigger_logs").insert({
      level: 'info',
      message: `Processing ${notification_type} for order ${order_id}`,
      order_id
    });
    const { data: order, error: orderError } = await supabaseClient
      .from("orders")
      .select(`
        id,
        user_id,
        created_at,
        total_amount,
        payment_method,
        status,
        order_items (
          id,
          quantity,
          price,
          size,
          color,
          products (
            id,
            name,
            description
          )
        ),
        delivery_addresses (
          id,
          full_name,
          phone,
          address
        )
      `)
      .eq("id", order_id)
      .single();

    if (orderError || !order) {
      console.error("Order fetch error:", orderError);
      throw new Error(`Error fetching order: ${orderError?.message || 'Order not found'}`);
    }

    // Fetch user details separately using Service Role (via auth admin)
    // This is much more reliable than joining auth.users which is restricted
    const { data: userData, error: userError } = await supabaseClient.auth.admin.getUserById(order.user_id);

    if (userError || !userData?.user) {
      console.error("User fetch error:", userError);
      // We don't throw here, just fallback to payload email if available
    }

    const customerEmail = userData?.user?.email || payload.user_email || "N/A";
    const userMeta = userData?.user?.user_metadata || {};


    // Get admin email
    const adminEmail = Deno.env.get("ADMIN_EMAIL") || "admin@example.com";

    if (notification_type === 'new_order') {
      // Prepare email content
      const subject = `New Order #${order.id.substring(0, 8)} Received`;

      // Format products list
      const productsList = order.order_items.map(item => {
        const variants = [];
        if (item.size) variants.push(`Size: ${item.size}`);
        if (item.color) variants.push(`Color: ${item.color}`);
        const variantsText = variants.length > 0 ? ` (${variants.join(', ')})` : '';

        return `- ${item.products.name}${variantsText} x${item.quantity} - $${item.price}`;
      }).join('<br>');

      const deliveryAddress = order.delivery_addresses?.[0] || null;
      const customerFullName = deliveryAddress?.full_name || userMeta.full_name || userMeta.name || customerEmail;

      const htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
          <h2 style="color: #333; border-bottom: 2px solid #333; padding-bottom: 10px;">New Order Received</h2>
          <div style="margin-bottom: 20px;">
            <p><strong>Order ID:</strong> #${order.id.substring(0, 8)}</p>
            <p><strong>Order Date:</strong> ${new Date(order.created_at).toLocaleString('en-US', { dateStyle: 'full', timeStyle: 'short' })}</p>
            <p><strong>Total Amount:</strong> <span style="font-size: 1.2em; color: #2e7d32;">$${order.total_amount}</span></p>
            <p><strong>Payment Method:</strong> ${order.payment_method.toUpperCase().replace('_', ' ')}</p>
            <p><strong>Status:</strong> <span style="background: #e3f2fd; padding: 2px 8px; border-radius: 4px;">${order.status}</span></p>
          </div>
          <h3 style="border-bottom: 1px solid #eee; padding-bottom: 5px;">Customer Details</h3>
          <p><strong>Name:</strong> ${customerFullName}</p>
          <p><strong>Email:</strong> ${customerEmail}</p>
          ${deliveryAddress ? `<p><strong>Phone:</strong> ${deliveryAddress.phone}</p>` : ''}
          <h3 style="border-bottom: 1px solid #eee; padding-bottom: 5px;">Delivery Address</h3>
          ${deliveryAddress ? `<p style="background: #f9f9f9; padding: 10px; border-radius: 5px; line-height: 1.5;">${deliveryAddress.address}</p>` : '<p style="color: #d32f2f;">No delivery address provided</p>'}
          <h3 style="border-bottom: 1px solid #eee; padding-bottom: 5px;">Ordered Items</h3>
          <div style="margin-bottom: 20px;">${productsList}</div>
          <p style="font-size: 0.9em; color: #666; margin-top: 30px; border-top: 1px solid #eee; padding-top: 10px;">
            This is an automated notification from your Kamisori E-Commerce platform.
          </p>
        </div>
      `;

      const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

      if (RESEND_API_KEY) {
        try {
          const res = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${RESEND_API_KEY}`,
            },
            body: JSON.stringify({
              from: 'Kamisori Notifications <onboarding@resend.dev>',
              to: [adminEmail],
              subject: subject,
              html: htmlContent,
            }),
          });

          const resData = await res.json();
          if (!res.ok) {
            await supabaseClient.from("trigger_logs").insert({
              level: 'error',
              message: `Email FAILED (Status ${res.status})`,
              order_id,
              details: resData
            });
          } else {
            await supabaseClient.from("trigger_logs").insert({
              level: 'info',
              message: `Email SENT successfully. ID: ${resData.id}`,
              order_id,
              details: { resData }
            });
          }
        } catch (err: any) {
          await supabaseClient.from("trigger_logs").insert({
            level: 'error',
            message: `CRITICAL ERROR: ${err.message || 'Unknown'}`,
            order_id,
            details: { stack: err.stack }
          });
        }
      } else {
        await supabaseClient.from("trigger_logs").insert({
          level: 'warning',
          message: 'Email skipped: RESEND_API_KEY missing',
          order_id
        });
      }

    } else if (notification_type === 'payment_uploaded') {
      const subject = `💳 Payment Slip Uploaded - Order #${order.id.substring(0, 8)}`;

      const htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
          <h2 style="color: #333; border-bottom: 2px solid #333; padding-bottom: 10px;">Payment Slip Received</h2>
          <p>A customer has uploaded a payment slip for their order. Please verify the transaction.</p>
          
          <div style="background: #fdf2f2; padding: 15px; border-radius: 8px; margin-bottom: 20px;">
             <p><strong>Order ID:</strong> #${order.id.substring(0, 8)}</p>
             <p><strong>Amount:</strong> $${order.total_amount}</p>
             <p><strong>Customer:</strong> ${customerEmail}</p>
          </div>

          <a href="${slip_url}" style="display: block; width: 200px; background: #3b82f6; color: white; text-align: center; padding: 12px; border-radius: 6px; text-decoration: none; font-weight: bold; margin: 20px 0;">View Payment Slip</a>
          
          <p style="font-size: 0.9em; color: #666; border-top: 1px solid #eee; padding-top: 10px;">
            Kamisori E-Commerce - Admin Notification
          </p>
        </div>
      `;

      const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
      if (RESEND_API_KEY) {
        await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${RESEND_API_KEY}` },
          body: JSON.stringify({
            from: 'Kamisori Payments <onboarding@resend.dev>',
            to: [adminEmail],
            subject: subject,
            html: htmlContent,
          }),
        });
      }
    }


    return new Response(
      JSON.stringify({ message: "Notification processed successfully" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("Error in notify-admin function:", error);
    return new Response(
      JSON.stringify({ error: error?.message || "An error occurred" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});