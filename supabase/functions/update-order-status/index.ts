import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.5";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
    // Handle CORS
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const url = new URL(req.url);
        const orderId = url.searchParams.get("order_id");
        const status = url.searchParams.get("status");
        const token = url.searchParams.get("token");

        const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
        const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
        const ADMIN_SECRET = Deno.env.get("ADMIN_SECRET_TOKEN") || "kamisori-admin-secret"; // Fallback for simplicity, but should be set

        if (!orderId || !status || !token) {
            return new Response("Missing parameters", { status: 400 });
        }

        if (token !== ADMIN_SECRET) {
            return new Response("Unauthorized", { status: 401 });
        }

        const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

        // Update order status
        const { data, error } = await supabaseClient
            .from("orders")
            .update({ status: status })
            .eq("id", orderId)
            .select();

        if (error) {
            throw error;
        }

        // Return a nice HTML response
        const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <title>Order Updated</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background-color: #f4f7f6; }
          .container { text-align: center; padding: 40px; background: white; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); max-width: 400px; width: 100%; }
          .icon { font-size: 64px; margin-bottom: 20px; }
          h1 { color: #2d3748; margin-bottom: 10px; font-size: 24px; }
          p { color: #718096; margin-bottom: 30px; line-height: 1.5; }
          .status { display: inline-block; padding: 6px 12px; background: #ebf8ff; color: #2b6cb0; border-radius: 9999px; font-weight: bold; text-transform: uppercase; font-size: 14px; }
          .button { display: inline-block; padding: 12px 24px; background: #3182ce; color: white; text-decoration: none; border-radius: 6px; font-weight: bold; transition: background 0.2s; }
          .button:hover { background: #2b6cb0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="icon">✅</div>
          <h1>Status Updated!</h1>
          <p>Order <strong>#${orderId.substring(0, 8)}</strong> has been successfully updated to:</p>
          <p><span class="status">${status}</span></p>
          <p>The customer has been notified automatically.</p>
          <a href="#" onclick="window.close()" class="button">Close Window</a>
        </div>
      </body>
      </html>
    `;

        return new Response(html, {
            headers: { ...corsHeaders, "Content-Type": "text/html" },
        });
    } catch (error: any) {
        console.error("Error updating order status:", error);
        return new Response(`Error: ${error.message}`, { status: 500 });
    }
});
