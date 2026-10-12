import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': 'https://revive.co.id',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Missing Authorization header')
    const token = authHeader.replace('Bearer ', '')

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    )

    // Verify caller is master_admin
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    if (userError || !user) throw new Error(`Unauthorized: ${userError?.message || 'No user'}`)

    // SEC-02 FIX: Only read role from app_metadata (cannot be self-modified by user)
    const userRole = user.app_metadata?.role
    if (userRole !== 'master_admin') {
      return new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403, headers: corsHeaders })
    }

    // Get request body
    const { applicationId } = await req.json()
    if (!applicationId) throw new Error('applicationId is required')

    // We need service_role key to bypass RLS and use auth.admin
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Fetch the application
    const { data: appData, error: appError } = await supabaseAdmin
      .from('partner_applications')
      .select('*')
      .eq('id', applicationId)
      .single()

    if (appError || !appData) throw new Error('Application not found')
    if (appData.status !== 'pending' && appData.status !== 'pending_review') {
      throw new Error('Application is not pending')
    }

    // ── 1. Create the partner row ─────────────────────────────────────────────
    // FB-02 FIX: carry the submitted workshop profile across. Previously only
    // shop_name / email / phone / address were copied, so an approved workshop
    // landed in the directory with a null entity_name, a null tier, a null paint
    // brand and null capacity — and no evidence of what was reviewed.
    const { data: partnerData, error: partnerError } = await supabaseAdmin
      .from('partners')
      .insert({
        shop_name: appData.shop_name,
        entity_name: appData.entity_name,
        owner_name: appData.owner_name,
        email: appData.email,
        phone: appData.phone,
        address: appData.address,
        tier: appData.tier ?? 2,
        paint_brand: appData.paint_brand ?? 'glasurit',
        throughput_capacity: appData.throughput_capacity ?? 12,
        service_radius_km: appData.service_radius_km,
        status: 'approved',
        submitted_at: appData.submitted_at ?? appData.created_at,
        nib_file_key: appData.nib_file_key,
        npwp_file_key: appData.npwp_file_key,
        siup_file_key: appData.siup_file_key,
        ktp_file_key: appData.ktp_file_key,
        is_active: true,
        workshop_address: appData.workshop_address ?? null,
        latitude: appData.latitude ?? null,
        longitude: appData.longitude ?? null,
        bank_name: appData.bank_name ?? null,
        bank_account_number: appData.bank_account_number ?? null,
        bank_account_holder: appData.bank_account_holder ?? null,
      })
      .select()
      .single()

    if (partnerError) throw partnerError

    // ── 2. Invite or fetch the user ───────────────────────────────────────────
    let userId = '';
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.inviteUserByEmail(
      appData.email,
      {
        data: { role: 'partner_mechanic', partner_id: partnerData.id }
      }
    )

    if (authError) {
      // SEC-15 FIX: listUsers() without pagination only returns the first page —
      // it fails once the user count exceeds the default limit. Scan pages until
      // the email is found.
      let existingUser = null
      let page = 1
      const perPage = 100
      while (!existingUser) {
        const { data: pageData, error: pageError } =
          await supabaseAdmin.auth.admin.listUsers({ page, perPage })
        if (pageError) throw pageError
        existingUser = pageData.users.find((u) => u.email === appData.email)
        if (pageData.users.length < perPage) break // No more pages
        page++
        if (page > 50) break // Safety limit: 5000 users max scan
      }

      if (!existingUser) {
        throw new Error(`Failed to invite user and could not find existing account: ${authError.message}`)
      }
      userId = existingUser.id
    } else {
      userId = authData.user.id
    }

    // Ensure the metadata is forcefully updated (handles cases where the user already existed)
    const { error: updateAuthError } = await supabaseAdmin.auth.admin.updateUserById(
      userId,
      {
        user_metadata: { role: 'partner_mechanic', partner_id: partnerData.id },
        app_metadata: { role: 'partner_mechanic', partner_id: partnerData.id }
      }
    )

    if (updateAuthError) throw updateAuthError

    // ── 3. Create or update the profile ──────────────────────────────────────
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .upsert({
        id: userId,
        full_name: appData.owner_name,
        email: appData.email,
        phone: appData.phone,
        role: 'partner_mechanic',
        partner_id: partnerData.id
      })

    if (profileError) throw profileError

    // ── 4. Membership ─────────────────────────────────────────────────────────
    // FB-02 FIX: memberships is the source of truth for authorization since
    // 20260920_authorization_consolidation. is_master_admin(), has_partner_membership()
    // and the partner RLS policies all read it, so without this row the invited
    // owner could not update their own partner record.
    const { error: membershipError } = await supabaseAdmin
      .from('memberships')
      .insert({
        user_id: userId,
        scope: 'partner',
        org_id: partnerData.id,
        role: 'owner',
        status: 'active'
      })

    // 23505 = already a member of this org (re-approval); anything else is real.
    if (membershipError && membershipError.code !== '23505') throw membershipError

    // ── 5. Carry the uploaded evidence onto the partner ───────────────────────
    // FB-02 FIX: the application's documents and facility photos are moved into
    // the versioned tables the partner dashboard and the admin detail panel read.
    // Without this the reviewer's evidence was orphaned on the application row.
    const docTypes = ['nib', 'npwp', 'siup', 'ktp'] as const
    const docRows = docTypes
      .filter((t) => appData[`${t}_file_key`])
      .map((t) => {
        const fileKey: string = appData[`${t}_file_key`]
        return {
          partner_id: partnerData.id,
          doc_type: t,
          file_key: fileKey,
          file_name: fileKey.split('/').pop() ?? `${t}.pdf`,
          uploaded_by: userId,
          is_current: true
        }
      })

    if (docRows.length > 0) {
      const { error: docError } = await supabaseAdmin
        .from('partner_documents')
        .insert(docRows)
      if (docError) throw docError
    }

    const photoKeys = Array.isArray(appData.facility_photo_keys)
      ? appData.facility_photo_keys
      : []

    const photoRows = photoKeys
      .filter((p: Record<string, unknown>) => p && p.file_key)
      .map((p: Record<string, unknown>) => ({
        partner_id: partnerData.id,
        slot: Number(p.slot) || 0,
        label: (p.label as string) ?? null,
        file_key: p.file_key as string,
        uploaded_by: userId,
        is_current: true
      }))

    if (photoRows.length > 0) {
      const { error: photoError } = await supabaseAdmin
        .from('partner_facility_photos')
        .insert(photoRows)
      if (photoError) throw photoError
    }

    // ── 6. Update the application status ─────────────────────────────────────
    const { error: updateError } = await supabaseAdmin
      .from('partner_applications')
      .update({ status: 'approved', reviewed_at: new Date().toISOString() })
      .eq('id', applicationId)

    if (updateError) throw updateError

    // ── 7. Notify applicant via WA + email ────────────────────────────────────
    const waMsg = `Selamat! 🎉\n\nPendaftaran bengkel *${appData.shop_name}* sebagai mitra Revive telah *disetujui*.\n\nSilakan cek email Anda untuk link login ke dashboard mitra.\n\nSalam,\nTim Revive`
    const emailMsg = `Selamat,\n\nPendaftaran bengkel ${appData.shop_name} sebagai mitra Revive telah disetujui.\n\nSilakan cek email ini untuk link login ke dashboard mitra Anda.\n\nSalam,\nTim Revive`

    const enqueue = async (channel: 'whatsapp' | 'email', toAddress: string, title: string, body: string) => {
      const { error } = await supabaseAdmin.from('notification_outbox').insert({
        user_id: null, job_id: null, kind: 'partner_approved',
        channel, to_address: toAddress, title, body,
        payload: {}, status: 'pending', purpose: 'transactional',
      })
      if (error) console.error(`[approve enqueue ${channel}]`, error.message)
    }

    if (appData.phone) await enqueue('whatsapp', appData.phone, 'Pendaftaran Mitra Revive Disetujui', waMsg)
    if (appData.email) await enqueue('email', appData.email, 'Pendaftaran Mitra Revive Disetujui', emailMsg)

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Partner approved and invited',
        partner_id: partnerData.id,
        documents: docRows.length,
        photos: photoRows.length
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
