// request-revision-partner
// Admin action: marks a pending application as 'pending_review' and sends the
// applicant a WA + email message with the revision notes, so they know exactly
// what to fix before resubmitting.
//
// Body: { applicationId: string, notes: string }
// Caller must be master_admin.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const CORS = {
  "Access-Control-Allow-Origin": "https://revive.co.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization" }, 401);

    const anon = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!
    );
    const { data: { user }, error: userErr } = await anon.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (userErr || !user) return json({ error: "Unauthorized" }, 401);
    if (user.app_metadata?.role !== "master_admin") return json({ error: "Forbidden" }, 403);

    const { applicationId, notes } = await req.json();
    if (!applicationId) return json({ error: "applicationId required" }, 400);
    if (!notes?.trim()) return json({ error: "notes required — tell the applicant what to fix" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } }
    );

    const { data: app, error: appErr } = await admin
      .from("partner_applications")
      .select("email, phone, shop_name, status")
      .eq("id", applicationId)
      .single();

    if (appErr || !app) return json({ error: "Application not found" }, 404);

    const { error: updateErr } = await admin
      .from("partner_applications")
      .update({
        status: "pending_review",
        revision_notes: notes.trim(),
        reviewed_at: new Date().toISOString(),
      })
      .eq("id", applicationId);
    if (updateErr) throw updateErr;

    const waMsg =
      `Halo dari Revive 👋\n\n` +
      `Pendaftaran bengkel *${app.shop_name}* Anda sedang kami tinjau dan memerlukan beberapa perbaikan sebelum dapat disetujui.\n\n` +
      `*Catatan dari tim Revive:*\n${notes.trim()}\n\n` +
      `Silakan kirim ulang dokumen atau informasi yang diperlukan, lalu balas pesan ini atau hubungi partner@revive.co.id.\n\n` +
      `Terima kasih! 🙏`;

    const emailMsg =
      `Halo,\n\n` +
      `Pendaftaran bengkel ${app.shop_name} memerlukan perbaikan sebelum dapat kami setujui.\n\n` +
      `Catatan dari tim Revive:\n${notes.trim()}\n\n` +
      `Mohon kirim ulang informasi atau dokumen yang diperlukan ke partner@revive.co.id, ` +
      `atau balas email ini.\n\n` +
      `Salam,\nTim Revive`;

    if (app.phone) {
      await admin.rpc("notify", {
        p_user_id: null, p_job_id: null,
        p_kind: "partner_revision_requested",
        p_channel: "whatsapp",
        p_to_address: app.phone,
        p_title: "Revisi Pendaftaran Mitra Revive",
        p_body: waMsg, p_payload: {}, p_purpose: "transactional",
      });
    }

    if (app.email) {
      await admin.rpc("notify", {
        p_user_id: null, p_job_id: null,
        p_kind: "partner_revision_requested",
        p_channel: "email",
        p_to_address: app.email,
        p_title: "Revisi Pendaftaran Mitra Revive",
        p_body: emailMsg, p_payload: {}, p_purpose: "transactional",
      });
    }

    return json({ success: true, status: "pending_review" });
  } catch (err: any) {
    console.error("[request-revision-partner]", err);
    return json({ error: err?.message ?? String(err) }, 500);
  }
});
