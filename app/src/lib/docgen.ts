/**
 * Παραγωγή εγγράφων στη ΛΕΙΤΟΥΡΓΙΑ ΕΠΙΔΕΙΞΗΣ.
 *
 * Στην παραγωγή, τα έγγραφα παράγονται από την Edge Function
 * `generate-document`, με τα δικαιώματα του συνδεδεμένου χρήστη (RLS) και
 * με απόδοση αριθμού πρωτοκόλλου. Εδώ αναπαράγεται η ίδια λογική τοπικά,
 * ώστε η εφαρμογή να μπορεί να επιδειχθεί χωρίς υποδομή.
 *
 * Η ΜΟΝΗ πηγή αλήθειας παραμένει η βάση και η Edge Function· αυτό το
 * module υπάρχει για την προεπισκόπηση.
 */
import TEMPLATES from '@/data/templates.json'
import { formatLegalRef } from './labels'
import type {
  Completion, Contract, Guarantee, HiddenWorkNotice, Measurement, Project,
} from './types'

/* ------------------------------------------------------------------ */
/* Πρότυπα                                                             */
/* ------------------------------------------------------------------ */
export interface TemplateField {
  label: string
  source_kind: string
  source_path: string | null
  data_type: string
  is_required: boolean
}

export interface DocTemplate {
  doc_code: string
  title: string
  stage_code: string
  legal_ref_id: string
  subject_template: string
  signatories: { label: string; name: string; capacity?: string }[]
  body_html: string
  fields: Record<string, TemplateField>
}

export const TEMPLATE_LIST = TEMPLATES as unknown as DocTemplate[]
export const TEMPLATE_BY_CODE: Record<string, DocTemplate> = Object.fromEntries(
  TEMPLATE_LIST.map(t => [t.doc_code, t]),
)
/** Ποια στάδια του οδηγού διαθέτουν έτοιμο πρότυπο. */
export const TEMPLATE_BY_STAGE: Record<string, DocTemplate[]> = TEMPLATE_LIST.reduce(
  (acc, t) => {
    ;(acc[t.stage_code] ??= []).push(t)
    return acc
  },
  {} as Record<string, DocTemplate[]>,
)

/* ------------------------------------------------------------------ */
/* Μορφοποίηση (ίδια με supabase/functions/generate-document/format.ts) */
/* ------------------------------------------------------------------ */
const EUR = new Intl.NumberFormat('el-GR', {
  style: 'currency', currency: 'EUR', minimumFractionDigits: 2, maximumFractionDigits: 2,
})
const NUM = new Intl.NumberFormat('el-GR', { maximumFractionDigits: 2 })
const QTY = new Intl.NumberFormat('el-GR', { maximumFractionDigits: 4 })
const DATE = new Intl.DateTimeFormat('el-GR', { day: '2-digit', month: '2-digit', year: 'numeric' })
const DATE_LONG = new Intl.DateTimeFormat('el-GR', {
  weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
})

function toDate(v: unknown): Date | null {
  if (!v) return null
  const s = String(v)
  const d = new Date(s.length === 10 ? `${s}T00:00:00` : s)
  return isNaN(d.getTime()) ? null : d
}

export function formatValue(value: unknown, dataType = 'text'): string {
  if (value === null || value === undefined || value === '') return '—'
  const n = Number(value)
  switch (dataType) {
    case 'currency': return isNaN(n) ? String(value) : EUR.format(n)
    case 'number': return isNaN(n) ? String(value) : NUM.format(n)
    case 'quantity': return isNaN(n) ? String(value) : QTY.format(n)
    case 'date': { const d = toDate(value); return d ? DATE.format(d) : String(value) }
    case 'date_long': { const d = toDate(value); return d ? DATE_LONG.format(d) : String(value) }
    case 'boolean': return value ? 'ΝΑΙ' : 'ΟΧΙ'
    default: return String(value)
  }
}

