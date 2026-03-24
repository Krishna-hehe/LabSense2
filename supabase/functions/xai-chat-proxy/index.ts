import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
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
      return jsonResponse({ error: "User not authenticated" }, 401);
    }

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
    const model = (body?.model ?? Deno.env.get("GEMINI_CHAT_MODEL") ??
      Deno.env.get("XAI_CHAT_MODEL") ??
      "gemini-2.0-flash-lite").toString();
    const prompt = (body?.prompt ?? "").toString().trim();
    const systemPrompt = (body?.systemPrompt ??
      "You are a concise, evidence-grounded medical assistant.")
      .toString();
    const temperature = Number(body?.temperature ?? 0.2);
    const maxTokens = Number(body?.maxTokens ?? 700);

    if (!prompt) {
      return jsonResponse({ error: "prompt is required" }, 400);
    }

    const trimmedBase = geminiBaseUrl.endsWith("/")
      ? geminiBaseUrl.slice(0, -1)
      : geminiBaseUrl;
    const baseWithoutVersion = trimmedBase.replace(/\/v1beta$/, "");
    const sanitizedModel = model.replace(/^models\//, "").trim();
    if (!sanitizedModel) {
      return jsonResponse({ error: "model is required" }, 400);
    }
    const geminiUrl =
      `${baseWithoutVersion}/v1beta/models/${encodeURIComponent(sanitizedModel)}:generateContent?key=${encodeURIComponent(geminiApiKey)}`;

    const geminiResponse = await fetch(geminiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature,
          maxOutputTokens: maxTokens,
        },
      }),
    });

    const rawBody = await geminiResponse.text();
    if (!geminiResponse.ok) {
      return jsonResponse(
        {
          error: `Gemini call failed (${geminiResponse.status})`,
          details: rawBody,
        },
        502,
      );
    }

    const parsed = safeJson(rawBody);
    const candidates = Array.isArray(parsed?.candidates) ? parsed.candidates : [];
    const first = (candidates[0] ?? {}) as Record<string, unknown>;
    const content = (first?.content ?? {}) as Record<string, unknown>;
    const parts = Array.isArray(content?.parts) ? content.parts : [];
    const text = parts
      .map((part) =>
        typeof part === "object" && part !== null && "text" in part
          ? String((part as Record<string, unknown>).text ?? "")
          : ""
      )
      .join("\n")
      .trim();

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

function jsonResponse(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}
