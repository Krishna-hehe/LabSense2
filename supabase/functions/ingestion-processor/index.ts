import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const LLAMAPARSE_BASE_URL =
  Deno.env.get("LLAMAPARSE_BASE_URL") ?? "https://api.cloud.llamaindex.ai";
const GEMINI_CHAT_MODEL =
  Deno.env.get("GEMINI_CHAT_MODEL") ?? "gemini-2.0-flash-lite";
const GEMINI_BASE_URL =
  Deno.env.get("GEMINI_BASE_URL") ??
  "https://generativelanguage.googleapis.com/v1beta";

const LLAMA_PARSE_INSTRUCTION =
  "This is a medical laboratory report. Preserve all tables exactly as structured using markdown table syntax. Keep every test name, numeric value, unit, and reference range on the same row. Do not summarize, interpret, or omit any values. If a value is flagged as HIGH or LOW, preserve that flag.";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const processorToken = Deno.env.get("INGESTION_PROCESSOR_TOKEN") ?? "";
    if (!processorToken) {
      return jsonResponse(
        { error: "INGESTION_PROCESSOR_TOKEN is not configured" },
        500,
      );
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const incomingToken = authHeader.replace("Bearer ", "").trim();
    if (incomingToken !== processorToken) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    const jobId = (body?.jobId ?? "").toString().trim();
    const userId = (body?.userId ?? "").toString().trim();
    const storagePath = (body?.storagePath ?? "").toString().trim();
    const fileName = (body?.fileName ?? "lab_report.pdf").toString().trim();
    const fileMimeType = (body?.fileMimeType ?? "application/pdf")
      .toString()
      .trim();

    if (!jobId || !userId || !storagePath) {
      return jsonResponse(
        { error: "jobId, userId, and storagePath are required" },
        400,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    const { data: fileBlob, error: downloadError } = await adminClient.storage
      .from("lab-reports")
      .download(storagePath);
    if (downloadError || !fileBlob) {
      throw new Error(
        `Failed to download source file from storage: ${downloadError?.message ?? "Unknown"}`,
      );
    }

    const fileBytes = new Uint8Array(await fileBlob.arrayBuffer());

    const llamaKey = Deno.env.get("LLAMAPARSE_API_KEY") ?? "";
    const geminiApiKey =
      Deno.env.get("GEMINI_API_KEY") ?? Deno.env.get("XAI_API_KEY") ?? "";
    if (!geminiApiKey) {
      throw new Error("GEMINI_API_KEY is not configured");
    }

    let markdown = "";
    if (fileMimeType.toLowerCase().includes("pdf")) {
      if (!llamaKey) {
        throw new Error(
          "LLAMAPARSE_API_KEY is required for PDF ingestion processor",
        );
      }
      markdown = await parsePdfWithLlamaParse(fileBytes, fileName, llamaKey);
    } else {
      throw new Error(
        "Image ingestion is not enabled in current AI mode. Upload PDF reports.",
      );
    }

    const parsedData = await extractStructuredDataFromMarkdown(markdown, geminiApiKey);
    parsedData["source_markdown"] = markdown;
    parsedData["storage_path"] = storagePath;
    parsedData["job_id"] = jobId;

    return jsonResponse({
      status: "done",
      parsedData,
      message: "Ingestion processor completed successfully",
    });
  } catch (error) {
    return jsonResponse(
      {
        status: "error",
        message: (error as Error).message || "Processor failed",
      },
      400,
    );
  }
});

