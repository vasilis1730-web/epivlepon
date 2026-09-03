/**
 * Απόδοση προτύπων.
 *
 *  • HTML  : αντικατάσταση placeholders + επαναλαμβανόμενες γραμμές πίνακα
 *  • DOCX  : αποσυμπίεση, αντικατάσταση στο word/document.xml, επανασυμπίεση
 *
 * Συντακτικό placeholder:  {{diadromi.pediou}}
 * Επαναλαμβανόμενη σειρά:  <tr>{{#each grammes}} … {{grammes.pedio}} … </tr>
 */
import JSZip from 'npm:jszip@3.10.1'
import { escapeHtml, formatValue, inferType } from './format.ts'
import { resolvePath } from './context.ts'

export interface FieldSpec {
  placeholder: string
  label: string
  data_type: string
  format_mask: string | null
  is_required: boolean
  source_kind: string
  source_path: string | null
}

const PLACEHOLDER = /\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/g
const EACH = /\{\{\s*#each\s+([a-zA-Z0-9_]+)\s*\}\}/

/** Επιστρέφει τη μορφοποιημένη τιμή ενός placeholder. */
function valueFor(
  path: string,
  ctx: unknown,
  specs: Map<string, FieldSpec>,
  overrides: Record<string, string>,
): { text: string; missing: boolean } {
  const key = `{{${path}}}`
  if (Object.prototype.hasOwnProperty.call(overrides, path)) {
    return { text: overrides[path], missing: false }
  }
  const spec = specs.get(key)

  let raw: unknown
  if (spec?.source_kind === 'computed' && spec.source_path) {
    raw = resolvePath(ctx, `computed.${spec.source_path}`)
  } else if (spec?.source_path && spec.source_kind !== 'manual') {
    raw = resolvePath(ctx, spec.source_path)
  }
  if (raw === undefined || raw === null) raw = resolvePath(ctx, path)

  const empty = raw === undefined || raw === null || raw === ''
  const type = spec?.data_type && spec.data_type !== 'table'
    ? spec.data_type
    : inferType(path, raw)

  return {
    text: empty ? '—' : formatValue(raw, type, spec?.format_mask),
    missing: empty && (spec?.is_required ?? false),
  }
}

export interface RenderResult {
  html: string
  missing: string[]
  payload: Record<string, string>
}

/** Απόδοση HTML σώματος προτύπου. */
export function renderHtmlBody(
  body: string,
  ctx: unknown,
  specs: Map<string, FieldSpec>,
  overrides: Record<string, string> = {},
): RenderResult {
  const missing: string[] = []
  const payload: Record<string, string> = {}

  // 1) Επαναλαμβανόμενες σειρές πίνακα
  let out = body.replace(/<tr\b[^>]*>[\s\S]*?<\/tr>/g, row => {
    const m = row.match(EACH)
    if (!m) return row
    const collection = m[1]
    const items = (resolvePath(ctx, collection) as Record<string, unknown>[] | undefined) ?? []
    const template = row.replace(EACH, '')
    if (items.length === 0) {
      return template.replace(PLACEHOLDER, '—')
    }
    return items
      .map(item =>
        template.replace(PLACEHOLDER, (_full, path: string) => {
          const field = path.startsWith(`${collection}.`) ? path.slice(collection.length + 1) : null
          if (field !== null) {
            const v = item[field]
            return escapeHtml(v === undefined || v === null || v === '' ? '—' : String(v))
          }
          const { text } = valueFor(path, ctx, specs, overrides)
          return escapeHtml(text)
        }),
      )
      .join('\n')
  })

  // 2) Απλά placeholders
  out = out.replace(PLACEHOLDER, (_full, path: string) => {
    const { text, missing: isMissing } = valueFor(path, ctx, specs, overrides)
    payload[path] = text
    if (isMissing && !missing.includes(path)) missing.push(path)
    return escapeHtml(text)
  })

  return { html: out, missing, payload }
}

/** Πλήρες έγγραφο έτοιμο για εκτύπωση/εξαγωγή σε PDF. */
export function wrapDocument(opts: {
  orgName: string
  orgUnit: string | null
  orgAddress: string | null
  orgPhone: string | null
  orgEmail: string | null
  title: string
  subject: string
  protocolNo: string | null
  protocolDate: string
  ada: string | null
  legalRef: string | null
  bodyHtml: string
  signatories: { label: string; name: string; capacity?: string }[]
  recipients?: string[]
}): string {
  const sig = opts.signatories
    .map(
      s => `<div class="sig">
        <div class="sig-label">${escapeHtml(s.label)}</div>
        <div class="sig-space"></div>
        <div class="sig-name">${escapeHtml(s.name)}</div>
        ${s.capacity ? `<div class="sig-cap">${escapeHtml(s.capacity)}</div>` : ''}
      </div>`,
    )
    .join('')

  return `<!doctype html>
<html lang="el"><head><meta charset="utf-8">
<title>${escapeHtml(opts.title)}</title>
<style>
  @page { size: A4; margin: 20mm 18mm 18mm 22mm; }
  * { box-sizing: border-box; }
  body { font-family: "Times New Roman", Times, serif; font-size: 11.5pt; line-height: 1.5;
         color: #111; margin: 0; padding: 20mm 18mm; max-width: 210mm; background: #fff; }
  .head { display: flex; justify-content: space-between; gap: 16mm;
          border-bottom: 1.5pt solid #111; padding-bottom: 4mm; }
  .head .org { font-size: 10.5pt; line-height: 1.35; }
  .head .org .rep { font-weight: 700; letter-spacing: .04em; }
  .head .org .name { font-weight: 700; }
  .head .org .unit { text-transform: uppercase; }
  .head .org .contact { margin-top: 2mm; font-size: 9pt; color: #444; }
  .head .prot { text-align: right; font-size: 10.5pt; white-space: nowrap; }
  .head .prot div { margin-bottom: 1.5mm; }
  .subject { margin: 7mm 0 5mm; font-size: 11pt; }
  .subject b { letter-spacing: .02em; }
  h1 { font-size: 13pt; text-align: center; letter-spacing: .08em; margin: 6mm 0 5mm; }
  .legal { text-align: center; font-size: 9.5pt; color: #555; margin: -3mm 0 6mm; }
  p { margin: 0 0 3.5mm; text-align: justify; }
  .intro { margin-bottom: 2mm; }
  ol.grounds { margin: 0 0 5mm; padding-left: 8mm; }
  ol.grounds li { margin-bottom: 2mm; text-align: justify; }
  .declare { text-align: center; font-weight: 700; letter-spacing: .3em; margin: 6mm 0 4mm; }
  table.data { width: 100%; border-collapse: collapse; margin: 4mm 0 5mm; font-size: 10.5pt; }
  table.data th { text-align: left; width: 38%; padding: 1.8mm 3mm; background: #f2f2f2;
                  border: 0.6pt solid #999; font-weight: 600; }
  table.data td { padding: 1.8mm 3mm; border: 0.6pt solid #999; }
  table.grid { width: 100%; border-collapse: collapse; margin: 4mm 0; font-size: 9.5pt; }
  table.grid th, table.grid td { border: 0.6pt solid #666; padding: 1.4mm 2mm; }
  table.grid thead th { background: #e8e8e8; font-weight: 700; text-align: center; }
  table.grid tfoot td { background: #f6f6f6; font-weight: 600; }
  table.grid tfoot tr.total td { background: #e0e0e0; font-weight: 700; }
  .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .note { font-size: 10pt; color: #333; margin-top: 4mm; }
  .signatures { display: flex; justify-content: space-around; gap: 12mm; margin-top: 14mm;
                page-break-inside: avoid; }
  .sig { text-align: center; min-width: 55mm; }
  .sig-label { font-size: 10pt; margin-bottom: 1mm; }
  .sig-space { height: 18mm; }
  .sig-name { font-weight: 700; border-top: 0.8pt solid #111; padding-top: 1.5mm; font-size: 10.5pt; }
  .sig-cap { font-size: 9pt; color: #555; }
  .recipients { margin-top: 10mm; font-size: 9.5pt; }
  .recipients b { display: block; margin-bottom: 1.5mm; }
  .recipients ol { margin: 0; padding-left: 6mm; }
  @media print { body { padding: 0; } }
</style></head>
<body>
  <header class="head">
    <div class="org">
      <div class="rep">ΕΛΛΗΝΙΚΗ ΔΗΜΟΚΡΑΤΙΑ</div>
      <div class="name">${escapeHtml(opts.orgName)}</div>
      ${opts.orgUnit ? `<div class="unit">${escapeHtml(opts.orgUnit)}</div>` : ''}
      <div class="contact">
        ${opts.orgAddress ? escapeHtml(opts.orgAddress) + '<br>' : ''}
        ${opts.orgPhone ? 'Τηλ.: ' + escapeHtml(opts.orgPhone) : ''}
        ${opts.orgEmail ? ' · ' + escapeHtml(opts.orgEmail) : ''}
      </div>
    </div>
    <div class="prot">
      <div>Ρόδος, ${escapeHtml(opts.protocolDate)}</div>
      ${opts.protocolNo ? `<div>Αρ. Πρωτ.: <b>${escapeHtml(opts.protocolNo)}</b></div>` : ''}
      ${opts.ada ? `<div>ΑΔΑ: <b>${escapeHtml(opts.ada)}</b></div>` : ''}
    </div>
  </header>

  <div class="subject"><b>ΘΕΜΑ:</b> ${escapeHtml(opts.subject)}</div>
  <h1>${escapeHtml(grUpper(opts.title))}</h1>
  ${opts.legalRef ? `<div class="legal">(${escapeHtml(opts.legalRef)})</div>` : ''}

  ${opts.bodyHtml}

  <div class="signatures">${sig}</div>

  ${
    opts.recipients?.length
      ? `<div class="recipients"><b>ΚΟΙΝΟΠΟΙΗΣΗ:</b><ol>${opts.recipients
          .map(r => `<li>${escapeHtml(r)}</li>`)
          .join('')}</ol></div>`
      : ''
  }
</body></html>`
}

/* ------------------------------------------------------------------ */
/* DOCX                                                                */
/* ------------------------------------------------------------------ */

const XML_ESC = (s: string) =>
  s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

/**
 * Κεφαλαιοποίηση κατά τους κανόνες της ελληνικής: τα κεφαλαία ΔΕΝ φέρουν
 * τόνο (ΑΠΟΦΑΣΗ, όχι ΑΠΌΦΑΣΗ)· τα διαλυτικά διατηρούνται (Ϊ, Ϋ).
 */
export const grUpper = (s: string) =>
  s.toUpperCase().normalize('NFD').replace(/[̀́͂΄]/g, '').normalize('NFC')

/**
 * Το Word σπάει συχνά ένα placeholder σε πολλά <w:t>. Ενοποιούμε ανά
 * παράγραφο <w:p> το κείμενο, κάνουμε την αντικατάσταση και το γράφουμε
 * πίσω στο πρώτο <w:t>, αδειάζοντας τα υπόλοιπα.
 */
export async function renderDocx(
  templateBytes: Uint8Array,
  ctx: unknown,
  specs: Map<string, FieldSpec>,
  overrides: Record<string, string> = {},
): Promise<{ bytes: Uint8Array; missing: string[]; payload: Record<string, string> }> {
  const zip = await JSZip.loadAsync(templateBytes)
  const file = zip.file('word/document.xml')
  if (!file) throw new Error('Μη έγκυρο αρχείο .docx: λείπει το word/document.xml')

  let xml = await file.async('string')
  const missing: string[] = []
  const payload: Record<string, string> = {}

  xml = xml.replace(/<w:p\b[^>]*>[\s\S]*?<\/w:p>/g, paragraph => {
    const texts = [...paragraph.matchAll(/<w:t(?:\s[^>]*)?>([\s\S]*?)<\/w:t>/g)]
    if (texts.length === 0) return paragraph
    const joined = texts.map(t => t[1]).join('')
    if (!joined.includes('{{')) return paragraph

    const replaced = joined.replace(PLACEHOLDER, (_f, path: string) => {
      const { text, missing: isMissing } = valueFor(path, ctx, specs, overrides)
      payload[path] = text
      if (isMissing && !missing.includes(path)) missing.push(path)
      return text
    })

    let first = true
    return paragraph.replace(/(<w:t(?:\s[^>]*)?>)([\s\S]*?)(<\/w:t>)/g, (_m, open, _content, close) => {
      if (first) {
        first = false
        const tag = open.includes('xml:space') ? open : open.replace('<w:t', '<w:t xml:space="preserve"')
        return `${tag}${XML_ESC(replaced)}${close}`
      }
      return `${open}${close}`
    })
  })

  zip.file('word/document.xml', xml)
  const out = await zip.generateAsync({ type: 'uint8array', compression: 'DEFLATE' })
  return { bytes: out, missing, payload }
}

export async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes as BufferSource)
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('')
}
