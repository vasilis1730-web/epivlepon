/**
 * Σύνταξη λογαριασμού (άρθρο 152 ν. 4412/2016).
 *
 * Ο λογαριασμός είναι ΣΩΡΕΥΤΙΚΟΣ: αποτυπώνει το σύνολο των εργασιών από
 * την αρχή του έργου και αφαιρεί ό,τι έχει ήδη πιστοποιηθεί. Γι' αυτό τα
 * ποσά της περιόδου, οι κρατήσεις και το πληρωτέο δεν πληκτρολογούνται —
 * υπολογίζονται από τα σωρευτικά μεγέθη και τους προηγούμενους λογαριασμούς.
 *
 * Προϋπόθεση πληρωμής είναι η εγκεκριμένη επιμέτρηση (άρθρο 151 §2).
 */
import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import * as api from '@/lib/api'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import {
  Badge, BlockerList, Button, Card, CardHeader, Field, Input, LegalRef,
  Select, Spinner,
} from '@/components/ui'
import { MEASUREMENT_STATUS } from '@/lib/labels'
import { addMonths, cx, date, eur, today } from '@/lib/format'
import { paymentTotals, paymentViolations } from '@/lib/rules'
import type { NewPaymentInput, PaymentCertificate } from '@/lib/types'

type Ptype = PaymentCertificate['ptype']

const PTYPE: Record<Ptype, string> = {
  tmimatikos: 'Τμηματικός',
  telikos: 'Τελικός',
  prokatavoli: 'Προκαταβολή',
}

interface PaymentForm {
  ptype: Ptype
  period_from: string
  period_to: string
  measurement_id: string
  submitted_at: string
  works_cumulative: number
  ge_oe_amount: number
  apologistika_amount: number
  revision_amount: number
  compensations: number
  advance_amortization: number
  penalties_amount: number
  other_deductions: number
  retentions_pct: number
  vat_rate: number
  has_summary_table: boolean
  has_revision_calc: boolean
}

/** Μόνο τα αριθμητικά πεδία — ώστε ο βοηθός `num` να μη δέχεται κατά λάθος
 *  πεδίο κειμένου ή σημαία. */
type NumericField = {
  [K in keyof PaymentForm]: PaymentForm[K] extends number ? K : never
}[keyof PaymentForm]

