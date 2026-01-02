import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.5";

// Polyfill for Deno.writeAll and readAll (required for 'smtp' library)
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
async function sendGmail(to: string, subject: string, html: string, fromName?: string) {
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
    const { order_id, new_status } = payload;

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get order details including customer info
    const { data: order, error: orderError } = await supabaseClient
      .from("orders")
      .select(`
        id,
        total_amount,
        payment_method,
        status,
        created_at,
        user_id,
        delivery_addresses (
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

    // Get customer email from Auth
    const { data: userData } = await supabaseClient.auth.admin.getUserById(order.user_id);
    const customerEmail = userData?.user?.email;
    const customerName = order.delivery_addresses?.[0]?.full_name || userData?.user?.user_metadata?.full_name || "Customer";

    if (!customerEmail) {
      throw new Error("Customer email not found");
    }

    let subject = "";
    let messageHeader = "";
    let messageBody = "";
    let statusColor = "#3b82f6";

    switch (new_status) {
      case "received":
        subject = `Order Received - Kamisori #${order.id.substring(0, 8)}`;
        messageHeader = "Thank you for your order!";
        messageBody = "We have received your order and it is currently being reviewed by our team. You will receive a confirmation email once your order has been processed.";
        statusColor = "#6b7280";
        break;
      case "confirmed":
        subject = `Order Confirmation - Kamisori #${order.id.substring(0, 8)}`;
        messageHeader = "Your order has been confirmed!";
        messageBody = "We are pleased to inform you that your order has been received and confirmed. Our team is now preparing it for shipment.";
        statusColor = "#3b82f6";
        break;
      case "paid":
        subject = `Payment Received - Kamisori #${order.id.substring(0, 8)}`;
        messageHeader = "Thank you for your payment!";
        messageBody = "We have successfully verified your payment. Your order is now being processed and will be shipped shortly.";
        statusColor = "#10b981";
        break;
      case "shipped":
        subject = `Your Order is on its way - Kamisori #${order.id.substring(0, 8)}`;
        messageHeader = "Great news! Your order has shipped.";
        messageBody = "Your package is currently in transit. You will receive further updates once it reaches your destination.";
        statusColor = "#f59e0b";
        break;
      case "cancelled":
        subject = `Order Cancellation - Kamisori #${order.id.substring(0, 8)}`;
        messageHeader = "Your order has been cancelled.";
        messageBody = "We regret to inform you that your order has been cancelled. If you have already made a payment, our support team will contact you regarding the refund process.";
        statusColor = "#ef4444";
        break;
      case "delivered":
        subject = `Your order has been delivered - Kamisori #${order.id.substring(0, 8)}`;
        messageHeader = "Order Delivered!";
        messageBody = "Your order has been successfully delivered. We hope you enjoy your purchase! Thank you for shopping with Kamisori.";
        statusColor = "#10b981";
        break;
      default:
        return new Response(JSON.stringify({ message: "No email template for this status" }), { status: 200 });
    }

    const htmlContent = `
      <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; padding: 0; border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden;">
        <div style="background-color: #111827; padding: 30px; text-align: center;">
          <h1 style="color: #ffffff; margin: 0; font-size: 24px; letter-spacing: 1px;">KAMISORI</h1>
        </div>
        <div style="padding: 40px 30px; background-color: #ffffff;">
          <h2 style="color: #111827; margin-top: 0; margin-bottom: 20px; font-size: 20px;">Dear ${customerName},</h2>
          <p style="color: #374151; font-size: 16px; line-height: 1.6; margin-bottom: 25px;">
            ${messageBody}
          </p>
          
          <div style="background-color: #f9fafb; border-radius: 8px; padding: 25px; margin-bottom: 30px;">
            <h3 style="color: #111827; margin-top: 0; margin-bottom: 15px; font-size: 16px; text-transform: uppercase; letter-spacing: 0.5px;">Order Details</h3>
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Order ID:</td>
                <td style="padding: 8px 0; color: #111827; font-size: 14px; text-align: right; font-weight: bold;">#${order.id.substring(0, 8)}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Status:</td>
                <td style="padding: 8px 0; text-align: right;">
                  <span style="background-color: ${statusColor}; color: #ffffff; padding: 4px 12px; border-radius: 9999px; font-size: 12px; font-weight: bold; text-transform: uppercase;">${new_status}</span>
                </td>
              </tr>
              <tr>
                <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Total Amount:</td>
                <td style="padding: 8px 0; color: #111827; font-size: 14px; text-align: right; font-weight: bold;">${order.total_amount} MMK</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; color: #6b7280; font-size: 14px;">Date:</td>
                <td style="padding: 8px 0; color: #111827; font-size: 14px; text-align: right;">${new Date(order.created_at).toLocaleDateString()}</td>
              </tr>
            </table>
          </div>

          <p style="color: #374151; font-size: 16px; line-height: 1.6; margin-bottom: 25px;">
            If you have any questions regarding your order, please do not hesitate to contact our support team.
          </p>
          <p style="color: #374151; font-size: 16px; line-height: 1.6; margin-bottom: 10px;">
            Best regards,<br>
            <strong>The Kamisori Team</strong>
          </p>
        </div>
        <div style="background-color: #f3f4f6; padding: 20px; text-align: center; border-top: 1px solid #e5e7eb;">
          <p style="color: #9ca3af; font-size: 12px; margin: 0;">&copy; ${new Date().getFullYear()} Kamisori E-Commerce. All rights reserved.</p>
        </div>
      </div>
    `;

    await sendGmail(customerEmail, subject, htmlContent, "The Kamisori Team");

    // Log the notification
    await supabaseClient.from("customer_notifications").insert({
      order_id,
      notification_type: `order_${new_status}`,
      message: `Order ${order_id} status updated to ${new_status}`,
      recipient_email: customerEmail,
    });

    return new Response(JSON.stringify({ success: true, message: "Customer notification sent" }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  } catch (error: any) {
    console.error("Error in notify-customer function:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});