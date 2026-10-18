import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";
// PERF-09 FIX: Use standard library base64 encoder instead of byte-by-byte loop
import { encode as base64Encode } from "https://deno.land/std@0.168.0/encoding/base64.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const googleApiKey = Deno.env.get("GOOGLE_AI_API_KEY") ?? "";
const groqApiKey = Deno.env.get("GROQ_API_KEY") ?? "";
const openaiApiKey = Deno.env.get("OPENAI_API_KEY") ?? "";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// SEC-03 FIX: Lock CORS to production domain only (exact match — no startsWith)
const ALLOWED_ORIGINS = new Set(["https://revive.co.id", "https://app.revive.co.id", "http://localhost:3000", "http://localhost"]);

function getCorsHeaders(origin?: string | null): Record<string, string> {
  const allowedOrigin = (origin && ALLOWED_ORIGINS.has(origin)) ? origin : "https://revive.co.id";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

// B-09 fix: DB-backed rate limit replaces in-memory map (per isolate, bypassable)
// Called via supabase service role after JWT verification
async function checkDbRateLimit(supabaseAdmin: any, userId: string, isAnon: boolean): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc('check_ai_rate_limit', {
    p_user_id: userId,
    p_is_anon: isAnon,
  });
  if (error) {
    console.error('[RateLimit] DB check failed:', error.message, '— fail-open');
    return true; // fail-open: don't block on DB error
  }
  return data === true;
}

// SEC-03 FIX: Only accept signed URLs from our own Supabase project
const ownSupabaseHost = new URL(supabaseUrl || "https://ahaospjkkuetkaixwzzz.supabase.co").hostname;
function isValidPhotoUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.hostname === ownSupabaseHost || parsed.hostname === "localhost";
  } catch {
    return false;
  }
}

// ── Hardcoded fallback prices (used if pricing_rules table is empty/unreachable) ──
const FALLBACK_PRICES: Record<string, number> = {
  'Bumper Depan': 500500,
  'Spoiler Bumper depan': 286000,
  'Kap Mesin': 715000,
  'Bumper Belakang': 500500,
  'Spoiler Bumper Belakang': 286000,
  'Bagasi': 643500,
  'Spoiler Bagasi': 286000,
  'Fender RH': 572000,
  'Pintu Depan RH': 572000,
  'Spion RH': 143000,
  'Pintu Belakang RH': 572000,
  'Quarter RH': 572000,
  'Trisplang RH': 357500,
  'Side Roof RH': 357500,
  'Fender LH': 572000,
  'Pintu Depan LH': 572000,
  'Spion LH': 143000,
  'Pintu Belakang LH': 572000,
  'Quarter LH': 572000,
  'Trisplang LH': 357500,
  'Side Roof LH': 357500,
  'Roof': 1001000,
  'Cover': 286000,
};

// ── LivePricingRule: shape of a row from the pricing_rules table ──
interface LivePricingRule {
  panel_name: string;   // matches what AI returns and what's in DB
  base_rate: number;
  severity_min: number; // sedang (medium) multiplier
  severity_max: number; // berat  (heavy)  multiplier
}

// ── Fetches live pricing rules from DB; gracefully falls back to hardcoded map ──
async function loadPricingRules(): Promise<LivePricingRule[]> {
  try {
    const { data, error } = await supabase
      .from("pricing_rules")
      .select("panel_name, base_rate, severity_min, severity_max");

    if (error || !data || data.length === 0) {
      console.warn("pricing_rules fetch failed or empty — using hardcoded fallback.", error?.message);
      return Object.entries(FALLBACK_PRICES).map(([panel_name, base_rate]) => ({
        panel_name,
        base_rate,
        severity_min: 1.5,
        severity_max: 2.0,
      }));
    }
    return data as LivePricingRule[];
  } catch (err) {
    console.error("Unexpected error loading pricing_rules:", err);
    return Object.entries(FALLBACK_PRICES).map(([panel_name, base_rate]) => ({
      panel_name,
      base_rate,
      severity_min: 1.5,
      severity_max: 2.0,
    }));
  }
}