export default function NewPayment() {
  const { projectId = '' } = useParams()
  const nav = useNavigate()
  const { push } = useToast()

  const { data, loading } = useQuery(async () => {
    const [contract, payments, measurements, acceptanceApproved] = await Promise.all([
      api.getContract(projectId), api.getPayments(projectId),
      api.getMeasurements(projectId), api.isAcceptanceApproved(projectId),
    ])
    return { contract, payments, measurements, acceptanceApproved }
  }, [projectId])

  const [f, setF] = useState<PaymentForm>({
    ptype: 'tmimatikos',
    period_from: '',
    period_to: today(),
    measurement_id: '',
    submitted_at: today(),
    works_cumulative: 0,
    ge_oe_amount: 0,
    apologistika_amount: 0,
    revision_amount: 0,
    compensations: 0,
    advance_amortization: 0,
    penalties_amount: 0,
    other_deductions: 0,
    retentions_pct: 5,
    vat_rate: 24,
    has_summary_table: false,
    has_revision_calc: false,
  })
  const [busy, setBusy] = useState(false)
  const [seeded, setSeeded] = useState(false)

  const set = <K extends keyof PaymentForm>(k: K, v: PaymentForm[K]) =>
    setF(s => ({ ...s, [k]: v }))

  // Οι εγκεκριμένες (ρητά ή σιωπηρά) επιμετρήσεις είναι οι μόνες που
  // θεμελιώνουν πληρωμή — άρθρο 151 §2.
  const approvedMeasurements = useMemo(
    () => (data?.measurements ?? []).filter(
      m => ['approved', 'deemed_approved'].includes(m.status)),
    [data?.measurements],
  )

  useEffect(() => {
    if (seeded || !data) return
    const prior = data.payments
    const last = prior.reduce<PaymentCertificate | undefined>(
      (acc, p) => (!acc || p.serial_no > acc.serial_no ? p : acc), undefined)
    const m = approvedMeasurements[approvedMeasurements.length - 1]
    setF(s => ({
      ...s,
      // Η περίοδος συνεχίζει από εκεί που σταμάτησε ο προηγούμενος.
      period_from: last?.period_to ?? data.contract?.signed_at ?? '',
      measurement_id: m?.id ?? '',
      // Αφετηρία τα σωρευτικά της επιμέτρησης — ο χρήστης τα επιβεβαιώνει.
      works_cumulative: m?.total_amount ?? 0,
      vat_rate: data.contract?.vat_rate ?? 24,
      has_revision_calc: Boolean(last),
    }))
    setSeeded(true)
  }, [data, approvedMeasurements, seeded])

  const totals = useMemo(
    () => paymentTotals(f, data?.payments ?? []),
    [f, data?.payments],
  )

  if (loading || !data?.contract) return <Spinner />

  const measurement = data.measurements.find(m => m.id === f.measurement_id)
  // Άρθρο 172 — έγκριση πρωτοκόλλου παραλαβής, όχι Βεβαίωση Περάτωσης.
  const acceptanceApproved = data.acceptanceApproved

  // Ο ίδιος έλεγχος που θα εφαρμοστεί κατά την έγκριση.
  const violations = paymentViolations(
    {
      id: 'draft', project_id: projectId, ptype: f.ptype, serial_no: 0,
      period_from: f.period_from || null, period_to: f.period_to || null,
      measurement_id: f.measurement_id || null,
      submitted_at: f.submitted_at, approval_due: addMonths(f.submitted_at, 1),
      approved_at: null, status: 'submitted',
      gross_cumulative: totals.gross, previous_certified: totals.previousCertified,
      period_amount: totals.period, advance_amortization: f.advance_amortization,
      penalties_amount: f.penalties_amount, retentions_amount: totals.retentions,
      net_payable: totals.net, vat_amount: totals.vat,
      has_summary_table: f.has_summary_table, has_revision_calc: f.has_revision_calc,
      paid_at: null,
    },
    measurement,
    acceptanceApproved,
  )
  const hard = violations.filter(v => v.severity === 'hard')

  const problems: string[] = []
  if (totals.gross <= 0) problems.push('Τα σωρευτικά μεγέθη είναι μηδενικά.')
  if (totals.period < 0) {
    problems.push(
      'Το ποσό περιόδου προκύπτει αρνητικό: τα σωρευτικά υπολείπονται όσων έχουν ' +
      'ήδη πιστοποιηθεί. Ελέγξτε τη σωρευτική δαπάνη εργασιών.',
    )
  }

  async function save() {
    setBusy(true)
    try {
      const input: NewPaymentInput = {
        project_id: projectId,
        ptype: f.ptype,
        period_from: f.period_from || null,
        period_to: f.period_to || null,
        measurement_id: f.measurement_id || null,
        submitted_at: f.submitted_at,
        works_cumulative: f.works_cumulative,
        ge_oe_amount: f.ge_oe_amount,
        apologistika_amount: f.apologistika_amount,
        revision_amount: f.revision_amount,
        compensations: f.compensations,
        advance_amortization: f.advance_amortization,
        penalties_amount: f.penalties_amount,
        other_deductions: f.other_deductions,
        retentions_pct: f.retentions_pct,
        vat_rate: f.vat_rate,
        has_summary_table: f.has_summary_table,
        has_revision_calc: f.has_revision_calc,
      }
      const r = await api.createPayment(input)
      push('success', `Καταχωρήθηκε ο ${r.serialNo}ος λογαριασμός`,
        `Προθεσμία έγκρισης: ${date(addMonths(f.submitted_at, 1))} (άρθρο 152).`)
      nav(`/erga/${projectId}/logariasmoi`)
    } catch (e) {
      push('error', 'Η καταχώριση απέτυχε', e instanceof Error ? e.message : undefined)
    } finally {
      setBusy(false)
    }
  }

  const num = (k: NumericField) => (
    <Input type="number" step="0.01" value={f[k] || ''} className="text-right"
      onChange={e => set(k, Number(e.target.value) || 0)} />
  )

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρο 152 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Σύνταξη λογαριασμού</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Συμπληρώνετε τα <strong>σωρευτικά</strong> μεγέθη από την αρχή του έργου.
          Το ποσό περιόδου, οι κρατήσεις και το πληρωτέο υπολογίζονται αυτόματα
          αφαιρώντας όσα έχουν ήδη πιστοποιηθεί.
        </p>
      </header>

      <Card>
        <CardHeader title="Ταυτότητα λογαριασμού" legalRef="N4412/152" />
        <div className="grid gap-4 px-4 py-4 sm:grid-cols-2 lg:grid-cols-4">
          <Field label="Είδος">
            <Select value={f.ptype} onChange={e => set('ptype', e.target.value as Ptype)}>
              {Object.entries(PTYPE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </Select>
          </Field>
          <Field label="Περίοδος από">
            <Input type="date" value={f.period_from}
              onChange={e => set('period_from', e.target.value)} />
          </Field>
          <Field label="Περίοδος έως">
            <Input type="date" value={f.period_to}
              onChange={e => set('period_to', e.target.value)} />
          </Field>
          <Field label="Ημ/νία υποβολής"
            hint={`Προθεσμία έγκρισης: ${date(addMonths(f.submitted_at, 1))}`}>
            <Input type="date" value={f.submitted_at}
              onChange={e => set('submitted_at', e.target.value)} />
          </Field>
          <div className="sm:col-span-2 lg:col-span-4">
            <Field label="Εγκεκριμένη επιμέτρηση" legalRef="N4412/151/2"
              hint="Η υποβολή και έγκριση επιμέτρησης είναι προϋπόθεση πληρωμής.">
              <Select value={f.measurement_id}
                onChange={e => set('measurement_id', e.target.value)}>
                <option value="">— καμία —</option>
                {approvedMeasurements.map(m => (
                  <option key={m.id} value={m.id}>
                    Α/Α {m.serial_no} · {eur(m.total_amount)} · {MEASUREMENT_STATUS[m.status]}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
        </div>
      </Card>

      <Card>
        <CardHeader title="Σωρευτικά μεγέθη (χωρίς ΦΠΑ)" legalRef="N4412/152" />
        <div className="grid gap-4 px-4 py-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="Δαπάνη εργασιών σωρευτικά">{num('works_cumulative')}</Field>
          <Field label="ΓΕ & ΟΕ">{num('ge_oe_amount')}</Field>
          <Field label="Απολογιστικά" legalRef="N4412/154">{num('apologistika_amount')}</Field>
          <Field label="Αναθεώρηση">{num('revision_amount')}</Field>
          <Field label="Αποζημιώσεις">{num('compensations')}</Field>
        </div>

        <CardHeader title="Κρατήσεις & μειώσεις" legalRef="N4412/152" />
        <div className="grid gap-4 px-4 py-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="Απόσβεση προκαταβολής" legalRef="N4412/150">
            {num('advance_amortization')}
          </Field>
          <Field label="Ποινικές ρήτρες"
            hint="Καταχωρίζονται ως υπολογισμός· η επιβολή είναι πράξη της Δ.Υ.">
            {num('penalties_amount')}
          </Field>
          <Field label="Λοιπές κρατήσεις">{num('other_deductions')}</Field>
          <Field label="Ποσοστό κρατήσεων %">{num('retentions_pct')}</Field>
          <Field label="Συντελεστής ΦΠΑ %">{num('vat_rate')}</Field>
        </div>

        <CardHeader title="Συνημμένα" legalRef="N4412/152" />
        <div className="grid gap-3 px-4 py-4 sm:grid-cols-2">
          <Check label="Ανακεφαλαιωτικός συνοπτικός πίνακας επιμετρήσεων"
            checked={f.has_summary_table}
            onChange={v => set('has_summary_table', v)} />
          <Check label="Υπολογισμός αναθεώρησης"
            checked={f.has_revision_calc}
            onChange={v => set('has_revision_calc', v)} />
        </div>
      </Card>

      <Card>
        <CardHeader title="Υπολογισμός" legalRef="N4412/152" />
        <div className="space-y-2 px-4 py-4 text-sm">
          <Row k="Σύνολο σωρευτικά (μικτό)" v={eur(totals.gross)} />
          <Row k="Μείον: προηγουμένως πιστοποιηθέντα" v={eur(-totals.previousCertified)} />
          <Row k="Ποσό περιόδου" v={eur(totals.period)} strong />
          {/* Το πρόσημο το αποδίδει ο μορφοποιητής: μια ΑΡΝΗΤΙΚΗ κράτηση είναι
              επιστροφή κρατήσεων και πρέπει να φαίνεται ως θετικό ποσό. */}
          <Row k={`Μείον: κρατήσεις ${f.retentions_pct}%`} v={eur(-totals.retentions)} />
          <Row k="Μείον: απόσβεση προκαταβολής" v={eur(-f.advance_amortization)} />
          <Row k="Μείον: ποινικές ρήτρες" v={eur(-f.penalties_amount)} />
          <Row k="Μείον: λοιπές κρατήσεις" v={eur(-f.other_deductions)} />
          <div className="border-t border-rule pt-2">
            <Row k="Πληρωτέο (καθαρό)" v={eur(totals.net)} strong />
            <Row k={`ΦΠΑ ${f.vat_rate}%`} v={eur(totals.vat)} />
            <Row k="Σύνολο με ΦΠΑ" v={eur(Math.round((totals.net + totals.vat) * 100) / 100)} strong />
          </div>
        </div>
      </Card>

      {violations.length > 0 && (
        <Card>
          <CardHeader title="Έλεγχος προϋποθέσεων" legalRef="N4412/152"
            right={hard.length
              ? <Badge tone="oxide">{hard.length} κωλύματα</Badge>
              : <Badge tone="brass">παρατηρήσεις</Badge>} />
          <div className="px-4 py-4"><BlockerList blockers={violations} /></div>
        </Card>
      )}

      {problems.length > 0 && (
        <Card>
          <div className="space-y-1.5 px-4 py-3 text-sm text-oxide">
            {problems.map(p => <p key={p}>• {p}</p>)}
          </div>
        </Card>
      )}

      <div className="flex flex-wrap items-center justify-end gap-2">
        <p className="mr-auto max-w-xl text-xs text-ink3">
          Ο λογαριασμός καταχωρίζεται ως <strong>υποβληθείς</strong>. Η άπρακτη πάροδο
          του μηνός καθιστά τον λογαριασμό εγκεκριμένο και πληρωτέο.{' '}
          <LegalRef id="N4412/152" />
        </p>
        <Button variant="secondary" onClick={() => nav(`/erga/${projectId}/logariasmoi`)}>
          Άκυρο
        </Button>
        <Button disabled={busy || problems.length > 0} onClick={save}>
          {busy ? 'Καταχώριση…' : 'Καταχώριση λογαριασμού'}
        </Button>
      </div>
    </div>
  )
}

function Row({ k, v, strong }: { k: string; v: string; strong?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className={cx('text-xs', strong ? 'text-ink' : 'text-ink3')}>{k}</span>
      <span className={cx('tnum shrink-0 font-mono text-xs',
        strong ? 'text-sm font-semibold text-ink' : 'text-ink2')}>{v}</span>
    </div>
  )
}

function Check({ label, checked, onChange }: {
  label: string; checked: boolean; onChange: (v: boolean) => void
}) {
  return (
    <label className="flex items-start gap-2 text-sm">
      <input type="checkbox" checked={checked} className="mt-0.5"
        onChange={e => onChange(e.target.checked)} />
      <span className={checked ? 'text-ink' : 'text-ink2'}>{label}</span>
    </label>
  )
}
