// verify-partner-otp
// Checks the OTP the applicant entered against the hashed token stored in
// partner_otp_tokens. Max 5 attempts before the token is invalidated.
//
// Body: { phone: string, code: string }
// Returns: { verified: true } or { verified: false, error: string }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const CORS = {
  "Access-Control-Allow-Origin": "https://revive.co.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MAX_ATTEMPTS = 5;

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
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
    const { phone, code } = await req.json().catch(() => ({}));
    if (!phone || !code) return json({ verified: false, error: "phone and code required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } }
    );

    const { data: row, error: fetchErr } = await admin
      .from("partner_otp_tokens")
      .select("hash, expires_at, attempts")
      .eq("phone", phone)
      .single();

    if (fetchErr || !row) return json({ verified: false, error: "OTP tidak ditemukan" });
    if (new Date(row.expires_at) < new Date()) {
      return json({ verified: false, error: "OTP sudah kadaluarsa. Kirim ulang." });
    }
    if (row.attempts >= MAX_ATTEMPTS) {
      return json({ verified: false, error: "Terlalu banyak percobaan. Kirim OTP baru." });
    }

    const hash = await sha256hex(code.trim());
    const match = hash === row.hash;

    if (match) {
      // Delete token — single use
      await admin.from("partner_otp_tokens").delete().eq("phone", phone);
      return json({ verified: true });
    }

    // Increment attempt counter
    await admin
      .from("partner_otp_tokens")
      .update({ attempts: row.attempts + 1 })
      .eq("phone", phone);

    return json({ verified: false, error: "Kode OTP salah" });
  } catch (err: any) {
    console.error("[verify-partner-otp]", err);
    return json({ verified: false, error: err?.message ?? String(err) }, 500);
  }
});
