/**
 * Δοκιμαστήριο της Edge Function generate-document χωρίς δίκτυο.
 *
 * Φορτώνει τον ΠΡΑΓΜΑΤΙΚΟ κώδικα (context.ts / render.ts / format.ts) μέσω
 * esbuild και τον τρέχει πάνω σε πραγματικές εγγραφές της βάσης (fixture.json),
 * με ψεύτικο πελάτη Supabase που απαντά από το fixture.
 *
 *   node tests/fnharness/harness.mjs
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'
import { webcrypto } from 'node:crypto'

if (!globalThis.crypto) globalThis.crypto = webcrypto

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const FN = resolve(ROOT, 'supabase/functions/generate-document')
const OUT = resolve(HERE, 'out')
mkdirSync(OUT, { recursive: true })

/* ---- 1. Μεταγλώττιση του κώδικα της συνάρτησης ------------------- */
const denoAlias = {
  name: 'deno-alias',
  setup(b) {
    b.onResolve({ filter: /^npm:jszip/ }, () => ({ path: 'jszip', external: true }))
    b.onResolve({ filter: /^jsr:@supabase/ }, () => ({
      path: resolve(HERE, 'supabase-stub.mjs'),
    }))
  },
}
writeFileSync(resolve(HERE, 'supabase-stub.mjs'), 'export const createClient = () => {}\n')

await build({
  entryPoints: [resolve(HERE, 'entry.ts')],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node20',
  outfile: resolve(OUT, 'bundle.mjs'),
  plugins: [denoAlias],
  logLevel: 'warning',
})

const mod = await import(resolve(OUT, 'bundle.mjs'))
const { buildContext, renderHtmlBody, wrapDocument, sha256, formatValue } = mod

/* ---- 2. Ψεύτικος πελάτης Supabase ------------------------------- */
const templates = JSON.parse(readFileSync(resolve(HERE, 'templates.json'), 'utf8'))
const fields = JSON.parse(readFileSync(resolve(HERE, 'template_fields.json'), 'utf8'))

/** Δύο σενάρια: έργο σε εκτέλεση και έργο σε περαίωση. */
const CASES = [
  { name: 'ΔΡ-2026/014 (σε εκτέλεση)', fixture: JSON.parse(readFileSync(resolve(HERE, 'fixture.json'), 'utf8')) },
  { name: 'ΔΡ-2025/007 (σε περαίωση)', fixture: JSON.parse(readFileSync(resolve(HERE, 'fixture2.json'), 'utf8')) },
]

function makeClient(fixture, queried) {
  const tableData = table => {
    queried.add(table)
    const v = fixture[table]
    if (v === undefined || v === null) return []
    return Array.isArray(v) ? v : [v]
  }
  const builder = table => {
    const rows = tableData(table)
    const api = {
      select: () => api,
      eq: () => api,
      is: () => api,
      order: () => api,
      limit: () => api,
      single: async () => ({ data: rows[0] ?? null, error: rows[0] ? null : { message: 'no rows' } }),
      maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
      then: (res, rej) => Promise.resolve({ data: rows, error: null }).then(res, rej),
    }
    return api
  }
  return { from: builder }
}

function legalLabel(ref) {
  if (!ref) return null
  if (ref === 'PD305/1996') return 'π.δ. 305/1996'
  if (ref.startsWith('N4412/')) {
    const [article, paragraph] = ref.slice(6).split('/')
    const map = { '1e': '1ε', '3a': '3α', '3b': '3β', '3c': '3γ', '14b': '14β' }
    return paragraph
      ? `άρθρο ${article} παρ. ${map[paragraph] ?? paragraph} ν. 4412/2016`
      : `άρθρο ${article} ν. 4412/2016`
  }
  return ref
}

/** Ποια πρότυπα έχουν νόημα σε κάθε σενάριο (τα υπόλοιπα δεν ελέγχονται). */
const APPLICABLE = {
  0: ['APOFASI_ORISMOU', 'EGKRISI_XRONOD', 'PPAE', 'ANAL_EPIMETRISI'],
  1: ['APOFASI_ORISMOU', 'ANAL_EPIMETRISI', 'BEBAIOSI_PERATOSIS', 'PRAXH_MEIWSHS_EGG'],
}

let failures = 0
const summary = []

