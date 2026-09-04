/**
 * Σύνταξη Ανακεφαλαιωτικού Πίνακα Εργασιών (άρθρο 156 §2 ν. 4412/2016).
 *
 * Ο ΑΠΕ ΔΕΝ γράφεται από το μηδέν: προσυμπληρώνεται από τα συμβατικά μεγέθη
 * (1ος ΑΠΕ) ή από τον τελευταίο εγκεκριμένο (2ος και επόμενοι), και ο
 * μηχανικός μεταβάλλει μόνο ΠΟΣΟΤΗΤΕΣ. Οι τιμές μονάδος είναι συμβατικές
 * και δεν αλλάζουν· νέα άρθρα εισάγονται ρητά, με Π.Κ.Τ.Μ.Ν.Ε. (§5).
 *
 * Τα τέσσερα όρια του άρθρου 156 ελέγχονται ΖΩΝΤΑΝΑ, ώστε η υπέρβαση να
 * φαίνεται πριν την καταχώριση και όχι ως σφάλμα του διακομιστή.
 */
import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import * as api from '@/lib/api'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import {
  Badge, BlockerList, Button, Card, CardHeader, Field, Input, LegalRef,
  Meter, Select, Spinner, Table, Td, Textarea, Th,
} from '@/components/ui'
import { WORK_GROUPS } from '@/lib/catalogue'
import { APE_TYPE } from '@/lib/labels'
import { cx, eur, qty, today } from '@/lib/format'
import { apeTotals, apeViolations } from '@/lib/rules'
import type { Ape, ApeLineDraft, ApeType, NewApeInput } from '@/lib/types'

const FUNDING: Record<ApeLineDraft['funding_source'], string> = {
  symvatiko: 'Συμβατικό',
  apravlepta: 'Απρόβλεπτα',
  epi_elasson: 'Επί έλασσον',
  symplirwmatiki: 'Συμπληρωματική',
  apologistika: 'Απολογιστικά',
}

