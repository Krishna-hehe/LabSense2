import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const MAX_UPLOAD_BYTES = 10 * 1024 * 1024; // 10MB
const ALLOWED_MIME_TYPES = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
]);

function isAllowedBinary(mimeType: string, bytes: Uint8Array): boolean {
  if (bytes.length < 4) return false;

  if (mimeType === "application/pdf") {
    return bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46; // %PDF
  }

  if (mimeType === "image/png") {
    return bytes.length >= 8 &&
      bytes[0] === 0x89 &&
      bytes[1] === 0x50 &&
      bytes[2] === 0x4E &&
      bytes[3] === 0x47;
  }

  if (mimeType === "image/jpeg") {
    return bytes[0] === 0xFF && bytes[1] === 0xD8;
  }

  return false;
}

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
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

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

    let storagePath = "";
    let fileName = "";
    let mimeType = "application/pdf";
    let sourceDocId: string | null = null;
    let payload: Record<string, unknown> = {};

    const contentType = req.headers.get("Content-Type") ?? "";
    if (contentType.includes("multipart/form-data")) {
      const form = await req.formData();
      const file = form.get("file");
      const declaredSize = Number(form.get("fileSize") ?? 0);
      const declaredName = (form.get("fileName") ?? "").toString().trim();
      const declaredMimeType = (form.get("mimeType") ?? "").toString().trim();

      if (!(file instanceof File)) {
        return new Response(JSON.stringify({ error: "file is required" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        });
      }

      fileName = (file.name || "lab_report.pdf").replace(/[^a-zA-Z0-9._-]/g, "_");
      mimeType = file.type || "application/pdf";
      if (declaredName && declaredName !== file.name) {
        return new Response(JSON.stringify({ error: "fileName does not match uploaded file" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        });
      }
      if (declaredMimeType && declaredMimeType !== mimeType) {
        return new Response(JSON.stringify({ error: "mimeType does not match uploaded file" }), {
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
      storagePath = `${user.id}/${Date.now()}_${fileName}`;

      const bytes = new Uint8Array(await file.arrayBuffer());
      if (bytes.length === 0 || bytes.length > MAX_UPLOAD_BYTES) {
        return new Response(
          JSON.stringify({ error: `File size must be between 1 and ${MAX_UPLOAD_BYTES} bytes` }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 413,
          },
        );
      }
      if (Number.isFinite(declaredSize) && declaredSize > 0 && declaredSize !== bytes.length) {
        return new Response(JSON.stringify({ error: "fileSize mismatch for uploaded file" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        });
      }
      if (!isAllowedBinary(mimeType, bytes)) {
        return new Response(JSON.stringify({ error: "Invalid file signature for provided MIME type" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        });
      }

      const { error: uploadError } = await adminClient.storage
        .from("lab-reports")
        .upload(storagePath, bytes, {
          upsert: false,
          contentType: mimeType,
          cacheControl: "3600",
        });

      if (uploadError) {
        throw uploadError;
      }
    } else {
      const body = await req.json();
      storagePath = (body?.storagePath ?? "").toString().trim();
      fileName = (body?.fileName ?? "lab_report.pdf").toString().trim();
      mimeType = (body?.mimeType ?? "application/pdf").toString().trim();
      const fileSize = Number(body?.fileSize ?? 0);
      sourceDocId = (body?.sourceDocId ?? "").toString().trim() || null;
      payload =
        body?.payload && typeof body.payload === "object"
          ? (body.payload as Record<string, unknown>)
          : {};

      if (!storagePath) {
        return new Response(
          JSON.stringify({
            error: "storagePath is required for JSON requests",
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 400,
          },
        );
      }

      if (!storagePath.startsWith(`${user.id}/`)) {
        return new Response(
          JSON.stringify({
            error:
              "storagePath must belong to the authenticated user namespace",
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 403,
          },
        );
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
    }

    const { data: insertedJob, error: jobError } = await adminClient
      .from("ingestion_jobs")
      .insert({
        user_id: user.id,
        storage_path: storagePath,
        file_name: fileName || "lab_report.pdf",
        file_mime_type: mimeType || "application/pdf",
        source_doc_id: sourceDocId,
        status: "queued",
        stage: "queued",
        progress: 5,
        payload,
      })
      .select("id, status, stage, progress, storage_path, file_name, file_mime_type, created_at")
      .single();

    if (jobError) {
      throw jobError;
    }

    return new Response(
      JSON.stringify({
        success: true,
        jobId: insertedJob.id,
        status: insertedJob.status,
        stage: insertedJob.stage,
        progress: insertedJob.progress,
        storagePath: insertedJob.storage_path,
        fileName: insertedJob.file_name,
        fileMimeType: insertedJob.file_mime_type,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error?.message ?? "Ingestion request failed" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});