function inferType(key: string, value: unknown): string {
  if (typeof value === 'number') {
    return /poso|aksia|dapani|timi|synolo|ypoloipo|amount/i.test(key) ? 'currency' : 'number'
  }
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value)) return 'date'
  if (typeof value === 'boolean') return 'boolean'
  return 'text'
}

const escapeHtml = (s: string) =>
  s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))

/**
 * Κεφαλαιοποίηση κατά τους κανόνες της ελληνικής: τα κεφαλαία ΔΕΝ φέρουν
 * τόνο (ΑΠΟΦΑΣΗ, όχι ΑΠΌΦΑΣΗ), αλλά τα διαλυτικά διατηρούνται (Ϊ, Ϋ).
 * Εφαρμόζεται στον κώδικα ώστε να είναι ανεξάρτητη από τη μηχανή απόδοσης.
 */
export const grUpper = (s: string) =>
  s.toUpperCase().normalize('NFD').replace(/[̀́͂΄]/g, '').normalize('NFC')

const addDays = (iso: string, days: number) => {
  const d = new Date(`${iso}T00:00:00`)
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}

/* ------------------------------------------------------------------ */
/* Περιβάλλον εγγράφου                                                 */
/* ------------------------------------------------------------------ */
export interface DocContext {
  org: { name: string; unit: string | null; address?: string | null; phone?: string | null; email?: string | null }
  project: Project
  contract?: Contract
  supervisor?: { full_name: string; specialty: string | null }
  head?: { full_name: string; specialty: string | null }
  entity?: {
    hidden?: HiddenWorkNotice
    measurement?: Measurement
    lines?: { aa: number; arthro: string; perigrafi: string; monada: string; timi: string; posotita: string; dapani: string }[]
    guarantee?: Guarantee
    completion?: Completion
    finalApprovedAt?: string | null
    scheduleSubmittedAt?: string | null
  }
}

