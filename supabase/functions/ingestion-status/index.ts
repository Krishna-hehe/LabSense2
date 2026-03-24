import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST" && req.method !== "GET") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 405,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

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

    let jobId = "";
    if (req.method === "POST") {
      const body = await req.json();
      jobId = (body?.jobId ?? "").toString().trim();
    } else {
      const url = new URL(req.url);
      jobId = (url.searchParams.get("jobId") ?? "").trim();
    }

    if (!jobId) {
      return new Response(JSON.stringify({ error: "jobId is required" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    const { data: job, error: jobError } = await authedClient
      .from("ingestion_jobs")
      .select(
        "id, status, stage, progress, attempts, max_attempts, last_error, parsed_data, storage_path, source_doc_id, created_at, updated_at, completed_at",
      )
      .eq("id", jobId)
      .eq("user_id", user.id)
      .single();

    if (jobError || !job) {
      return new Response(JSON.stringify({ error: "Job not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    const message = buildStatusMessage(job.status, job.stage, job.last_error);

    return new Response(
      JSON.stringify({
        jobId: job.id,
        status: job.status,
        stage: job.stage,
        progress: job.progress,
        attempts: job.attempts,
        maxAttempts: job.max_attempts,
        message,
        parsedData: job.parsed_data,
        storagePath: job.storage_path,
        sourceDocId: job.source_doc_id,
        completedAt: job.completed_at,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error?.message ?? "Failed to retrieve ingestion status",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});

function buildStatusMessage(status: string, stage: string, lastError?: string) {
  if (status === "queued") return "Queued for processing.";
  if (status === "processing") return `Processing stage: ${stage}.`;
  if (status === "done") return "Ingestion completed successfully.";
  if (status === "dead_letter") return `Moved to dead-letter: ${lastError ?? "Unknown error"}`;
  if (status === "error") return `Processing failed: ${lastError ?? "Unknown error"}`;
  return `Status: ${status}`;
}
