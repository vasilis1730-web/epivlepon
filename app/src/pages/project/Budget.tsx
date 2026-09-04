/**
 * Προϋπολογισμός μελέτης — τα ΣΥΜΒΑΤΙΚΑ μεγέθη του έργου.
 *
 * Αποτελεί την έκδοση 0 του προϋπολογισμού και τη βάση από την οποία
 * προσυμπληρώνεται ο 1ος Ανακεφαλαιωτικός Πίνακας Εργασιών: εκεί ο
 * μηχανικός δεν ξαναγράφει τα άρθρα, αλλά μεταβάλλει μόνο ποσότητες.
 * Χωρίς καταχωρισμένο προϋπολογισμό δεν μπορεί να συνταχθεί ΑΠΕ.
 */
import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import * as api from '@/lib/api'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import {
  Badge, Button, Card, CardHeader, Input, LegalRef, Select, Spinner, Table, Td, Th,
} from '@/components/ui'
import { WORK_GROUPS } from '@/lib/catalogue'
import { eur } from '@/lib/format'
import type { BudgetItemDraft } from '@/lib/types'

const emptyLine = (lineNo: number): BudgetItemDraft => ({
  line_no: lineNo, item_code: '', description: '', unit: '',
  work_group: '', unit_price: 0, quantity: 0,
})

