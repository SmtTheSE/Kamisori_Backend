import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.5";

// Polyfill for Deno.writeAll and readAll (removed in recent Deno versions)
// This is required for the 'smtp' library to work on Supabase
if (!(Deno as any).writeAll) {
  (Deno as any).writeAll = async (w: any, arr: Uint8Array) => {
    let nwritten = 0;
    while (nwritten < arr.length) {
      const n = await w.write(arr.subarray(nwritten));
      if (n === null) break;
      nwritten += n;
    }
  };
}
if (!(Deno as any).readAll) {
  (Deno as any).readAll = async (r: any) => {
    const buf = new Uint8Array(1024);
    let out = new Uint8Array(0);
    while (true) {
      const n = await r.read(buf);
      if (n === null || n === 0) break;
      const tmp = new Uint8Array(out.length + n);
      tmp.set(out);
      tmp.set(buf.subarray(0, n), out.length);
      out = tmp;
    }
    return out;
  };
}

import { SmtpClient } from "https://deno.land/x/smtp/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Helper function to send email via Gmail SMTP
async function sendGmail(to: string, subject: string, html: string, replyTo?: string, fromName?: string) {
  const SMTP_USER = Deno.env.get("SMTP_USER");
  const SMTP_PASSWORD = Deno.env.get("SMTP_PASSWORD");

  if (!SMTP_USER || !SMTP_PASSWORD) {
    throw new Error("SMTP_USER or SMTP_PASSWORD environment variables are missing");
  }

  const client = new SmtpClient();

  try {
    await client.connectTLS({
      hostname: "smtp.gmail.com",
      port: 465,
      username: SMTP_USER,
      password: SMTP_PASSWORD,
    });

    await client.send({
      from: fromName ? `${fromName} <${SMTP_USER}>` : SMTP_USER,
      to: to,
      replyTo: replyTo,
      subject: subject,
      content: html,
      html: html,
    });

    await client.close();
    return { success: true };
  } catch (error: any) {
    console.error("SMTP Error:", error);
    try { await client.close(); } catch (_) { }
    throw error;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const { order_id, slip_url, notification_type } = payload;

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const adminEmail = Deno.env.get("ADMIN_EMAIL") || "sittminthar005@gmail.com";

    console.log("Notification trigger received:", { order_id, notification_type });

    // Handle TEST PING
    if (notification_type === 'test_ping') {
      await supabaseClient.from("trigger_logs").insert({
        level: 'info',
        message: 'TEST PING STARTED (SMTP)',
        details: { adminEmail, hasSmtpUser: !!Deno.env.get("SMTP_USER") }
      });

      try {
        await sendGmail(
          adminEmail,
          '🔔 Diagnostic Test Email (SMTP)',
          '<h1>It Works!</h1><p>If you see this, your Edge Function and Gmail SMTP configuration are working perfectly.</p>'
        );

        await supabaseClient.from("trigger_logs").insert({
          level: 'info',
          message: 'TEST EMAIL SENT (SMTP)',
          details: { to: adminEmail }
        });

        return new Response(JSON.stringify({ success: true, message: "Test email sent" }), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        });
      } catch (err: any) {
        await supabaseClient.from("trigger_logs").insert({
          level: 'error',
          message: 'TEST EMAIL FAILED (SMTP)',
          details: { error: err.message }
        });
        return new Response(JSON.stringify({ success: false, error: err.message }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        });
      }
    }

    // Normal flow
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
      throw new Error(`Error fetching order: ${orderError?.message || 'Order not found'}`);
    }

    const { data: userData } = await supabaseClient.auth.admin.getUserById(order.user_id);
    const customerEmail = userData?.user?.email || payload.user_email || "N/A";
    const userMeta = userData?.user?.user_metadata || {};
    const deliveryAddress = order.delivery_addresses?.[0] || null;
    const customerFullName = deliveryAddress?.full_name || userMeta.full_name || userMeta.name || customerEmail;

    let subject = "";
    let htmlContent = "";

    if (notification_type === 'new_order') {
      subject = `New Order #${order.id.substring(0, 8)} Received`;

      const itemsHtml = order.order_items.map(item => {
        const variants = [];
        if (item.size) variants.push(`Size: ${item.size}`);
        if (item.color) variants.push(`Color: ${item.color}`);
        const variantsText = variants.length > 0 ? ` (${variants.join(', ')})` : '';
        return `<li>${item.products.name}${variantsText} x${item.quantity} - ${item.price} MMK</li>`;
      }).join('');

      htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
          <h2 style="color: #333; border-bottom: 2px solid #333; padding-bottom: 10px;">New Order Received</h2>
          <div style="margin-bottom: 20px;">
            <p><strong>Order ID:</strong> #${order.id.substring(0, 8)}</p>
            <p><strong>Order Date:</strong> ${new Date(order.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</p>
            <p><strong>Total Amount:</strong> <span style="font-size: 1.2em; color: #2e7d32;">${order.total_amount} MMK</span></p>
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
          <ul style="padding-left: 20px;">
            ${itemsHtml}
          </ul>

          <h3 style="border-bottom: 1px solid #eee; padding-bottom: 5px;">Quick Actions</h3>
          <p style="margin-bottom: 15px; color: #666;">Contact the buyer or update order status:</p>
          <div style="margin-top: 20px;">
            <a href="mailto:${customerEmail}" 
               style="display: inline-block; background-color: #6b7280; color: white; padding: 12px 18px; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 0 10px 10px 0;">
               📧 Reply to Customer
            </a>
            <a href="${Deno.env.get("SUPABASE_URL")}/functions/v1/update-order-status?order_id=${order.id}&status=confirmed&token=${Deno.env.get("ADMIN_SECRET_TOKEN") || 'kamisori-admin-secret'}" 
               style="display: inline-block; background-color: #3b82f6; color: white; padding: 12px 18px; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 0 10px 10px 0;">
               ✅ Confirm Order
            </a>
            <a href="${Deno.env.get("SUPABASE_URL")}/functions/v1/update-order-status?order_id=${order.id}&status=paid&token=${Deno.env.get("ADMIN_SECRET_TOKEN") || 'kamisori-admin-secret'}" 
               style="display: inline-block; background-color: #10b981; color: white; padding: 12px 18px; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 0 10px 10px 0;">
               💰 Mark as Paid
            </a>
          </div>

          <p style="font-size: 0.8em; color: #999; margin-top: 30px; border-top: 1px solid #eee; padding-top: 10px;">
            Kamisori E-Commerce - Admin Notification
          </p>
        </div>
      `;
    } else if (notification_type === 'payment_uploaded') {
      subject = `💳 Payment Slip Uploaded - Order #${order.id.substring(0, 8)}`;
      htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
          <h2 style="color: #333; border-bottom: 2px solid #333; padding-bottom: 10px;">Payment Slip Received</h2>
          <p>A customer has uploaded a payment slip for their order. Please verify the transaction.</p>
          <div style="background: #fdf2f2; padding: 15px; border-radius: 8px; margin-bottom: 20px;">
            <p><strong>Order ID:</strong> #${order.id.substring(0, 8)}</p>
            <p><strong>Amount:</strong> ${order.total_amount} MMK</p>
            <p><strong>Customer:</strong> ${customerFullName} (${customerEmail})</p>
          </div>
          
          <a href="${slip_url}" style="display: block; width: 200px; background: #3b82f6; color: white; text-align: center; padding: 12px; border-radius: 6px; text-decoration: none; font-weight: bold; margin: 20px 0;">View Payment Slip</a>

          <h3 style="border-bottom: 1px solid #eee; padding-bottom: 5px;">Quick Actions</h3>
          <div style="margin-top: 20px;">
            <a href="${Deno.env.get("SUPABASE_URL")}/functions/v1/update-order-status?order_id=${order.id}&status=paid&token=${Deno.env.get("ADMIN_SECRET_TOKEN") || 'kamisori-admin-secret'}" 
               style="display: inline-block; background-color: #10b981; color: white; padding: 12px 18px; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 0 10px 10px 0;">
               ✅ Approve Payment
            </a>
            <a href="${Deno.env.get("SUPABASE_URL")}/functions/v1/update-order-status?order_id=${order.id}&status=cancelled&token=${Deno.env.get("ADMIN_SECRET_TOKEN") || 'kamisori-admin-secret'}" 
               style="display: inline-block; background-color: #ef4444; color: white; padding: 12px 18px; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 0 10px 10px 0;">
               ❌ Reject & Cancel
            </a>
          </div>

          <p style="font-size: 0.8em; color: #999; margin-top: 30px; border-top: 1px solid #eee; padding-top: 10px;">
            Kamisori E-Commerce - Admin Notification
          </p>
        </div>
      `;
    }

    if (subject && htmlContent) {
      try {
        const fromName = notification_type === 'new_order' ? `${customerFullName} (via Kamisori)` : "Kamisori System";
        await sendGmail(adminEmail, subject, htmlContent, customerEmail, fromName);

        await supabaseClient.from("trigger_logs").insert({
          level: 'info',
          message: `Email SENT successfully via SMTP`,
          order_id
        });
      } catch (err: any) {
        await supabaseClient.from("trigger_logs").insert({
          level: 'error',
          message: `SMTP SEND FAILED: ${err.message}`,
          order_id,
          details: { error: err.message }
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