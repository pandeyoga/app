import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

// ── SEC-06: the only path that may create a partner application ───────────────
// partner_applications carried an INSERT policy of `true` for roles {public}, so
// anyone holding the anon key could POST rows straight into the admin Partner
// Assessment queue with no session and no validation. The policy is now removed
// (see 20260922_partner_application_submission_lockdown.sql) and every write goes
// through here, where it can be validated, attributed and rate limited.
//
// A caller needs a session, but not an identified one: /partner/register is a
// public route and GuestSession.ensure() signs the visitor in anonymously, which
// yields a real `authenticated` JWT with a stable uid. That uid is what lets the
// uploaded evidence be verified as the caller's own.

const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://revive.co.id',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/** Max applications a single session may file per rolling 24h. */
const RATE_LIMIT_PER_DAY = 3

/** Fields the registration form must supply. */
const REQUIRED = ['entity_name', 'shop_name', 'owner_name', 'email', 'phone', 'address', 'bank_name', 'bank_account_number', 'bank_account_holder'] as const

/** Legal documents, keyed exactly as the form names its picker slots. */
const DOC_TYPES = ['nib', 'npwp', 'siup', 'ktp'] as const

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function bad(message: string, status = 400) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return bad('Missing Authorization header', 401)
    const token = authHeader.replace('Bearer ', '')

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    )

    // Any valid session — including an anonymous one — may apply, but it must be
    // a real session: the uid below is what the upload paths are scoped to.
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    if (userError || !user) return bad(`Unauthorized: ${userError?.message || 'No user'}`, 401)

    const uid = user.id

    let payload: Record<string, unknown>
    try {
      payload = await req.json()
    } catch {
      return bad('Invalid JSON body')
    }

    // ── 1. Required fields ─────────────────────────────────────────────────────
    const missing = REQUIRED.filter((f) => {
      const v = payload[f]
      return v === undefined || v === null || String(v).trim() === ''
    })
    if (missing.length > 0) {
      return bad(`Missing required field(s): ${missing.join(', ')}`)
    }

    const email = String(payload.email).trim().toLowerCase()
    if (!EMAIL_RE.test(email)) return bad('Invalid email address')

    // ── 2. Evidence must belong to the caller ──────────────────────────────────
    // Each key is a storage path inside the private 'revive-photos' bucket. The
    // upload policy scopes objects to <auth.uid()>/..., so requiring the
    // '<uid>/partner-applications/' prefix here stops an application from citing
    // someone else's documents or an arbitrary object as its own evidence.
    const expectedPrefix = `${uid}/partner-applications/`

    const ownedKey = (k: unknown, field: string): string | null => {
      if (k === undefined || k === null || k === '') return null
      const key = String(k)
      if (!key.startsWith(expectedPrefix)) {
        throw new Error(
          `${field} does not belong to this session — expected a key under ${expectedPrefix}`
        )
      }
      return key
    }

    const docKeys: Record<string, string | null> = {}
    for (const t of DOC_TYPES) {
      docKeys[t] = ownedKey(payload[`${t}_file_key`], `${t}_file_key`)
    }

    const rawPhotos = Array.isArray(payload.facility_photo_keys)
      ? payload.facility_photo_keys
      : []
    const photoKeys = rawPhotos
      .filter((p): p is Record<string, unknown> => !!p && typeof p === 'object')
      .map((p) => ({
        slot: Number(p.slot) || 0,
        label: p.label ? String(p.label) : null,
        file_key: ownedKey(p.file_key, 'facility_photo_keys[].file_key'),
      }))
      .filter((p) => p.file_key !== null)

    // Same evidence rule the client enforces: an application with nothing to
    // inspect is what made the admin document counter read 0/4 forever.
    const docCount = DOC_TYPES.filter((t) => docKeys[t]).length
    if (photoKeys.length === 0 && docCount === 0) {
      return bad('At least one facility photo or legal document is required')
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // ── 3. Rate limit per session ──────────────────────────────────────────────
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    const { count, error: countError } = await supabaseAdmin
      .from('partner_applications')
      .select('id', { count: 'exact', head: true })
      .eq('submitted_by', uid)
      .gte('created_at', since)

    if (countError) throw countError
    if ((count ?? 0) >= RATE_LIMIT_PER_DAY) {
      return bad(
        `Too many applications submitted from this session (limit ${RATE_LIMIT_PER_DAY} per 24h). Please try again later.`,
        429
      )
    }

    // ── 4. One pending application per email (C-92 fix: .eq not .ilike) ────────
    const { data: existing, error: existingError } = await supabaseAdmin
      .from('partner_applications')
      .select('id')
      .eq('status', 'pending')
      .eq('email', email)   // email already lowercased above; eq avoids _ and % wildcard exploit
      .limit(1)

    if (existingError) throw existingError
    if (existing && existing.length > 0) {
      return bad('An application for this email is already awaiting review.', 409)
    }

    // ── 5. Validate inputs server-side (C-77) ───────────────────────────────
    const tier = Number(payload.tier ?? 2)
    if (![1, 2, 3].includes(tier)) return bad('tier must be 1, 2, or 3', 400)

    const throughput = Number(payload.throughput_capacity ?? 12)
    if (throughput < 1 || throughput > 50) return bad('throughput_capacity must be 1-50', 400)

    const radius = payload.service_radius_km != null ? Number(payload.service_radius_km) : null
    if (radius !== null && (radius < 1 || radius > 100)) return bad('service_radius_km must be 1-100', 400)

    // Validate photo slots 0-3, unique
    const usedSlots = new Set<number>()
    for (const p of photoKeys) {
      const slot = Number((p as any).slot ?? 0)
      if (slot < 0 || slot > 3) return bad(`Photo slot must be 0-3, got ${slot}`, 400)
      if (usedSlots.has(slot)) return bad(`Duplicate photo slot ${slot}`, 400)
      usedSlots.add(slot)
    }

    // ── 6. Insert ──────────────────────────────────────────────────────────────
    const { data: inserted, error: insertError } = await supabaseAdmin
      .from('partner_applications')
      .insert({
        entity_name: String(payload.entity_name).trim(),
        shop_name: String(payload.shop_name).trim(),
        owner_name: String(payload.owner_name).trim(),
        email,
        phone: String(payload.phone).trim(),
        address: String(payload.address).trim(),
        tier,
        paint_brand: payload.paint_brand ?? 'glasurit',
        throughput_capacity: throughput,
        service_radius_km: radius,
        status: 'pending',
        submitted_at: new Date().toISOString(),
        submitted_by: uid,
        nib_file_key: docKeys.nib,
        npwp_file_key: docKeys.npwp,
        siup_file_key: docKeys.siup,
        ktp_file_key: docKeys.ktp,
        facility_photo_keys: photoKeys,
        workshop_address: payload.workshop_address ? String(payload.workshop_address).trim() : null,
        latitude: payload.latitude != null ? Number(payload.latitude) : null,
        longitude: payload.longitude != null ? Number(payload.longitude) : null,
        bank_name: String(payload.bank_name ?? '').trim() || null,
        bank_account_number: String(payload.bank_account_number ?? '').trim() || null,
        bank_account_holder: String(payload.bank_account_holder ?? '').trim() || null,
        wa_verified: payload.wa_verified === true,
      })
      .select('id')
      .single()

    if (insertError) throw insertError

    return new Response(
      JSON.stringify({
        success: true,
        application_id: inserted.id,
        documents: docCount,
        photos: photoKeys.length,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err: any) {
    const message = err?.message ?? String(err)
    // Path-ownership failures are the caller's fault, not a server error.
    const status = /does not belong to this session/.test(message) ? 403 : 400
    return bad(message, status)
  }
})