export default function NewApe() {
  const { projectId = '' } = useParams()
  const nav = useNavigate()
  const { push } = useToast()

  const { data, loading } = useQuery(async () => {
    const [project, contract, apes, budget] = await Promise.all([
      api.getProject(projectId), api.getContract(projectId),
      api.getApes(projectId), api.getBudget(projectId),
    ])
    return { project, contract, apes, budget }
  }, [projectId])

  const [lines, setLines] = useState<ApeLineDraft[]>([])
  const [atype, setAtype] = useState<ApeType>('taktopoiitikos')
  const [reason, setReason] = useState('')
  const [draftedAt, setDraftedAt] = useState(today())
  const [supplementary, setSupplementary] = useState(false)
  const [busy, setBusy] = useState(false)
  const [seeded, setSeeded] = useState(false)

  /* --------------------------------------------------------------- */
  /* Προσυμπλήρωση                                                    */
  /* --------------------------------------------------------------- */
  // Βάση: ο τελευταίος ΕΓΚΕΚΡΙΜΕΝΟΣ ΑΠΕ· αν δεν υπάρχει, ο προϋπολογισμός.
  const previous: Ape | undefined = useMemo(() => {
    const approved = (data?.apes ?? []).filter(a => a.status === 'approved')
    return approved.sort((a, b) => b.serial_no - a.serial_no)[0]
  }, [data?.apes])

  useEffect(() => {
    if (seeded || !data) return
    if (previous) {
      // 2ος και επόμενοι: οι ποσότητες του προηγούμενου γίνονται «προηγούμενες»
      // και αφετηρία της νέας πρότασης.
      setLines(previous.lines.map(l => ({
        item_code: l.item_code, description: l.description, unit: l.unit,
        work_group: l.work_group, unit_price: l.unit_price,
        qty_initial: l.qty_initial, qty_previous: l.qty_new, qty_new: l.qty_new,
        funding_source: l.funding_source, is_new_item: l.is_new_item,
      })))
    } else if (data.budget?.items.length) {
      // 1ος ΑΠΕ: τα συμβατικά μεγέθη του προϋπολογισμού.
      setLines(data.budget.items.map(i => ({
        item_code: i.item_code, description: i.description, unit: i.unit,
        work_group: i.work_group, unit_price: i.unit_price,
        qty_initial: i.quantity, qty_previous: i.quantity, qty_new: i.quantity,
        funding_source: 'symvatiko' as const, is_new_item: false,
      })))
    }
    setSeeded(true)
  }, [data, previous, seeded])

  const groups = useMemo(
    () => WORK_GROUPS.filter(g => g.category === data?.project?.category),
    [data?.project?.category],
  )

  const totals = useMemo(
    () => apeTotals(lines, data?.contract?.initial_value_net ?? 0),
    [lines, data?.contract?.initial_value_net],
  )

  /* --------------------------------------------------------------- */
  /* Ζωντανός έλεγχος ορίων άρθρου 156                                */
  /* --------------------------------------------------------------- */
  const violations = useMemo(() => {
    if (!data?.contract) return []
    // Συντίθεται προσωρινός ΑΠΕ ώστε να περάσει από τους ΙΔΙΟΥΣ κανόνες που
    // θα εφαρμόσει η βάση κατά την έγκριση.
    const provisional: Ape = {
      id: 'draft', project_id: projectId, serial_no: 0, atype, reason,
      drafted_at: draftedAt,
      initial_contract_value: data.contract.initial_value_net,
      new_total_value: totals.newTotal,
      delta_amount: totals.delta,
      contingency_used: totals.contingencyUsed,
      savings_used: totals.savings,
      supplementary_needed: supplementary,
      tc_opinion_id: null, contractor_signature: null,
      status: 'draft', approved_at: null,
      lines: lines.map((l, i) => ({
        id: `d${i}`, work_group: l.work_group, item_code: l.item_code,
        description: l.description, unit: l.unit, unit_price: l.unit_price,
        qty_initial: l.qty_initial, qty_new: l.qty_new,
        amount_initial: Math.round(l.qty_initial * l.unit_price * 100) / 100,
        amount_new: Math.round(l.qty_new * l.unit_price * 100) / 100,
        delta_amount: Math.round((l.qty_new - l.qty_initial) * l.unit_price * 100) / 100,
        funding_source: l.funding_source, is_new_item: l.is_new_item,
      })),
    }
    const others = (data.apes ?? []).filter(a => a.status === 'approved')
    return apeViolations(provisional, data.contract, others)
  }, [data, lines, atype, reason, draftedAt, supplementary, totals, projectId])

  if (loading || !data?.contract) return <Spinner />
  const { contract, budget } = data

  const hasSource = Boolean(previous || budget?.items.length)
  if (!hasSource && seeded) return <NoBudget projectId={projectId} />

  const set = (i: number, patch: Partial<ApeLineDraft>) =>
    setLines(ls => ls.map((l, idx) => (idx === i ? { ...l, ...patch } : l)))

  const addNewItem = () =>
    setLines(ls => [...ls, {
      item_code: '', description: '', unit: '', work_group: '', unit_price: 0,
      qty_initial: 0, qty_previous: 0, qty_new: 0,
      funding_source: 'apravlepta', is_new_item: true,
    }])

  const removeLine = (i: number) => setLines(ls => ls.filter((_, idx) => idx !== i))

  const hard = violations.filter(v => v.severity === 'hard')
  const problems: string[] = []
  if (!reason.trim()) problems.push('Απαιτείται αιτιολόγηση της αναγκαιότητας (άρθρο 156 §2).')
  if (!lines.length) problems.push('Ο ΑΠΕ δεν περιέχει καμία γραμμή.')
  if (lines.some(l => l.is_new_item && (!l.item_code.trim() || l.unit_price <= 0))) {
    problems.push('Κάθε νέο άρθρο χρειάζεται κωδικό και τιμή μονάδος από Π.Κ.Τ.Μ.Ν.Ε.')
  }
  if (lines.some(l => !l.work_group)) {
    problems.push('Κάθε γραμμή πρέπει να ανήκει σε ομάδα εργασιών (άρθρο 156 §3γ).')
  }

  async function save() {
    setBusy(true)
    try {
      const input: NewApeInput = {
        project_id: projectId, atype, reason: reason.trim(),
        drafted_at: draftedAt, supplementary_needed: supplementary, lines,
      }
      const r = await api.createApe(input)
      push('success', `Καταχωρήθηκε ο ${r.serialNo}ος ΑΠΕ`,
        'Σε κατάσταση σχεδίου — εκκρεμεί υπογραφή αναδόχου και έγκριση.')
      nav(`/erga/${projectId}/ape`)
    } catch (e) {
      push('error', 'Η καταχώριση απέτυχε', e instanceof Error ? e.message : undefined)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρο 156 §2 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Σύνταξη Ανακεφαλαιωτικού Πίνακα</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          {previous
            ? `Οι γραμμές προσυμπληρώθηκαν από τον ${previous.serial_no}ο εγκεκριμένο ΑΠΕ.`
            : 'Οι γραμμές προσυμπληρώθηκαν από τα συμβατικά μεγέθη του προϋπολογισμού.'}{' '}
          Μεταβάλλετε μόνο τις νέες ποσότητες· οι τιμές μονάδος είναι συμβατικές.
        </p>
      </header>

      <Card>
        <CardHeader title="Στοιχεία πίνακα" legalRef="N4412/156/2" />
        <div className="grid gap-4 px-4 py-4 sm:grid-cols-2 lg:grid-cols-4">
          <Field label="Είδος ΑΠΕ">
            <Select value={atype} onChange={e => setAtype(e.target.value as ApeType)}>
              {Object.entries(APE_TYPE).map(([k, v]) => (
                <option key={k} value={k}>{v}</option>
              ))}
            </Select>
          </Field>
          <Field label="Ημερομηνία σύνταξης">
            <Input type="date" value={draftedAt} onChange={e => setDraftedAt(e.target.value)} />
          </Field>
          <Field label="Συμπληρωματική σύμβαση" hint="Ενεργοποιεί την υποχρέωση γνωμοδότησης Τ.Σ.">
            <Select value={supplementary ? '1' : '0'}
              onChange={e => setSupplementary(e.target.value === '1')}>
              <option value="0">Δεν απαιτείται</option>
              <option value="1">Απαιτείται</option>
            </Select>
          </Field>
          <Field label="Αξία αρχικής σύμβασης">
            <div className="tnum px-1 py-1.5 font-mono text-sm">{eur(contract.initial_value_net)}</div>
          </Field>
          <div className="sm:col-span-2 lg:col-span-4">
            <Field label="Αιτιολόγηση αναγκαιότητας" legalRef="N4412/156/2">
              <Textarea value={reason} onChange={e => setReason(e.target.value)}
                placeholder="Γιατί απαιτείται η τροποποίηση· ποιες συνθήκες προέκυψαν και πότε." />
            </Field>
          </div>
        </div>
      </Card>

      <Card>
        <CardHeader
          title="Γραμμές πίνακα"
          subtitle="Η στήλη «Νέα ποσότητα» είναι η μόνη που μεταβάλλεται ελεύθερα"
          right={<Badge tone="muted">{lines.length} γραμμές</Badge>}
        />
        <Table minWidth={1240}>
          <thead>
            <tr>
              <Th>Άρθρο</Th><Th>Περιγραφή</Th><Th>Ομάδα</Th><Th>Μον.</Th>
              <Th align="end">Τιμή</Th>
              <Th align="end">Ποσ. αρχική</Th><Th align="end">Ποσ. προηγ.</Th>
              <Th align="end">Ποσ. νέα</Th>
              <Th align="end">Μεταβολή</Th><Th>Πηγή</Th><Th align="end" />
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => {
              const delta = Math.round((l.qty_new - l.qty_initial) * l.unit_price * 100) / 100
              return (
                <tr key={i}>
                  <Td>
                    {l.is_new_item
                      ? <Input value={l.item_code} placeholder="ΝΕΟ-1" className="w-28"
                          onChange={e => set(i, { item_code: e.target.value })} />
                      : <span className="whitespace-nowrap font-mono text-xs">{l.item_code}</span>}
                  </Td>
                  <Td>
                    {l.is_new_item
                      ? <Input value={l.description} placeholder="Περιγραφή νέας εργασίας"
                          onChange={e => set(i, { description: e.target.value })} />
                      : <span className="text-sm">{l.description}</span>}
                  </Td>
                  <Td>
                    {l.is_new_item
                      ? <Select value={l.work_group}
                          onChange={e => set(i, { work_group: e.target.value })}>
                          <option value="">— επιλογή —</option>
                          {groups.map(g => (
                            <option key={g.code} value={g.title}>{g.code} · {g.title}</option>
                          ))}
                        </Select>
                      : <span className="text-xs text-ink2">{l.work_group}</span>}
                  </Td>
                  <Td>
                    {l.is_new_item
                      ? <Input value={l.unit} className="w-16"
                          onChange={e => set(i, { unit: e.target.value })} />
                      : <span className="text-xs">{l.unit}</span>}
                  </Td>
                  <Td align="end">
                    {l.is_new_item
                      ? <Input type="number" step="0.0001" min="0" value={l.unit_price || ''}
                          className="w-24 text-right"
                          onChange={e => set(i, { unit_price: Number(e.target.value) || 0 })} />
                      : <span className="tnum font-mono text-xs">{eur(l.unit_price)}</span>}
                  </Td>
                  <Td align="end" className="tnum font-mono text-xs text-ink3">{qty(l.qty_initial)}</Td>
                  <Td align="end" className="tnum font-mono text-xs text-ink3">{qty(l.qty_previous)}</Td>
                  <Td align="end">
                    <Input type="number" step="0.0001" min="0" value={l.qty_new || ''}
                      className="w-28 text-right"
                      onChange={e => set(i, { qty_new: Number(e.target.value) || 0 })} />
                  </Td>
                  <Td align="end"
                    className={cx('tnum font-mono text-xs font-semibold',
                      delta < 0 ? 'text-oxide' : delta > 0 ? 'text-accent' : 'text-ink3')}>
                    {delta > 0 ? '+' : ''}{eur(delta)}
                  </Td>
                  <Td>
                    <Select value={l.funding_source}
                      onChange={e => set(i, {
                        funding_source: e.target.value as ApeLineDraft['funding_source'],
                      })}>
                      {Object.entries(FUNDING).map(([k, v]) => (
                        <option key={k} value={k}>{v}</option>
                      ))}
                    </Select>
                  </Td>
                  <Td align="end">
                    {l.is_new_item && (
                      <Button variant="ghost" onClick={() => removeLine(i)}
                        aria-label="Διαγραφή νέου άρθρου">✕</Button>
                    )}
                  </Td>
                </tr>
              )
            })}
          </tbody>
        </Table>
        <div className="border-t border-rule px-4 py-3">
          <Button variant="secondary" onClick={addNewItem}>+ Νέο άρθρο (Π.Κ.Τ.Μ.Ν.Ε.)</Button>
        </div>
      </Card>

      <Card>
        <CardHeader title="Όρια τροποποιήσεων" legalRef="N4412/156/1" />
        <div className="grid gap-5 px-4 py-4 sm:grid-cols-3">
          <Limit label="Σωρευτική αύξηση" value={Math.max(0, totals.delta)}
            limit={contract.initial_value_net * 0.5}
            note="όριο 50% — άρθρο 156 §1" />
          <Limit label="Χρήση απροβλέπτων" value={totals.contingencyUsed}
            limit={contract.contingency_amount}
            note={`κονδύλιο ${contract.contingency_pct}% — άρθρο 156 §3β`} />
          <Limit label="Επί έλασσον (συνολικά)" value={totals.savings}
            limit={contract.initial_value_net * 0.1}
            note="όριο 10% — άρθρο 156 §3γ" />
        </div>
        <dl className="grid gap-x-6 gap-y-2 border-t border-rule px-4 py-3 text-sm sm:grid-cols-4">
          <Pair k="Δαπάνη εργασιών (αρχική)" v={eur(totals.worksInitial)} />
          <Pair k="Δαπάνη εργασιών (νέα)" v={eur(totals.worksNew)} />
          <Pair k="Μεταβολή" v={`${totals.delta >= 0 ? '+' : ''}${eur(totals.delta)}`} />
          <Pair k="Νέα συνολική δαπάνη" v={eur(totals.newTotal)} />
        </dl>
      </Card>

      {violations.length > 0 && (
        <Card>
          <CardHeader title="Έλεγχος άρθρου 156" legalRef="N4412/156"
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
          Ο πίνακας καταχωρίζεται ως <strong>σχέδιο</strong>. Τα κωλύματα του άρθρου 156
          δεν εμποδίζουν τη σύνταξη — εμποδίζουν την <em>έγκριση</em>, η οποία είναι
          πράξη της Διευθύνουσας Υπηρεσίας. <LegalRef id="N4412/156/7" />
        </p>
        <Button variant="secondary" onClick={() => nav(`/erga/${projectId}/ape`)}>Άκυρο</Button>
        <Button disabled={busy || problems.length > 0} onClick={save}>
          {busy ? 'Καταχώριση…' : 'Καταχώριση ΑΠΕ'}
        </Button>
      </div>
    </div>
  )
}

function Limit({ label, value, limit, note }: {
  label: string; value: number; limit: number; note: string
}) {
  const over = value > limit
  return (
    <div>
      <div className="flex items-baseline justify-between">
        <span className="label-xs">{label}</span>
        <span className={cx('tnum font-mono text-xs', over ? 'text-oxide' : 'text-ink2')}>
          {eur(value)} / {eur(limit)}
        </span>
      </div>
      <div className="mt-2"><Meter value={value} max={limit || 1} tone={over ? 'oxide' : 'accent'} /></div>
      <p className="mt-1.5 text-2xs text-ink3">{note}</p>
    </div>
  )
}

function Pair({ k, v }: { k: string; v: string }) {
  return (
    <div>
      <dt className="label-xs">{k}</dt>
      <dd className="tnum mt-0.5 font-mono text-[13px]">{v}</dd>
    </div>
  )
}

function NoBudget({ projectId }: { projectId: string }) {
  const nav = useNavigate()
  return (
    <Card className="mx-auto max-w-2xl">
      <CardHeader title="Δεν υπάρχει καταχωρισμένος προϋπολογισμός" legalRef="N4412/156/2" />
      <div className="space-y-3 px-4 py-4 text-sm text-ink2">
        <p>
          Ο Ανακεφαλαιωτικός Πίνακας συγκρίνει τις νέες ποσότητες με τις
          <strong> συμβατικές</strong>. Χωρίς καταχωρισμένα τα άρθρα του τιμολογίου
          δεν υπάρχει αφετηρία σύγκρισης — και ένας ΑΠΕ χωρίς αφετηρία δεν
          τεκμηριώνει τίποτε.
        </p>
        <p className="text-ink3">
          Καταχωρίστε πρώτα τον προϋπολογισμό μελέτης· ο 1ος ΑΠΕ θα προσυμπληρωθεί
          αυτόματα από αυτόν.
        </p>
        <div className="pt-1">
          <Button onClick={() => nav(`/erga/${projectId}/proypologismos`)}>
            Καταχώριση προϋπολογισμού
          </Button>
        </div>
      </div>
    </Card>
  )
}
