// send-partner-otp
// Generates a 6-digit OTP, stores it (hashed) on the partner_applications row
// identified by phone, and dispatches it via WhatsApp through the notification
// outbox. Called from the partner registration screen before submit.
//
// Body: { phone: string, channel: 'whatsapp' }
// Returns: { sent: true } or { error: string }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const CORS = {
  "Access-Control-Allow-Origin": "https://revive.co.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const OTP_TTL_MINUTES = 10;

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function randomOtp(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

async function sha256hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text)
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { phone } = await req.json().catch(() => ({}));
    if (!phone) return json({ error: "phone required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } }
    );

    const otp = randomOtp();
    const hash = await sha256hex(otp);
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60_000).toISOString();

    // Upsert OTP keyed to phone number in a dedicated table.
    // partner_otp_tokens: (phone TEXT PK, hash TEXT, expires_at TIMESTAMPTZ, attempts INT)
    const { error: upsertErr } = await admin
      .from("partner_otp_tokens")
      .upsert(
        { phone, hash, expires_at: expiresAt, attempts: 0 },
        { onConflict: "phone" }
      );
    if (upsertErr) throw upsertErr;

    // Enqueue WA notification via the existing notify() DB function.
    const msg = `Kode OTP Revive Anda: *${otp}*\n\nBerlaku ${OTP_TTL_MINUTES} menit. Jangan bagikan ke siapapun.`;

    const { error: notifErr } = await admin.rpc("notify", {
      p_user_id: null,
      p_job_id: null,
      p_kind: "partner_otp",
      p_channel: "whatsapp",
      p_to_address: phone,
      p_title: "Kode Verifikasi Revive",
      p_body: msg,
      p_payload: {},
      p_purpose: "transactional",
    });
    if (notifErr) throw notifErr;

    return json({ sent: true });
  } catch (err: any) {
    console.error("[send-partner-otp]", err);
    return json({ error: err?.message ?? String(err) }, 500);
  }
});
