import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const MAX_UPLOAD_BYTES = 10 * 1024 * 1024; // 10MB
const ALLOWED_MIME_TYPES = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
]);

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 405,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const authHeader = req.headers.get("Authorization") ?? "";
    const authedClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await authedClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "User not authenticated" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const body = await req.json();
    const fileName = (body?.fileName ?? "").toString().trim();
    const mimeType = (body?.mimeType ?? "application/pdf").toString().trim();
    const fileSize = Number(body?.fileSize ?? 0);

    if (!fileName) {
      return new Response(JSON.stringify({ error: "fileName is required" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }
    if (!ALLOWED_MIME_TYPES.has(mimeType)) {
      return new Response(JSON.stringify({ error: "Unsupported file type" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 415,
      });
    }
    if (!Number.isFinite(fileSize) || fileSize <= 0 || fileSize > MAX_UPLOAD_BYTES) {
      return new Response(
        JSON.stringify({ error: `fileSize must be between 1 and ${MAX_UPLOAD_BYTES} bytes` }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 413,
        },
      );
    }

    const normalizedFileName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
    const storagePath = `${user.id}/${Date.now()}_${normalizedFileName}`;

    const adminClient = createClient(supabaseUrl, supabaseServiceKey);
    const { data, error } = await adminClient.storage
      .from("lab-reports")
      .createSignedUploadUrl(storagePath);

    if (error) {
      throw error;
    }

    return new Response(
      JSON.stringify({
        success: true,
        path: storagePath,
        mimeType,
        signedUrl: data?.signedUrl,
        token: data?.token,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error?.message ?? "Failed to create upload url" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});