for (const [ci, kase] of CASES.entries()) {
  const fixture = kase.fixture
  const queried = new Set()
  const sb = makeClient(fixture, queried)
  const entityId = {
    PPAE: fixture.hidden_work_notices?.id,
    ANAL_EPIMETRISI: fixture.measurements?.id,
    PRAXH_MEIWSHS_EGG: fixture.guarantees?.id,
  }

  for (const t of templates) {
    const specs = new Map(fields.filter(f => f.template_id === t.id).map(f => [f.placeholder, f]))
    const ctx = await buildContext(sb, {
      projectId: fixture.projects.id,
      docCode: t.doc_code,
      entityId: entityId[t.doc_code] ?? null,
    })
    const org = ctx.organizations ?? {}

    const rendered = renderHtmlBody(t.body_html, ctx, specs, {})
    const subject = renderHtmlBody(t.subject_template ?? t.title, ctx, specs, {}).html
    const signatories = (t.signatories ?? []).map(s => ({
      label: s.label,
      name: renderHtmlBody(s.name, ctx, specs, {}).html,
      capacity: s.capacity ? renderHtmlBody(s.capacity, ctx, specs, {}).html : undefined,
    }))

    const html = wrapDocument({
      orgName: org.name ?? 'ΟΡΓΑΝΙΣΜΟΣ',
      orgUnit: org.unit ?? null,
      orgAddress: org.address ?? null,
      orgPhone: org.phone ?? null,
      orgEmail: org.email ?? null,
      title: t.title,
      subject,
      protocolNo: `2026/${1000 + templates.indexOf(t)}`,
      protocolDate: formatValue(new Date().toISOString().slice(0, 10), 'date'),
      ada: null,
      legalRef: legalLabel(t.legal_ref_id),
      bodyHtml: rendered.html,
      signatories,
      recipients: [ctx.anadoxos?.epwnymia ?? 'Ο ανάδοχος', 'Φάκελο έργου'],
    })

    const applies = APPLICABLE[ci].includes(t.doc_code)
    if (applies) writeFileSync(resolve(OUT, `${ci}_${t.doc_code}.html`), html, 'utf8')

    // ---- Έλεγχοι -------------------------------------------------
    const leftover = [...new Set([...html.matchAll(/\{\{\s*[^}]+\}\}/g)].map(m => m[0]))]
    const dashes = (rendered.html.match(/—/g) ?? []).length
    const checksum = await sha256(new TextEncoder().encode(html))
    const problems = []
    if (leftover.length) problems.push(`αναντικατάστατα: ${leftover.join(', ')}`)
    if (html.includes('undefined')) problems.push('περιέχει «undefined»')
    if (html.includes('[object Object]')) problems.push('περιέχει «[object Object]»')
    if (html.includes('NaN')) problems.push('περιέχει «NaN»')
    if (applies && rendered.missing.length) {
      problems.push(`υποχρεωτικά κενά: ${rendered.missing.join(', ')}`)
    }
    if (!applies && problems.length === 0) continue // δεν αφορά το σενάριο
    if (problems.length) failures++

    summary.push({
      kase: kase.name,
      doc: t.doc_code,
      placeholders: Object.keys(rendered.payload).length,
      kena: dashes,
      bytes: html.length,
      checksum: checksum.slice(0, 12),
      problems,
      tables: [...queried].sort().join(', '),
    })
  }
}

/* ---- 4. Αναφορά -------------------------------------------------- */
console.log('\n═══ Παραγωγή εγγράφων — αποτελέσματα ═══')
let last = ''
for (const s of summary) {
  if (s.kase !== last) {
    console.log(`\n▸ ${s.kase}`)
    last = s.kase
  }
  const mark = s.problems.length ? '✗' : '✓'
  console.log(
    `  ${mark} ${s.doc.padEnd(20)} πεδία=${String(s.placeholders).padStart(3)}  ` +
      `κενά=${String(s.kena).padStart(2)}  ${String(s.bytes).padStart(6)} bytes  sha=${s.checksum}`,
  )
  for (const p of s.problems) console.log(`      → ${p}`)
}
console.log(
  failures === 0
    ? '\nΟΛΑ ΤΑ ΠΡΟΤΥΠΑ ΑΠΟΔΟΘΗΚΑΝ ΚΑΘΑΡΑ.\n'
    : `\n${failures} πρότυπα με ευρήματα.\n`,
)
process.exit(failures === 0 ? 0 : 1)
