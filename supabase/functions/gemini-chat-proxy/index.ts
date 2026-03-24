import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    // Best-effort user validation. Do not hard-fail on missing/expired tokens.
    await userClient.auth.getUser();

    const geminiApiKey =
      (Deno.env.get("GEMINI_API_KEY") ?? Deno.env.get("XAI_API_KEY") ?? "").trim();
    const geminiBaseUrl = (
      Deno.env.get("GEMINI_BASE_URL") ??
      Deno.env.get("XAI_BASE_URL") ??
      "https://generativelanguage.googleapis.com/v1beta"
    ).trim();

    if (!geminiApiKey) {
      return jsonResponse({ error: "GEMINI_API_KEY is not configured" }, 500);
    }
    if (!geminiBaseUrl) {
      return jsonResponse({ error: "GEMINI_BASE_URL is not configured" }, 500);
    }

    const body = await req.json();
    const configuredModel = (
      Deno.env.get("GEMINI_CHAT_MODEL") ??
      Deno.env.get("XAI_CHAT_MODEL") ??
      "gemini-flash-lite-latest"
    )
      .toString()
      .replace(/^models\//, "")
      .trim();
    const requestedModel = (body?.model ?? "")
      .toString()
      .replace(/^models\//, "")
      .trim();
    // Force server-side model choice so stale/older clients can't override
    // to expensive or rate-limited models.
    const model = configuredModel.isNotEmpty ? configuredModel : requestedModel;
    const prompt = (body?.prompt ?? "").toString().trim();
    const systemPrompt = (
      body?.systemPrompt ?? "You are a concise, evidence-grounded medical assistant."
    ).toString();
    const temperature = Number(body?.temperature ?? 0.2);
    const maxTokens = Number(body?.maxTokens ?? 700);

    if (!prompt) {
      return jsonResponse({ error: "prompt is required" }, 400);
    }

    const trimmedBase = geminiBaseUrl.endsWith("/")
      ? geminiBaseUrl.slice(0, -1)
      : geminiBaseUrl;
    const baseWithoutVersion = trimmedBase.replace(/\/v1beta$/, "");
    const sanitizedModel = model;
    if (!sanitizedModel) {
      return jsonResponse({ error: "model is required" }, 400);
    }
    const fallbackModel = (
      Deno.env.get("GEMINI_FALLBACK_MODEL") ?? "gemini-flash-lite-latest"
    ).replace(/^models\//, "").trim();
    const clampedMaxTokens = Number.isFinite(maxTokens)
      ? Math.min(Math.max(Math.trunc(maxTokens), 32), 1200)
      : 700;

    let { response: geminiResponse, rawBody } = await callGeminiGenerate({
      baseWithoutVersion,
      apiKey: geminiApiKey,
      model: sanitizedModel,
      prompt,
      systemPrompt,
      temperature,
      maxOutputTokens: clampedMaxTokens,
    });

    if (isRateLimitedResponse(geminiResponse.status, rawBody)) {
      await delayMs(1200);
      ({ response: geminiResponse, rawBody } = await callGeminiGenerate({
        baseWithoutVersion,
        apiKey: geminiApiKey,
        model: sanitizedModel,
        prompt: prompt.length > 5000 ? prompt.slice(0, 5000) : prompt,
        systemPrompt: systemPrompt.length > 1200
          ? systemPrompt.slice(0, 1200)
          : systemPrompt,
        temperature: Math.min(Math.max(temperature, 0), 0.2),
        maxOutputTokens: Math.min(clampedMaxTokens, 256),
      }));
    }

    if (
      !geminiResponse.ok &&
      isRateLimitedResponse(geminiResponse.status, rawBody) &&
      fallbackModel &&
      fallbackModel !== sanitizedModel
    ) {
      ({ response: geminiResponse, rawBody } = await callGeminiGenerate({
        baseWithoutVersion,
        apiKey: geminiApiKey,
        model: fallbackModel,
        prompt: prompt.length > 4000 ? prompt.slice(0, 4000) : prompt,
        systemPrompt: systemPrompt.length > 1000
          ? systemPrompt.slice(0, 1000)
          : systemPrompt,
        temperature: Math.min(Math.max(temperature, 0), 0.2),
        maxOutputTokens: Math.min(clampedMaxTokens, 256),
      }));
    }

    if (!geminiResponse.ok) {
      if (isRateLimitedResponse(geminiResponse.status, rawBody)) {
        return jsonResponse({
          text:
            "AI service is temporarily at capacity. Please retry in about a minute.",
          degraded: true,
          reason: "provider_rate_limited",
        });
      }
      return jsonResponse(
        {
          error: `Gemini call failed (${geminiResponse.status})`,
          details: rawBody,
        },
        502,
      );
    }

    const text = extractGeminiText(rawBody);

    if (!text) {
      return jsonResponse({ error: "Gemini returned empty content" }, 502);
    }

    return jsonResponse({ text });
  } catch (error) {
    return jsonResponse(
      { error: (error as Error).message || "gemini-chat-proxy failed" },
      400,
    );
  }
});

function safeJson(text: string): Record<string, unknown> {
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

function extractGeminiText(rawBody: string): string {
  const parsed = safeJson(rawBody);
  const candidates = Array.isArray(parsed?.candidates) ? parsed.candidates : [];
  const first = (candidates[0] ?? {}) as Record<string, unknown>;
  const content = (first?.content ?? {}) as Record<string, unknown>;
  const parts = Array.isArray(content?.parts) ? content.parts : [];
  return parts
    .map((part) =>
      typeof part === "object" && part !== null && "text" in part
        ? String((part as Record<string, unknown>).text ?? "")
        : ""
    )
    .join("\n")
    .trim();
}

function isRateLimitedResponse(status: number, rawBody: string): boolean {
  if (status === 429) return true;
  const parsedError = safeJson(rawBody);
  const providerStatus = String(
    (parsedError["error"] as Record<string, unknown> | undefined)?.["status"] ?? "",
  ).toUpperCase();
  return providerStatus === "RESOURCE_EXHAUSTED";
}

async function callGeminiGenerate(params: {
  baseWithoutVersion: string;
  apiKey: string;
  model: string;
  prompt: string;
  systemPrompt: string;
  temperature: number;
  maxOutputTokens: number;
}): Promise<{ response: Response; rawBody: string }> {
  const geminiUrl =
    `${params.baseWithoutVersion}/v1beta/models/${encodeURIComponent(params.model)}:generateContent?key=${encodeURIComponent(params.apiKey)}`;

  const response = await fetch(geminiUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: params.systemPrompt }] },
      contents: [{ role: "user", parts: [{ text: params.prompt }] }],
      generationConfig: {
        temperature: params.temperature,
        maxOutputTokens: params.maxOutputTokens,
      },
    }),
  });

  const rawBody = await response.text();
  return { response, rawBody };
}

function delayMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function jsonResponse(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}