async function parsePdfWithLlamaParse(
  fileBytes: Uint8Array,
  fileName: string,
  apiKey: string,
): Promise<string> {
  const form = new FormData();
  form.set("result_type", "markdown");
  form.set("premium_mode", "true");
  form.set("parsing_instruction", LLAMA_PARSE_INSTRUCTION);
  form.set(
    "file",
    new Blob([fileBytes], { type: "application/pdf" }),
    fileName || "lab_report.pdf",
  );

  const uploadResponse = await fetch(`${LLAMAPARSE_BASE_URL}/api/v1/parsing/upload`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
    },
    body: form,
  });

  if (!uploadResponse.ok) {
    throw new Error(
      `LlamaParse upload failed (${uploadResponse.status}): ${await uploadResponse.text()}`,
    );
  }

  const uploadJson = await safeJson(uploadResponse);
  const immediate = extractMarkdown(uploadJson);
  if (immediate) return immediate;

  const jobId = extractJobId(uploadJson);
  if (!jobId) {
    throw new Error("LlamaParse upload did not return a job id");
  }

  for (let i = 0; i < 45; i++) {
    const statusResponse = await fetch(
      `${LLAMAPARSE_BASE_URL}/api/v1/parsing/job/${jobId}`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          Accept: "application/json",
        },
      },
    );

    if (!statusResponse.ok) {
      throw new Error(
        `LlamaParse status failed (${statusResponse.status}): ${await statusResponse.text()}`,
      );
    }

    const statusJson = await safeJson(statusResponse);
    const inline = extractMarkdown(statusJson);
    if (inline) return inline;

    const status = extractStatus(statusJson).toUpperCase();
    if (status === "ERROR" || status === "FAILED") {
      throw new Error(`LlamaParse job failed: ${jobId}`);
    }

    if (status === "SUCCESS" || status === "COMPLETED" || status === "DONE") {
      const markdown = await fetchLlamaParseResultMarkdown(jobId, apiKey);
      if (!markdown) {
        throw new Error("LlamaParse completed but markdown is empty");
      }
      return markdown;
    }

    await delay(2000);
  }

  throw new Error("LlamaParse timeout while waiting for markdown");
}

async function fetchLlamaParseResultMarkdown(
  jobId: string,
  apiKey: string,
): Promise<string> {
  const endpoints = [
    `${LLAMAPARSE_BASE_URL}/api/v1/parsing/job/${jobId}/result/markdown`,
    `${LLAMAPARSE_BASE_URL}/api/v1/parsing/job/${jobId}/result?result_type=markdown`,
    `${LLAMAPARSE_BASE_URL}/api/v1/parsing/job/${jobId}/result`,
  ];

  for (const endpoint of endpoints) {
    const response = await fetch(endpoint, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/json",
      },
    });
    if (!response.ok) continue;

    const bodyText = await response.text();
    const json = safeJsonString(bodyText);
    const markdownFromJson = extractMarkdown(json);
    if (markdownFromJson) return markdownFromJson;

    const trimmed = bodyText.trim();
    if (trimmed && !trimmed.startsWith("{") && !trimmed.startsWith("[")) {
      return trimmed;
    }
  }

  return "";
}

async function extractStructuredDataFromMarkdown(
  markdown: string,
  geminiApiKey: string,
): Promise<Record<string, unknown>> {
  const prompt = `
You are an expert Medical Data Extractor.
You are given a medical lab report in markdown.
Extract strict JSON with fields:
- lab_provider
- lab_name
- date (YYYY-MM-DD)
- test_results[] with test_name, original_name, loinc_code, result_value, unit, reference_range, status.
If status is missing, infer from result_value and reference_range.
Return JSON only.

MARKDOWN:
${markdown}
`;

  const text = await callGeminiGenerateContent({
    apiKey: geminiApiKey,
    model: GEMINI_CHAT_MODEL,
    prompt,
  });

  const jsonText = extractJsonBlock(text);
  const parsed = safeJsonString(jsonText);
  if (!parsed || typeof parsed !== "object") {
    throw new Error("Gemini extraction did not return JSON object");
  }

  const normalized = normalizeParsedData(parsed as Record<string, unknown>);
  if (!Array.isArray(normalized.test_results)) {
    throw new Error("Parsed data missing test_results array");
  }
  return normalized;
}