export default function Budget() {
  const { projectId = '' } = useParams()
  const nav = useNavigate()
  const { push } = useToast()

  const { data, loading } = useQuery(async () => {
    const [project, contract, budget] = await Promise.all([
      api.getProject(projectId), api.getContract(projectId), api.getBudget(projectId),
    ])
    return { project, contract, budget }
  }, [projectId])

  const [lines, setLines] = useState<BudgetItemDraft[]>([])
  const [busy, setBusy] = useState(false)
  const [seeded, setSeeded] = useState(false)

  // Προσυμπλήρωση από ό,τι έχει ήδη καταχωρηθεί (επανεπεξεργασία).
  useEffect(() => {
    if (seeded || !data) return
    const existing = data.budget?.items ?? []
    setLines(
      existing.length
        ? existing.map(i => ({
            line_no: i.line_no, item_code: i.item_code, description: i.description,
            unit: i.unit, work_group: i.work_group, unit_price: i.unit_price,
            quantity: i.quantity,
          }))
        : [emptyLine(1)],
    )
    setSeeded(true)
  }, [data, seeded])

  const groups = useMemo(
    () => WORK_GROUPS.filter(g => g.category === data?.project?.category),
    [data?.project?.category],
  )

  const total = useMemo(
    () => Math.round(lines.reduce((s, l) => s + l.unit_price * l.quantity, 0) * 100) / 100,
    [lines],
  )

  if (loading || !data?.contract) return <Spinner />
  const { contract } = data

  const set = (i: number, patch: Partial<BudgetItemDraft>) =>
    setLines(ls => ls.map((l, idx) => (idx === i ? { ...l, ...patch } : l)))

  const addLine = () => setLines(ls => [...ls, emptyLine(ls.length + 1)])
  const removeLine = (i: number) =>
    setLines(ls => ls.filter((_, idx) => idx !== i).map((l, idx) => ({ ...l, line_no: idx + 1 })))

  const filled = lines.filter(l => l.item_code.trim() && l.quantity > 0 && l.unit_price > 0)
  const problems: string[] = []
  if (!filled.length) problems.push('Δεν έχει συμπληρωθεί καμία έγκυρη γραμμή.')
  if (lines.some(l => l.item_code.trim() && !l.work_group)) {
    problems.push(
      'Κάθε άρθρο πρέπει να ενταχθεί σε ομάδα εργασιών — χωρίς αυτήν δεν ελέγχεται ' +
      'το όριο 20% των επί έλασσον δαπανών ανά ομάδα (άρθρο 156 §3γ).',
    )
  }

  async function save() {
    setBusy(true)
    try {
      const r = await api.saveBudget(projectId, filled)
      push('success', 'Ο προϋπολογισμός καταχωρήθηκε',
        `${r.itemCount} άρθρα · σύνολο ${eur(r.totalNet)}`)
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
        <div className="label-xs">Άρθρο 53 §7 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Προϋπολογισμός μελέτης</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Καταχωρίστε τα άρθρα του τιμολογίου με τις συμβατικές ποσότητες. Αυτά τα
          μεγέθη είναι η αφετηρία κάθε Ανακεφαλαιωτικού Πίνακα: στον ΑΠΕ
          μεταβάλλονται μόνο οι ποσότητες, ποτέ οι τιμές μονάδος.
        </p>
      </header>

      <Card>
        <CardHeader
          title="Άρθρα τιμολογίου"
          subtitle={`Ομάδες εργασιών κατηγορίας «${data.project?.category ?? '—'}»`}
          legalRef="N4412/53/7"
          right={<Badge tone="muted">{filled.length} άρθρα</Badge>}
        />
        <Table minWidth={1080}>
          <thead>
            <tr>
              <Th className="w-10">Α/Α</Th>
              <Th>Κωδ. άρθρου</Th>
              <Th>Περιγραφή</Th>
              <Th>Ομάδα εργασιών</Th>
              <Th>Μον.</Th>
              <Th align="end">Τιμή μονάδος</Th>
              <Th align="end">Ποσότητα</Th>
              <Th align="end">Δαπάνη</Th>
              <Th align="end" />
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={i}>
                <Td className="tnum font-mono text-xs text-ink3">{l.line_no}</Td>
                <Td>
                  <Input value={l.item_code} placeholder="ΝΕΤ ΟΔΟ Α-2"
                    onChange={e => set(i, { item_code: e.target.value })} />
                </Td>
                <Td>
                  <Input value={l.description} placeholder="Περιγραφή εργασίας"
                    onChange={e => set(i, { description: e.target.value })} />
                </Td>
                <Td>
                  <Select value={l.work_group}
                    onChange={e => set(i, { work_group: e.target.value })}>
                    <option value="">— επιλογή —</option>
                    {groups.map(g => (
                      <option key={g.code} value={g.title}>{g.code} · {g.title}</option>
                    ))}
                  </Select>
                </Td>
                <Td>
                  <Input value={l.unit} placeholder="m³" className="w-20"
                    onChange={e => set(i, { unit: e.target.value })} />
                </Td>
                <Td align="end">
                  <Input type="number" step="0.0001" min="0" value={l.unit_price || ''}
                    className="w-28 text-right"
                    onChange={e => set(i, { unit_price: Number(e.target.value) || 0 })} />
                </Td>
                <Td align="end">
                  <Input type="number" step="0.0001" min="0" value={l.quantity || ''}
                    className="w-28 text-right"
                    onChange={e => set(i, { quantity: Number(e.target.value) || 0 })} />
                </Td>
                <Td align="end" className="tnum font-mono text-xs">
                  {eur(Math.round(l.unit_price * l.quantity * 100) / 100)}
                </Td>
                <Td align="end">
                  <Button variant="ghost" onClick={() => removeLine(i)}
                    aria-label={`Διαγραφή γραμμής ${l.line_no}`}>✕</Button>
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-rule px-4 py-3">
          <Button variant="secondary" onClick={addLine}>+ Προσθήκη άρθρου</Button>
          <div className="text-right">
            <div className="label-xs">Δαπάνη εργασιών</div>
            <div className="tnum font-serif text-xl font-semibold">{eur(total)}</div>
          </div>
        </div>
      </Card>

      <Card>
        <CardHeader title="Αντιπαραβολή με τη σύμβαση" legalRef="N4412/156/1" />
        <div className="space-y-2 px-4 py-4 text-sm">
          <div className="flex items-baseline justify-between">
            <span className="text-ink2">Αξία αρχικής σύμβασης (χωρίς ΦΠΑ)</span>
            <span className="tnum font-mono">{eur(contract.initial_value_net)}</span>
          </div>
          <div className="flex items-baseline justify-between">
            <span className="text-ink2">Κονδύλιο απροβλέπτων {contract.contingency_pct}%</span>
            <span className="tnum font-mono">{eur(contract.contingency_amount)}</span>
          </div>
          <p className="pt-1 text-xs text-ink3">
            Η δαπάνη εργασιών είναι μικρότερη της συμβατικής αξίας, καθώς η τελευταία
            περιλαμβάνει ΓΕ &amp; ΟΕ και απρόβλεπτα. Τα κονδύλια αυτά δεν
            ανακεφαλαιώνονται εκ νέου στον ΑΠΕ. <LegalRef id="N4412/156/3b" />
          </p>
        </div>
      </Card>

      {problems.length > 0 && (
        <Card>
          <div className="space-y-1.5 px-4 py-3 text-sm text-oxide">
            {problems.map(p => <p key={p}>• {p}</p>)}
          </div>
        </Card>
      )}

      <div className="flex flex-wrap justify-end gap-2">
        <Button variant="secondary" onClick={() => nav(`/erga/${projectId}`)}>Άκυρο</Button>
        <Button disabled={busy || problems.length > 0} onClick={save}>
          {busy ? 'Καταχώριση…' : 'Καταχώριση προϋπολογισμού'}
        </Button>
      </div>
    </div>
  )
}