/** Επίπεδο αντικείμενο με τις διαδρομές που δέχονται τα πρότυπα. */
export function buildContext(c: DocContext): Record<string, unknown> {
  const { project: p, contract: k, entity: e } = c
  const issued = e?.completion?.certificate_issued_at ?? null

  return {
    organizations: c.org,
    projects: p,
    ergo: {
      titlos: p.title, kodikos: p.code, thesi: p.location,
      xrimatodotisi: p.funding_source, proypologismos_meletis: p.study_budget_net,
    },
    contracts: k ?? {},
    contractors: k ? { name: k.contractor_name, afm: k.contractor_afm } : {},
    symvasi: k
      ? {
          arithmos: k.contract_no, imerominia_ypografis: k.signed_at,
          aksia: k.initial_value_net, ekptosi: k.discount_pct,
          apravlepta: k.contingency_amount, prothesmia_imeres: k.total_duration_days,
          lixi_prothesmias: k.current_end_date, mines_syntirisis: k.maintenance_months,
        }
      : {},
    anadoxos: k ? { epwnymia: k.contractor_name, afm: k.contractor_afm } : {},
    supervisor: c.supervisor ?? {},
    epivlepon: c.supervisor ?? {},
    head: c.head ?? {},
    proistamenos: c.head ?? {},

    hidden_work_notices: e?.hidden ?? {},
    afaneis: e?.hidden
      ? {
          aa: e.hidden.serial_no, perigrafi: e.hidden.work_description,
          thesi: e.hidden.location,
          imerominia_prosklisis: e.hidden.invitation_sent_at,
          prothesmia_elegxou: e.hidden.inspection_due,
          imerominia_elegxou: e.hidden.inspected_at,
          imerominia_elegxou_pliris: formatValue(e.hidden.inspected_at, 'date_long'),
          plithos_fotografion: e.hidden.photos_count,
        }
      : {},

    measurements: e?.measurement ?? {},
    grammes: e?.lines ?? [],
    epimetrisi: e?.measurement
      ? {
          aa: e.measurement.serial_no,
          periodos:
            e.measurement.period_from && e.measurement.period_to
              ? `${formatValue(e.measurement.period_from, 'date')} – ${formatValue(e.measurement.period_to, 'date')}`
              : '—',
          tmima: e.measurement.work_section,
          imerominia_ypovolis: e.measurement.submitted_at,
          synolo_symvatikwn: e.measurement.contractual_amount,
          synolo_ektos: e.measurement.extra_amount,
          geniko_synolo: e.measurement.total_amount,
        }
      : {},

    guarantees: e?.guarantee ?? {},
    eggyisi: e?.guarantee
      ? {
          arithmos: e.guarantee.guarantee_no, ekdotis: e.guarantee.issuer,
          arxiko_poso: e.guarantee.current_amount,
          poso_meiosis: Math.round(e.guarantee.current_amount * 0.7 * 100) / 100,
          ypoloipo: Math.round(e.guarantee.current_amount * 0.3 * 100) / 100,
        }
      : {},
    final_measurement: { approved_at: e?.finalApprovedAt ?? null },
    teliki: { imerominia_egkrisis: e?.finalApprovedAt ?? null },

    completions: e?.completion ?? {},
    peraiosi: e?.completion
      ? {
          egkekrimenos_xronos: e.completion.approved_completion_date,
          ekthesi_epivleponta: e.completion.supervisor_report_at,
          pragmatiki_imerominia:
            e.completion.actual_completion_date ?? e.completion.approved_completion_date,
          enarksi_syntirisis: issued ? addDays(issued, 1) : null,
        }
      : {},

    schedules: { submitted_at: e?.scheduleSubmittedAt ?? null },
    xronodiagramma: { imerominia_ypovolis: e?.scheduleSubmittedAt ?? null },

    computed: {
      maintenance_start: issued ? addDays(issued, 1) : null,
      inspection_date_long: formatValue(e?.hidden?.inspected_at, 'date_long'),
      guarantee_reduction: e?.guarantee ? Math.round(e.guarantee.current_amount * 0.7 * 100) / 100 : null,
      guarantee_remaining: e?.guarantee ? Math.round(e.guarantee.current_amount * 0.3 * 100) / 100 : null,
      measurement_period:
        e?.measurement?.period_from && e?.measurement?.period_to
          ? `${formatValue(e.measurement.period_from, 'date')} – ${formatValue(e.measurement.period_to, 'date')}`
          : null,
    },
  }
}