async function callGeminiGenerateContent(args: {
  apiKey: string;
  model: string;
  prompt: string;
}): Promise<string> {
  const normalizedBase = GEMINI_BASE_URL.endsWith("/")
    ? GEMINI_BASE_URL.slice(0, -1)
    : GEMINI_BASE_URL;
  const baseWithVersion = normalizedBase.includes("/v1beta")
    ? normalizedBase
    : `${normalizedBase}/v1beta`;
  const modelName = args.model.replace(/^models\//, "").trim();
  const endpoint = `${baseWithVersion}/models/${encodeURIComponent(modelName)}:generateContent?key=${encodeURIComponent(args.apiKey)}`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    body: JSON.stringify({
      systemInstruction: {
        parts: [
          {
            text:
              "You are a medical extraction assistant. Return only required JSON.",
          },
        ],
      },
      contents: [
        {
          role: "user",
          parts: [{ text: args.prompt }],
        },
      ],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 1200,
      },
    }),
  });

  if (!response.ok) {
    throw new Error(
      `Gemini call failed (${response.status}): ${await response.text()}`,
    );
  }

  const json = await safeJson(response);
  const candidates = (json?.candidates ?? []) as Array<Record<string, unknown>>;
  const first = candidates[0] ?? {};
  const content = (first["content"] ?? {}) as Record<string, unknown>;
  const parts = Array.isArray(content["parts"])
    ? (content["parts"] as Array<Record<string, unknown>>)
    : [];
  const text = parts
    .map((part) => (part["text"] ?? "").toString())
    .join("")
    .trim();
  if (!text) {
    throw new Error("Gemini returned empty content");
  }

  return text;
}

function normalizeParsedData(
  parsed: Record<string, unknown>,
): Record<string, unknown> {
  const normalized: Record<string, unknown> = { ...parsed };
  const results = Array.isArray(parsed["test_results"])
    ? parsed["test_results"] as Array<Record<string, unknown>>
    : [];

  normalized["test_results"] = results.map((raw) => {
    const item: Record<string, unknown> = { ...raw };
    item["test_name"] = (item["test_name"] ?? item["name"] ?? "").toString();
    item["original_name"] = (item["original_name"] ?? item["test_name"] ?? "")
      .toString();
    item["result_value"] = (
      item["result_value"] ?? item["result"] ?? ""
    ).toString();
    item["unit"] = (item["unit"] ?? "").toString();
    item["reference_range"] = (
      item["reference_range"] ?? item["reference"] ?? ""
    ).toString();
    item["status"] = (item["status"] ?? "Normal").toString();
    item["loinc_code"] = (item["loinc_code"] ?? "").toString();
    return item;
  });

  return normalized;
}

function extractJobId(payload: Record<string, unknown>): string {
  const direct = payload["job_id"] ?? payload["jobId"] ?? payload["id"];
  if (direct) return direct.toString();

  const nested = payload["data"] as Record<string, unknown> | undefined;
  if (nested) {
    const v = nested["job_id"] ?? nested["jobId"] ?? nested["id"];
    if (v) return v.toString();
  }
  return "";
}

function extractStatus(payload: Record<string, unknown>): string {
  const direct = payload["status"];
  if (direct) return direct.toString();

  const nested = payload["data"] as Record<string, unknown> | undefined;
  if (nested && nested["status"]) return nested["status"].toString();
  return "";
}

function extractMarkdown(payload: Record<string, unknown>): string {
  const candidates = [
    payload["markdown"],
    payload["markdown_full"],
    payload["text"],
    payload["text_full"],
    ((payload["result"] as Record<string, unknown> | undefined) ?? {})["markdown"],
    ((payload["data"] as Record<string, unknown> | undefined) ?? {})["markdown"],
    ((payload["data"] as Record<string, unknown> | undefined) ?? {})["markdown_full"],
  ];

  for (const c of candidates) {
    if (typeof c === "string" && c.trim().length > 0) {
      return c.trim();
    }
  }
  return "";
}

function extractJsonBlock(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return "{}";

  const startObj = trimmed.indexOf("{");
  const endObj = trimmed.lastIndexOf("}");
  if (startObj >= 0 && endObj > startObj) {
    return trimmed.slice(startObj, endObj + 1);
  }
  return trimmed;
}

async function delay(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function safeJson(response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  return safeJsonString(text);
}

function safeJsonString(text: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object") {
      return parsed as Record<string, unknown>;
    }
    return {};
  } catch {
    return {};
  }
}

function jsonResponse(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}
