/**
 * generate-document — Παραγωγή εγγράφων έργου από τα πρότυπα της Υπηρεσίας.
 *
 * POST /functions/v1/generate-document
 * {
 *   project_id:        uuid,           // υποχρεωτικό
 *   doc_code:          string,         // π.χ. "BEBAIOSI_PERATOSIS"
 *   entity_id?:        uuid,           // επιμέτρηση / αφανείς / εγγύηση / ΑΠΕ …
 *   project_stage_id?: uuid,           // σύνδεση με στάδιο του οδηγού
 *   overrides?:        { [path]: string },
 *   assign_protocol?:  boolean,        // λήψη αριθμού πρωτοκόλλου (default: true)
 *   status?:           'draft'|'signed'|'approved',
 *   dry_run?:          boolean         // επιστροφή προεπισκόπησης χωρίς αποθήκευση
 * }
 *
 * ΑΣΦΑΛΕΙΑ: ο πελάτης Supabase δημιουργείται με το JWT του καλούντος, άρα
 * κάθε ανάγνωση/εγγραφή υπόκειται στα RLS policies. Η συνάρτηση δεν
 * χρησιμοποιεί service-role κλειδί.
 */
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'
import { buildContext } from './context.ts'
import { renderDocx, renderHtmlBody, sha256, wrapDocument, type FieldSpec } from './render.ts'
import { formatValue, todayIso } from './format.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8' },
  })

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'Επιτρέπεται μόνο POST.' }, 405)

  const auth = req.headers.get('Authorization')
  if (!auth) return json({ error: 'Λείπει η κεφαλίδα Authorization.' }, 401)

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  )

  try {
    const body = await req.json()
    const {
      project_id, doc_code, entity_id = null, project_stage_id = null,
      overrides = {}, assign_protocol = true, status = 'draft', dry_run = false,
    } = body ?? {}

    if (!project_id || !doc_code) {
      return json({ error: 'Απαιτούνται τα πεδία project_id και doc_code.' }, 400)
    }

    const { data: user } = await sb.auth.getUser()
    if (!user?.user) return json({ error: 'Μη έγκυρη συνεδρία.' }, 401)

    // ---- Πρότυπο ---------------------------------------------------
    const { data: template, error: tErr } = await sb
      .from('document_templates')
      .select('*')
      .eq('doc_code', doc_code)
      .eq('is_active', true)
      .order('version', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (tErr) return json({ error: `Σφάλμα ανάγνωσης προτύπου: ${tErr.message}` }, 500)
    if (!template) {
      return json({ error: `Δεν βρέθηκε ενεργό πρότυπο με κωδικό «${doc_code}».` }, 404)
    }

    const { data: fieldRows } = await sb
      .from('template_fields').select('*').eq('template_id', template.id)
    const specs = new Map<string, FieldSpec>(
      (fieldRows ?? []).map(f => [f.placeholder, f as FieldSpec]),
    )

    // ---- Δεδομένα --------------------------------------------------
    const ctx = await buildContext(sb, { projectId: project_id, docCode: doc_code, entityId: entity_id })
    const org = (ctx.organizations ?? {}) as Record<string, string | null>

    // ---- Αριθμός πρωτοκόλλου --------------------------------------
    let protocolNo: string | null = null
    if (assign_protocol && !dry_run && org.id) {
      const { data: seq, error: sErr } = await sb.rpc('next_protocol_no', { p_org: org.id })
      if (!sErr && seq != null) {
        const year = new Date().getFullYear()
        protocolNo = (template.numbering_scheme ?? '{ΕΤΟΣ}/{ΑΑ}')
          .replace('{ΕΤΟΣ}', String(year))
          .replace('{ΑΑ}', String(seq))
      }
    }
    const protocolDate = todayIso()

    // ---- Απόδοση ---------------------------------------------------
    let bytes: Uint8Array
    let contentType: string
    let extension: string
    let missing: string[] = []
    let payload: Record<string, string> = {}
    let previewHtml: string | null = null

    if (template.file_type === 'docx' && template.storage_path) {
      const { data: file, error: dErr } = await sb.storage
        .from('templates').download(template.storage_path)
      if (dErr || !file) {
        return json({ error: `Δεν ήταν δυνατή η λήψη του προτύπου: ${dErr?.message}` }, 502)
      }
      const res = await renderDocx(new Uint8Array(await file.arrayBuffer()), ctx, specs, overrides)
      bytes = res.bytes
      missing = res.missing
      payload = res.payload
      contentType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      extension = 'docx'
    } else {
      if (!template.body_html) {
        return json({
          error: `Το πρότυπο «${doc_code}» δεν έχει ούτε αρχείο στο storage_path ούτε ενσωματωμένο body_html.`,
        }, 422)
      }
      const rendered = renderHtmlBody(template.body_html, ctx, specs, overrides)
      const subject = renderHtmlBody(template.subject_template ?? template.title, ctx, specs, overrides).html
      const signatories = ((template.signatories ?? []) as { label: string; name: string; capacity?: string }[])
        .map(s => ({
          label: s.label,
          name: renderHtmlBody(s.name, ctx, specs, overrides).html,
          capacity: s.capacity ? renderHtmlBody(s.capacity, ctx, specs, overrides).html : undefined,
        }))

      const contractorName =
        (ctx.anadoxos as { epwnymia?: string } | undefined)?.epwnymia ?? 'Ο ανάδοχος'

      previewHtml = wrapDocument({
        orgName: org.name ?? 'ΟΡΓΑΝΙΣΜΟΣ',
        orgUnit: org.unit ?? null,
        orgAddress: org.address ?? null,
        orgPhone: org.phone ?? null,
        orgEmail: org.email ?? null,
        title: template.title,
        subject,
        protocolNo,
        protocolDate: formatValue(protocolDate, 'date'),
        ada: null,
        legalRef: legalLabel(template.legal_ref_id),
        bodyHtml: rendered.html,
        signatories,
        recipients: [contractorName, 'Φάκελο έργου'],
      })
      bytes = new TextEncoder().encode(previewHtml)
      missing = rendered.missing
      payload = rendered.payload
      contentType = 'text/html; charset=utf-8'
      extension = 'html'
    }

    const checksum = await sha256(bytes)

    if (dry_run) {
      return json({
        ok: true, dry_run: true, doc_code, missing_fields: missing,
        payload, checksum, preview_html: previewHtml,
      })
    }

    // ---- Αποθήκευση ------------------------------------------------
    const stamp = new Date().toISOString().replace(/[:.]/g, '-')
    const storagePath = `${project_id}/${doc_code}_${stamp}.${extension}`

    const { error: upErr } = await sb.storage
      .from('documents')
      .upload(storagePath, bytes, { contentType, upsert: false })
    if (upErr) return json({ error: `Αποτυχία αποθήκευσης αρχείου: ${upErr.message}` }, 502)

    const { data: doc, error: insErr } = await sb
      .from('documents')
      .insert({
        project_id,
        project_stage_id,
        template_id: template.id,
        doc_code,
        title: template.title,
        protocol_no: protocolNo,
        protocol_date: protocolDate,
        status,
        storage_path: storagePath,
        payload: { fields: payload, missing, generated_by: user.user.email },
        checksum,
        entity_type: (ctx.entity_type as string | undefined) ?? null,
        entity_id,
        created_by: user.user.id,
      })
      .select('*')
      .single()

    if (insErr) {
      await sb.storage.from('documents').remove([storagePath])
      return json({ error: `Αποτυχία καταχώρισης εγγράφου: ${insErr.message}` }, 500)
    }

    const { data: signed } = await sb.storage
      .from('documents').createSignedUrl(storagePath, 60 * 60)

    return json({
      ok: true,
      document: doc,
      missing_fields: missing,
      download_url: signed?.signedUrl ?? null,
      checksum,
    })
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})

function legalLabel(ref: string | null): string | null {
  if (!ref) return null
  if (ref === 'PD305/1996') return 'π.δ. 305/1996'
  if (ref.startsWith('N4412/')) {
    const [article, paragraph] = ref.slice(6).split('/')
    const map: Record<string, string> = { '1e': '1ε', '3a': '3α', '3b': '3β', '3c': '3γ', '14b': '14β' }
    return paragraph
      ? `άρθρο ${article} παρ. ${map[paragraph] ?? paragraph} ν. 4412/2016`
      : `άρθρο ${article} ν. 4412/2016`
  }
  return ref
}
