import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

type IngestionJob = {
  id: string;
  user_id: string;
  storage_path: string;
  file_name: string;
  file_mime_type: string | null;
  status: string;
  stage: string;
  progress: number;
  attempts: number;
  max_attempts: number;
  payload: Record<string, unknown> | null;
};

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

    const configuredSecret = Deno.env.get("INGESTION_CRON_SECRET") ?? "";
    const incomingSecret = req.headers.get("x-cron-secret") ?? "";
    if (!configuredSecret) {
      return new Response(
        JSON.stringify({ error: "INGESTION_CRON_SECRET is not configured" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        },
      );
    }
    if (configuredSecret !== incomingSecret) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const processorUrl =
      Deno.env.get("INGESTION_PROCESSOR_URL") ??
      `${supabaseUrl}/functions/v1/ingestion-processor`;
    const processorToken = Deno.env.get("INGESTION_PROCESSOR_TOKEN") ?? "";
    if (!processorToken) {
      return new Response(
        JSON.stringify({ error: "INGESTION_PROCESSOR_TOKEN is not configured" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        },
      );
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceKey);
    const body = await safeJson(req);
    const requestedBatch = Number(body?.batchSize ?? 10);
    const batchSize = Math.max(1, Math.min(requestedBatch || 10, 25));

    const { data: fetchedJobs, error: jobFetchError } = await adminClient
      .from("ingestion_jobs")
      .select(
        "id, user_id, storage_path, file_name, file_mime_type, status, stage, progress, attempts, max_attempts, payload",
      )
      .in("status", ["queued", "error"])
      .order("created_at", { ascending: true })
      .limit(batchSize * 2);

    if (jobFetchError) throw jobFetchError;

    const jobs = (fetchedJobs ?? [])
      .map((row) => row as IngestionJob)
      .filter((job) => job.attempts < job.max_attempts)
      .slice(0, batchSize);

    let claimed = 0;
    let completed = 0;
    let failed = 0;
    let deadLettered = 0;

    for (const job of jobs) {
      const { data: claimedJob, error: claimError } = await adminClient
        .from("ingestion_jobs")
        .update({
          status: "processing",
          stage: "processing",
          progress: 15,
          started_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          last_error: null,
        })
        .eq("id", job.id)
        .eq("status", job.status)
        .select(
          "id, user_id, storage_path, file_name, file_mime_type, status, stage, progress, attempts, max_attempts, payload",
        )
        .single();

      if (claimError || !claimedJob) {
        continue;
      }
      claimed += 1;

      try {
        if (!processorUrl) {
          throw new Error("INGESTION_PROCESSOR_URL is not configured");
        }

        const processorResponse = await fetch(processorUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${processorToken}`,
          },
          body: JSON.stringify({
            jobId: claimedJob.id,
            userId: claimedJob.user_id,
            storagePath: claimedJob.storage_path,
            fileName: claimedJob.file_name,
            fileMimeType: claimedJob.file_mime_type,
            payload: claimedJob.payload ?? {},
          }),
        });

        if (!processorResponse.ok) {
          throw new Error(
            `Processor error (${processorResponse.status}): ${await processorResponse.text()}`,
          );
        }

        const processorData = await processorResponse.json();
        const processorStatus = (processorData?.status ?? "").toString();

        if (processorStatus === "done") {
          const { error: doneError } = await adminClient
            .from("ingestion_jobs")
            .update({
              status: "done",
              stage: "done",
              progress: 100,
              parsed_data: processorData?.parsedData ?? null,
              completed_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
              last_error: null,
            })
            .eq("id", claimedJob.id);
          if (doneError) throw doneError;
          completed += 1;
        } else if (
          processorStatus === "processing" ||
          processorStatus === "extracting" ||
          processorStatus === "indexing"
        ) {
          const { error: updateError } = await adminClient
            .from("ingestion_jobs")
            .update({
              status: "queued",
              stage: processorStatus,
              progress: Number(processorData?.progress ?? 60),
              updated_at: new Date().toISOString(),
            })
            .eq("id", claimedJob.id);
          if (updateError) throw updateError;
        } else {
          throw new Error(
            processorData?.message ??
              "Processor did not return a supported status",
          );
        }
      } catch (error) {
        const message = (error as Error).message || "Unknown ingestion error";
        const nextAttempts = claimedJob.attempts + 1;
        const hitMaxAttempts = nextAttempts >= claimedJob.max_attempts;

        if (hitMaxAttempts) {
          const { error: deadLetterInsertError } = await adminClient
            .from("ingestion_dead_letters")
            .insert({
              job_id: claimedJob.id,
              user_id: claimedJob.user_id,
              storage_path: claimedJob.storage_path,
              file_name: claimedJob.file_name,
              attempts: nextAttempts,
              reason: message,
              payload: claimedJob.payload ?? {},
            });
          if (deadLetterInsertError) throw deadLetterInsertError;

          const { error: markDeadError } = await adminClient
            .from("ingestion_jobs")
            .update({
              status: "dead_letter",
              stage: "dead_letter",
              progress: 100,
              attempts: nextAttempts,
              last_error: message,
              completed_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            })
            .eq("id", claimedJob.id);
          if (markDeadError) throw markDeadError;
          deadLettered += 1;
        } else {
          const { error: markError } = await adminClient
            .from("ingestion_jobs")
            .update({
              status: "error",
              stage: "retry_wait",
              progress: 0,
              attempts: nextAttempts,
              last_error: message,
              updated_at: new Date().toISOString(),
            })
            .eq("id", claimedJob.id);
          if (markError) throw markError;
          failed += 1;
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        scanned: jobs.length,
        claimed,
        completed,
        failed,
        deadLettered,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error?.message ?? "Failed to process jobs" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});

async function safeJson(req: Request) {
  try {
    return await req.json();
  } catch {
    return {};
  }
}