// ── Deterministic cost engine — uses live DB rules, not hardcoded map ──
function calculateDeterministicCost(
  structuredData: any,
  rules: LivePricingRule[]
): number {
  if (!structuredData?.assessment?.damaged_panels_detail) return 0;

  // L-10 fix: closed severity list — unknown value = berat (fail-safe, not ringan)
  const VALID_SEVERITIES = new Set(['ringan', 'sedang', 'berat']);

  // Build lookup map (case-insensitive handled at query time)
  const ruleMap = new Map<string, LivePricingRule>(rules.map((r) => [r.panel_name, r]));

  // C-34 fix: dedup panels by name, keep highest severity
  const panelMap = new Map<string, { severity: string; panel: any }>();
  for (const panel of structuredData.assessment.damaged_panels_detail) {
    const name: string = (panel.panel_name ?? '').trim();
    if (!name) continue;
    const rawSev: string = (panel.panel_severity ?? '').toLowerCase().trim();
    // L-10: unknown severity → berat (safe default, not ringan)
    const severity = VALID_SEVERITIES.has(rawSev) ? rawSev : 'berat';
    const existing = panelMap.get(name);
    // Keep highest severity (berat > sedang > ringan)
    const sevRank = (s: string) => s === 'berat' ? 2 : s === 'sedang' ? 1 : 0;
    if (!existing || sevRank(severity) > sevRank(existing.severity)) {
      panelMap.set(name, { severity, panel: { ...panel, panel_severity: severity } });
    }
  }

  let totalCost = 0;
  for (const [name, { severity, panel }] of panelMap) {
    // C-34 fix: case-insensitive lookup via normalized name
    const normName = name.toLowerCase();
    const rule = [...ruleMap.entries()].find(([k]) => k.toLowerCase() === normName)?.[1];
    if (!rule) {
      // Unknown panel — skip with log, no fallback price (C-34: don't price silently)
      console.warn(`[pricing] Unknown panel skipped: "${name}"`);
      continue;
    }

    let multiplier = 1.0;
    if (severity === 'sedang') multiplier = rule?.severity_min ?? 1.5;
    else if (severity === 'berat') multiplier = rule?.severity_max ?? 2.0;

    const panelCost = Math.round(rule.base_rate * multiplier);
    panel.calculated_cost = panelCost;
    panel.applied_multiplier = multiplier;
    totalCost += panelCost;
  }
  return totalCost;
}



serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── SEC-03 FIX: Require valid JWT authentication ──────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing or invalid Authorization header" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    // Verify the JWT using the anon key client (validates token signature)
    const userClient = createClient(supabaseUrl, supabaseAnonKey);
    const { data: { user }, error: authError } = await userClient.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    // B-09 fix: DB-backed rate limit (persistent across isolate restarts)
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    const isAnon = user.is_anonymous === true;
    if (!await checkDbRateLimit(supabaseAdmin, user.id, isAnon)) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again tomorrow.", code: "RATE_LIMITED" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 429,
      });
    }

    const { photoUrl, photoUrls: photoUrlsRaw, damageDescription, selectedPanels } = await req.json();

    // Support both the new array format and the legacy single-URL format
    const photoUrls: string[] = Array.isArray(photoUrlsRaw) && photoUrlsRaw.length > 0
      ? photoUrlsRaw
      : photoUrl
      ? [photoUrl]
      : [];

    if (photoUrls.length === 0) {
      return new Response(JSON.stringify({ error: "photoUrl or photoUrls is required" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // SEC-03 FIX: Cap number of images to prevent abuse
    if (photoUrls.length > 5) {
      return new Response(JSON.stringify({ error: "Maximum 5 images allowed" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // SEC-03 FIX: Validate all URLs belong to our Supabase Storage domain
    for (const url of photoUrls) {
      if (!isValidPhotoUrl(url)) {
        return new Response(JSON.stringify({ error: `Invalid photo URL domain: ${new URL(url).hostname}` }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        });
      }
    }

    // Load AI config + live pricing rules in parallel for minimum latency
    const [{ data: configs, error: configError }, liveRules] = await Promise.all([
      supabase
        .from("ai_config")
        .select("*")
        .eq("is_active", true)
        .order("priority_order", { ascending: true }),
      loadPricingRules(),
    ]);

    if (configError || !configs || configs.length === 0) {
      throw new Error("Failed to load active AI configuration (No active models found)");
    }

    const panelsConstraint = (selectedPanels && selectedPanels.length > 0)
        ? `\nIMPORTANT: The user has reported possible damage on these panels: [${selectedPanels.join(', ')}]. Use this as a HINT of which areas to inspect closely. However, you must ONLY include a panel in your response if you can VISUALLY CONFIRM actual damage (scratches, dents, deformation, or paint damage) on it from the image. If a listed panel shows NO visible damage in the image, you MUST OMIT it from damaged_panels_detail entirely. Do NOT assign default or assumed severity to panels that are not clearly damaged in the image. Accuracy is critical — do not include unverifiable panels.`
        : "";

    const masterPrompt = `Analyze the car body damage from these images.
Valid panel names are: Bumper Depan, Spoiler Bumper depan, Kap Mesin, Bumper Belakang, Spoiler Bumper Belakang, Bagasi, Spoiler Bagasi, Fender RH, Pintu Depan RH, Spion RH, Pintu Belakang RH, Quarter RH, Trisplang RH, Side Roof RH, Fender LH, Pintu Depan LH, Spion LH, Pintu Belakang LH, Quarter LH, Trisplang LH, Side Roof LH, Roof, Cover.${panelsConstraint}

For each damaged panel found, classify its specific severity into: 'ringan', 'sedang', or 'berat'.
Also classify the overall severity of the car damage.
Return precise counts for dents, scratches, and broken panels in the exact following JSON format:
{
  "analysis_metadata": { "engine_processed": "model-name", "timestamp": "ISO8601" },
  "assessment": {
    "severity_classification": "ringan/sedang/berat",
    "total_panels_damaged": 0,
    "damaged_panels_detail": [
      { "panel_name": "exact_valid_panel_name", "panel_severity": "ringan/sedang/berat", "scratches_found": 0, "dents_found": 0, "requires_replacement": false }
    ]
  },
  "financial_estimation": { "currency": "IDR", "estimated_days_to_repair": 0 }
}`;

    let estimationResult = null;
    let usedModel = "";
    let usedEngineId = -1;
    let lastError = null;

    // Execute Fallback Cascade
    for (const configData of configs) {
      try {
        const provider = configData.provider.toLowerCase();
        
        // Per-row API key: ai_config.api_key_env names the Edge Function secret
        // to use. Empty/missing falls back to the legacy hardcoded provider key,
        // so existing rows behave exactly as before.
        const rowKey = configData.api_key_env
          ? (Deno.env.get(configData.api_key_env) ?? "")
          : "";

        if (provider.includes("google") || provider.includes("gemini")) {
          estimationResult = await callGoogleGemini(photoUrls, masterPrompt, configData.model_name, rowKey || googleApiKey);
        } else if (provider.includes("groq")) {
          estimationResult = await callOpenAICompatible(photoUrls, masterPrompt, configData.model_name, rowKey || groqApiKey, configData.api_base_url);
        } else if (provider.includes("openai") || provider.includes("router")) {
          // Covers OpenAI, OpenRouter and 9Router-style gateways
          estimationResult = await callOpenAICompatible(photoUrls, masterPrompt, configData.model_name, rowKey || openaiApiKey, configData.api_base_url);
        } else {
          throw new Error(`Unsupported model provider: ${provider}`);
        }
        
        usedModel = `${configData.provider}/${configData.model_name}`;
        usedEngineId = configData.priority_order;
        break; // Success! Break the fallback loop
      } catch (err: any) {
        console.error(`Model ${configData.model_name} failed:`, err.message);
        lastError = err;
        // Loop continues to next fallback model
      }
    }

    if (!estimationResult) {
      throw new Error(`All fallback Vision AI Engines Failed. Last Error: ${lastError?.message}`);
    }

    let finalCostEstimation = null;
    try {
        let jsonStr = estimationResult;
        // Try to extract from markdown code blocks first
        const mdMatch = estimationResult.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (mdMatch) {
            jsonStr = mdMatch[1];
        } else {
            // Find the first { and the last }
            const firstBrace = estimationResult.indexOf('{');
            const lastBrace = estimationResult.lastIndexOf('}');
            if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
                jsonStr = estimationResult.substring(firstBrace, lastBrace + 1);
            }
        }
        
        finalCostEstimation = JSON.parse(jsonStr);
        const calculatedCost = calculateDeterministicCost(finalCostEstimation, liveRules);
        finalCostEstimation.financial_estimation = finalCostEstimation.financial_estimation || {};
        finalCostEstimation.financial_estimation.calculated_base_cost = calculatedCost;
        finalCostEstimation.financial_estimation.pricing_source = "live_db";
        
    } catch (e: any) {
        // L-03 fix: parse fail = hard failure, not success with null structuredData
        console.error('[vision-estimation] JSON parse failed:', e.message.slice(0, 200));
        return new Response(JSON.stringify({
          success: false,
          code: 'PARSE_ERROR',
          error: 'AI response could not be parsed as valid JSON',
        }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 502,
        });
    }

    return new Response(JSON.stringify({
        success: true,
        estimation: estimationResult,
        structuredData: finalCostEstimation,
        usedModel: usedModel,
        engineId: usedEngineId,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});

// --- Model API Call Wrappers ---

async function callGoogleGemini(photoUrls: string[], prompt: string, modelName: string, apiKey: string) {
  // Fetch and base64-encode ALL images, add each as a separate inline_data part
  // C-66 fix: AbortSignal.timeout for image fetch (8s per image)
  const imageParts: object[] = [];
  for (const url of photoUrls) {
    const imageResp = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!imageResp.ok) throw new Error(`Image fetch failed: HTTP ${imageResp.status}`);
    // C-66 fix: limit image size to 10MB before reading
    const contentLength = imageResp.headers.get('content-length');
    if (contentLength && parseInt(contentLength) > 10 * 1024 * 1024) {
      throw new Error('Image too large (max 10MB)');
    }
    const imageBuffer = await imageResp.arrayBuffer();
    const base64Image = base64Encode(new Uint8Array(imageBuffer));
    const mimeType = imageResp.headers.get('content-type') || 'image/jpeg';
    imageParts.push({ inline_data: { mime_type: mimeType, data: base64Image } });
  }

  // C-67 fix: send API key via header x-goog-api-key, not query string
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent`, {
    method: "POST",
    signal: AbortSignal.timeout(30000),   // C-66: 30s model timeout
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,           // C-67: header, not query string
    },
    body: JSON.stringify({
      contents: [{
        parts: [
          { text: prompt },
          ...imageParts,     // all images injected here
        ]
      }],
      generationConfig: {
        responseMimeType: "application/json"
      }
    })
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "<unreadable body>");
    throw new Error(
      `Google API error: ${response.status} ${response.statusText} — ${errBody.slice(0, 400)}`
    );
  }
  const data = await response.json();
  if (data.candidates && data.candidates[0].content.parts[0].text) {
     return data.candidates[0].content.parts[0].text;
  }
  throw new Error("No output returned from Google AI");
}

async function callOpenAICompatible(photoUrls: string[], prompt: string, modelName: string, apiKey: string, apiBaseUrl: string) {
  const isGroq = apiBaseUrl.includes("groq");
  const isOpenRouterFree = modelName.includes("free");

  // Build content array: text prompt first, then one image_url entry per photo.
  // Images are downloaded and inlined as base64 data URLs rather than passed as
  // remote links. Gemini-backed gateways have no remote-URL image input (the
  // native API takes inline_data only), so handing them an https URL makes the
  // upstream call stall or silently drop the image. Groq/OpenAI also accept
  // data URLs, so this path is safe for every provider.
  // C-66 fix: timeout per image + size limit
  const imageParts: object[] = [];
  for (const url of photoUrls) {
    const imageResp = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!imageResp.ok) {
      throw new Error(`Image fetch failed: HTTP ${imageResp.status}`);
    }
    const contentLength = imageResp.headers.get('content-length');
    if (contentLength && parseInt(contentLength) > 10 * 1024 * 1024) {
      throw new Error('Image too large (max 10MB)');
    }
    const imageBuffer = await imageResp.arrayBuffer();
    const base64Image = base64Encode(new Uint8Array(imageBuffer));
    const mimeType = imageResp.headers.get("content-type") || "image/jpeg";
    imageParts.push({
      type: "image_url",
      image_url: { url: `data:${mimeType};base64,${base64Image}` },
    });
  }

  const contentArray: object[] = [
    { type: "text", text: prompt },
    ...imageParts,
  ];

  const payload: any = {
    model: modelName,
    messages: [{ role: "user", content: contentArray }],
  };

  // Skip JSON mode for models that might not fully support strict structured format
  if (!isGroq && !isOpenRouterFree) {
    payload.response_format = { type: "json_object" };
  }

  const response = await fetch(apiBaseUrl, {
    method: "POST",
    signal: AbortSignal.timeout(35000), // C-66: 35s model timeout
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://revive.co.id",
      "X-Title": "re-V Platform"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "<unreadable body>");
    throw new Error(
      `OpenAI-compatible API error: ${response.status} ${response.statusText} — ${errBody.slice(0, 400)}`
    );
  }

  // Some gateways (e.g. 9Router) always answer with SSE, even when `stream` is
  // never requested — `response.json()` throws on that body. Detect by
  // content-type and reassemble the streamed deltas when present. Groq/OpenAI
  // reply with plain JSON and keep taking the branch below.
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    const raw = await response.text();
    let assembled = "";
    for (const line of raw.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data:")) continue;
      const chunkStr = trimmed.slice(5).trim();
      if (!chunkStr || chunkStr === "[DONE]") continue;
      try {
        const chunk = JSON.parse(chunkStr);
        const choice = (chunk.choices ?? [])[0] ?? {};
        const piece = choice.delta?.content ?? choice.message?.content;
        if (piece) assembled += piece;
      } catch {
        // Skip keep-alive / non-JSON frames
      }
    }
    if (!assembled.trim()) {
      throw new Error("OpenAI-compatible API returned an SSE stream with no content");
    }
    return assembled;
  }

  const data = await response.json();
  return data.choices[0].message.content;
}