/* ------------------------------------------------------------------ */
/* Απόδοση                                                             */
/* ------------------------------------------------------------------ */
const PLACEHOLDER = /\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/g
const EACH = /\{\{\s*#each\s+([a-zA-Z0-9_]+)\s*\}\}/

const resolvePath = (ctx: unknown, path: string): unknown =>
  path.split('.').reduce<unknown>(
    (acc, key) => (acc === null || acc === undefined ? undefined : (acc as Record<string, unknown>)[key]),
    ctx,
  )

function valueFor(path: string, ctx: unknown, fields: Record<string, TemplateField>) {
  const spec = fields[`{{${path}}}`]
  let raw: unknown
  if (spec?.source_kind === 'computed' && spec.source_path) {
    raw = resolvePath(ctx, `computed.${spec.source_path}`)
  } else if (spec?.source_path && spec.source_kind !== 'manual') {
    raw = resolvePath(ctx, spec.source_path)
  }
  if (raw === undefined || raw === null) raw = resolvePath(ctx, path)
  const empty = raw === undefined || raw === null || raw === ''
  const type = spec?.data_type && spec.data_type !== 'table' ? spec.data_type : inferType(path, raw)
  return { text: empty ? '—' : formatValue(raw, type), missing: empty && (spec?.is_required ?? false) }
}

export interface RenderResult { html: string; missing: string[] }

export function renderBody(
  body: string,
  ctx: unknown,
  fields: Record<string, TemplateField>,
): RenderResult {
  const missing: string[] = []

  let out = body.replace(/<tr\b[^>]*>[\s\S]*?<\/tr>/g, row => {
    const m = row.match(EACH)
    if (!m) return row
    const collection = m[1]
    const items = (resolvePath(ctx, collection) as Record<string, unknown>[] | undefined) ?? []
    const tpl = row.replace(EACH, '')
    if (items.length === 0) return tpl.replace(PLACEHOLDER, '—')
    return items
      .map(item =>
        tpl.replace(PLACEHOLDER, (_f, path: string) => {
          if (path.startsWith(`${collection}.`)) {
            const v = item[path.slice(collection.length + 1)]
            return escapeHtml(v === undefined || v === null || v === '' ? '—' : String(v))
          }
          return escapeHtml(valueFor(path, ctx, fields).text)
        }),
      )
      .join('\n')
  })

  out = out.replace(PLACEHOLDER, (_f, path: string) => {
    const { text, missing: isMissing } = valueFor(path, ctx, fields)
    if (isMissing && !missing.includes(path)) missing.push(path)
    return escapeHtml(text)
  })

  return { html: out, missing }
}

/** Ολόκληρο έγγραφο, έτοιμο για εκτύπωση σε Α4 ή εξαγωγή σε PDF. */
export function wrapDocument(o: {
  org: DocContext['org']
  title: string
  subject: string
  protocolNo: string | null
  protocolDate: string
  legalRef: string | null
  bodyHtml: string
  signatories: { label: string; name: string; capacity?: string }[]
  recipients: string[]
}): string {
  const sig = o.signatories
    .map(
      s => `<div class="sig"><div class="sig-label">${escapeHtml(s.label)}</div>
      <div class="sig-space"></div><div class="sig-name">${escapeHtml(s.name)}</div>
      ${s.capacity ? `<div class="sig-cap">${escapeHtml(s.capacity)}</div>` : ''}</div>`,
    )
    .join('')

  return `<!doctype html><html lang="el"><head><meta charset="utf-8">
<title>${escapeHtml(o.title)}</title><style>
@page { size: A4; margin: 20mm 18mm 18mm 22mm; }
*{box-sizing:border-box}
body{font-family:"Times New Roman",Times,serif;font-size:11.5pt;line-height:1.5;color:#111;
     margin:0;padding:16mm 14mm;background:#fff}
.head{display:flex;justify-content:space-between;gap:16mm;border-bottom:1.5pt solid #111;padding-bottom:4mm}
.head .org{font-size:10.5pt;line-height:1.35}
.head .org .rep{font-weight:700;letter-spacing:.04em}
.head .org .name{font-weight:700}
.head .org .unit{text-transform:uppercase}
.head .org .contact{margin-top:2mm;font-size:9pt;color:#444}
.head .prot{text-align:right;font-size:10.5pt;white-space:nowrap}
.head .prot div{margin-bottom:1.5mm}
.subject{margin:7mm 0 5mm;font-size:11pt}
h1{font-size:13pt;text-align:center;letter-spacing:.08em;margin:6mm 0 5mm}
.legal{text-align:center;font-size:9.5pt;color:#555;margin:-3mm 0 6mm}
p{margin:0 0 3.5mm;text-align:justify}
ol.grounds{margin:0 0 5mm;padding-left:8mm}
ol.grounds li{margin-bottom:2mm;text-align:justify}
.declare{text-align:center;font-weight:700;letter-spacing:.3em;margin:6mm 0 4mm}
table.data{width:100%;border-collapse:collapse;margin:4mm 0 5mm;font-size:10.5pt}
table.data th{text-align:left;width:38%;padding:1.8mm 3mm;background:#f2f2f2;border:.6pt solid #999;font-weight:600}
table.data td{padding:1.8mm 3mm;border:.6pt solid #999}
table.grid{width:100%;border-collapse:collapse;margin:4mm 0;font-size:9.5pt}
table.grid th,table.grid td{border:.6pt solid #666;padding:1.4mm 2mm}
table.grid thead th{background:#e8e8e8;font-weight:700;text-align:center}
table.grid tfoot td{background:#f6f6f6;font-weight:600}
table.grid tfoot tr.total td{background:#e0e0e0;font-weight:700}
.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.note{font-size:10pt;color:#333;margin-top:4mm}
.signatures{display:flex;justify-content:space-around;gap:12mm;margin-top:14mm;page-break-inside:avoid}
.sig{text-align:center;min-width:55mm}
.sig-label{font-size:10pt;margin-bottom:1mm}
.sig-space{height:18mm}
.sig-name{font-weight:700;border-top:.8pt solid #111;padding-top:1.5mm;font-size:10.5pt}
.sig-cap{font-size:9pt;color:#555}
.recipients{margin-top:10mm;font-size:9.5pt}
.recipients b{display:block;margin-bottom:1.5mm}
.recipients ol{margin:0;padding-left:6mm}
@media print{body{padding:0}}
</style></head><body>
<header class="head">
  <div class="org">
    <div class="rep">ΕΛΛΗΝΙΚΗ ΔΗΜΟΚΡΑΤΙΑ</div>
    <div class="name">${escapeHtml(o.org.name)}</div>
    ${o.org.unit ? `<div class="unit">${escapeHtml(o.org.unit)}</div>` : ''}
    <div class="contact">${o.org.address ? escapeHtml(o.org.address) + '<br>' : ''}
      ${o.org.phone ? 'Τηλ.: ' + escapeHtml(o.org.phone) : ''}
      ${o.org.email ? ' · ' + escapeHtml(o.org.email) : ''}</div>
  </div>
  <div class="prot">
    <div>Ρόδος, ${escapeHtml(o.protocolDate)}</div>
    ${o.protocolNo ? `<div>Αρ. Πρωτ.: <b>${escapeHtml(o.protocolNo)}</b></div>` : ''}
  </div>
</header>
<div class="subject"><b>ΘΕΜΑ:</b> ${escapeHtml(o.subject)}</div>
<h1>${escapeHtml(grUpper(o.title))}</h1>
${o.legalRef ? `<div class="legal">(${escapeHtml(o.legalRef)})</div>` : ''}
${o.bodyHtml}
<div class="signatures">${sig}</div>
${o.recipients.length
    ? `<div class="recipients"><b>ΚΟΙΝΟΠΟΙΗΣΗ:</b><ol>${o.recipients
        .map(r => `<li>${escapeHtml(r)}</li>`)
        .join('')}</ol></div>`
    : ''}
</body></html>`
}

/** Πλήρης παραγωγή ενός εγγράφου από πρότυπο και δεδομένα έργου. */
export function generate(
  docCode: string,
  c: DocContext,
  protocolNo: string | null = null,
): { html: string; missing: string[]; template: DocTemplate } {
  const t = TEMPLATE_BY_CODE[docCode]
  if (!t) throw new Error(`Δεν υπάρχει διαθέσιμο πρότυπο για τον κωδικό «${docCode}».`)
  const ctx = buildContext(c)
  const body = renderBody(t.body_html, ctx, t.fields)
  const subject = renderBody(t.subject_template, ctx, t.fields).html
  return {
    template: t,
    missing: body.missing,
    html: wrapDocument({
      org: c.org,
      title: t.title,
      subject,
      protocolNo,
      protocolDate: formatValue(new Date().toISOString().slice(0, 10), 'date'),
      legalRef: formatLegalRef(t.legal_ref_id),
      bodyHtml: body.html,
      signatories: t.signatories.map(s => ({
        label: s.label,
        name: renderBody(s.name, ctx, t.fields).html,
        capacity: s.capacity ? renderBody(s.capacity, ctx, t.fields).html : undefined,
      })),
      recipients: [c.contract?.contractor_name ?? 'Ο ανάδοχος', 'Φάκελο έργου'],
    }),
  }
}
