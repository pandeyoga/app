import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const CORS = {
  "Access-Control-Allow-Origin": "https://revive.co.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status, headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function enqueue(admin: any, opts: {
  kind: string; channel: "whatsapp" | "email"; toAddress: string;
  title: string; body: string;
}) {
  const { error } = await admin.from("notification_outbox").insert({
    user_id: null, job_id: null,
    kind: opts.kind, channel: opts.channel,
    to_address: opts.toAddress,
    title: opts.title, body: opts.body,
    payload: {}, status: "pending", purpose: "transactional",
  });
  if (error) console.error(`[enqueue ${opts.kind}/${opts.channel}]`, error.message);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization" }, 401);

    const anon = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user }, error: userErr } = await anon.auth.getUser(authHeader.replace("Bearer ", ""));
    if (userErr || !user) return json({ error: "Unauthorized" }, 401);
    if (user.app_metadata?.role !== "master_admin") return json({ error: "Forbidden" }, 403);

    const { applicationId, reason } = await req.json();
    if (!applicationId) return json({ error: "applicationId required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } }
    );

    const { data: app, error: appErr } = await admin
      .from("partner_applications").select("email, phone, shop_name, status")
      .eq("id", applicationId).single();
    if (appErr || !app) return json({ error: "Application not found" }, 404);
    if (!["pending", "pending_review"].includes(app.status)) {
      return json({ error: `Status is '${app.status}', cannot reject` }, 400);
    }

    const { error: updateErr } = await admin
      .from("partner_applications")
      .update({ status: "rejected", rejection_reason: reason ?? null, reviewed_at: new Date().toISOString() })
      .eq("id", applicationId);
    if (updateErr) throw updateErr;

    const reasonLine = reason ? `\n\nAlasan: ${reason}` : "";
    const waMsg = `Halo dari Revive,\n\nMohon maaf, pendaftaran bengkel *${app.shop_name}* kami tolak.${reasonLine}\n\nUntuk pertanyaan hubungi partner@revive.co.id.`;
    const emailMsg = `Halo,\n\nPendaftaran bengkel ${app.shop_name} tidak dapat kami setujui.${reasonLine}\n\nHubungi partner@revive.co.id.\n\nSalam,\nTim Revive`;

    if (app.phone) {
      await enqueue(admin, { kind: "partner_rejected", channel: "whatsapp",
        toAddress: app.phone, title: "Update Pendaftaran Revive", body: waMsg });
    }
    if (app.email) {
      await enqueue(admin, { kind: "partner_rejected", channel: "email",
        toAddress: app.email, title: "Update Pendaftaran Mitra Revive", body: emailMsg });
    }

    return json({ success: true, status: "rejected" });
  } catch (err: any) {
    console.error("[reject-partner]", err);
    return json({ error: err?.message ?? String(err) }, 500);
  }
});
