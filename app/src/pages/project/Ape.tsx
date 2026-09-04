import { useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import * as api from '@/lib/api'
import { RuleViolation } from '@/lib/store'
import {
  Badge, BlockerList, Button, Card, CardHeader, Meter, Spinner, Table, Td, Th,
} from '@/components/ui'
import { APE_STATUS, APE_TYPE } from '@/lib/labels'
import { cx, date, eur, pct, qty } from '@/lib/format'
import { apeViolations } from '@/lib/rules'

const FUNDING: Record<string, string> = {
  symvatiko: 'Συμβατικό', apravlepta: 'Απρόβλεπτα', epi_elasson: 'Επί έλασσον',
  symplirwmatiki: 'Συμπληρωματική', apologistika: 'Απολογιστικά',
}

export default function ApePage() {
  const { projectId = '' } = useParams()
  const nav = useNavigate()
  const toast = useToast()

  const { data, loading } = useQuery(async () => {
    const [apes, contract] = await Promise.all([api.getApes(projectId), api.getContract(projectId)])
    return { apes, contract }
  }, [projectId])

  if (loading || !data?.contract) return <Spinner />
  const { apes, contract } = data
  const approved = apes.filter(a => a.status === 'approved')
  const cumulativeDelta = approved.reduce((s, a) => s + a.delta_amount, 0)

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="label-xs">Άρθρο 156 ν. 4412/2016</div>
          <h1 className="mt-1 font-serif text-2xl font-bold">Ανακεφαλαιωτικοί Πίνακες Εργασιών</h1>
          <p className="mt-1 max-w-3xl text-sm text-ink2">
            Κάθε τροποποίηση ελέγχεται ως προς τα τέσσερα όρια: 50% σωρευτικά, 9%/15%
            απρόβλεπτα, 20% ανά ομάδα εργασιών και 10% συνολικά για τις επί έλασσον δαπάνες.
          </p>
        </div>
        <div className="flex shrink-0 gap-2">
          <Button variant="secondary" onClick={() => nav(`/erga/${projectId}/proypologismos`)}>
            Προϋπολογισμός
          </Button>
          <Button onClick={() => nav(`/erga/${projectId}/ape/neos`)}>Νέος ΑΠΕ</Button>
        </div>
      </header>

      <Card>
        <CardHeader title="Όρια τροποποιήσεων" legalRef="N4412/156/1" />
        <div className="grid gap-5 px-4 py-4 sm:grid-cols-3">
          <LimitBar
            label="Σωρευτική αύξηση"
            value={Math.max(0, cumulativeDelta)}
            limit={contract.initial_value_net * 0.5}
            note="όριο 50% της αρχικής σύμβασης — άρθρο 156 §1"
          />
          <LimitBar
            label="Χρήση απροβλέπτων"
            value={approved.reduce((s, a) => s + a.contingency_used, 0)}
            limit={contract.contingency_amount}
            note={`κονδύλιο ${contract.contingency_pct}% — άρθρο 156 §3β`}
          />
          <LimitBar
            label="Επί έλασσον (συνολικά)"
            value={apes.reduce(
              (s, a) => s + a.lines.reduce((t, l) => t + (l.delta_amount < 0 ? -l.delta_amount : 0), 0), 0)}
            limit={contract.initial_value_net * 0.1}
            note="όριο 10% της αρχικής σύμβασης — άρθρο 156 §3γ"
          />
        </div>
      </Card>

      {apes.length === 0 && (
        <Card><p className="px-4 py-8 text-center text-sm text-ink3">Δεν έχουν συνταχθεί ΑΠΕ.</p></Card>
      )}

      {apes.map(a => {
        const others = approved.filter(x => x.id !== a.id)
        const violations = apeViolations(a, contract, others)
        const hard = violations.filter(v => v.severity === 'hard')
        const savings = a.lines.reduce((s, l) => s + (l.delta_amount < 0 ? -l.delta_amount : 0), 0)

        return (
          <Card key={a.id}>
            <CardHeader
              title={`${a.serial_no}ος Ανακεφαλαιωτικός Πίνακας Εργασιών`}
              subtitle={a.reason}
              legalRef="N4412/156/2"
              right={
                <>
                  <Badge tone={a.status === 'approved' ? 'accent' : hard.length ? 'oxide' : 'brass'}>
                    {APE_STATUS[a.status]}
                  </Badge>
                  <Badge tone="muted">{APE_TYPE[a.atype]}</Badge>
                </>
              }
            />

            <dl className="grid gap-x-6 gap-y-2 border-b border-rule px-4 py-3 text-sm sm:grid-cols-4">
              <Pair k="Αρχική σύμβαση" v={eur(a.initial_contract_value)} />
              <Pair k="Νέα συνολική δαπάνη" v={eur(a.new_total_value)} />
              <Pair k="Μεταβολή" v={`${eur(a.delta_amount)} (${pct((a.delta_amount / a.initial_contract_value) * 100)})`} />
              <Pair k="Επί έλασσον" v={eur(savings)} />
              <Pair k="Χρήση απροβλέπτων" v={eur(a.contingency_used)} />
              <Pair k="Ημ/νία σύνταξης" v={date(a.drafted_at)} />
              <Pair k="Γνωμοδότηση Τ.Σ." v={a.tc_opinion_id ? 'Ναι' : '—'} />
              <Pair k="Υπογραφή αναδόχου" v={a.contractor_signature ? SIGN[a.contractor_signature] ?? a.contractor_signature : '—'} />
            </dl>

            <Table minWidth={980}>
              <thead>
                <tr>
                  <Th>Άρθρο</Th><Th>Περιγραφή</Th><Th>Ομάδα εργασιών</Th>
                  <Th align="end">Τιμή</Th><Th align="end">Ποσ. αρχική</Th><Th align="end">Ποσ. νέα</Th>
                  <Th align="end">Δαπάνη αρχική</Th><Th align="end">Δαπάνη νέα</Th>
                  <Th align="end">Μεταβολή</Th><Th>Πηγή</Th>
                </tr>
              </thead>
              <tbody>
                {a.lines.map(l => (
                  <tr key={l.id}>
                    <Td className="whitespace-nowrap font-mono text-xs">{l.item_code}</Td>
                    <Td className="text-sm">{l.description}</Td>
                    <Td className="text-xs text-ink2">{l.work_group}</Td>
                    <Td align="end" className="font-mono text-xs">{eur(l.unit_price)}</Td>
                    <Td align="end" className="font-mono text-xs">{qty(l.qty_initial)}</Td>
                    <Td align="end" className="font-mono text-xs">{qty(l.qty_new)}</Td>
                    <Td align="end">{eur(l.amount_initial)}</Td>
                    <Td align="end">{eur(l.amount_new)}</Td>
                    <Td align="end" className={cx('font-semibold', l.delta_amount < 0 ? 'text-oxide' : 'text-accent')}>
                      {l.delta_amount >= 0 ? '+' : ''}{eur(l.delta_amount)}
                    </Td>
                    <Td><Badge tone={l.funding_source === 'epi_elasson' ? 'oxide' : 'neutral'}>
                      {FUNDING[l.funding_source]}
                    </Badge></Td>
                  </tr>
                ))}
              </tbody>
            </Table>

            <div className="space-y-3 border-t border-rule px-4 py-4">
              <div className="label-xs">Έλεγχος ορίων άρθρου 156</div>
              <BlockerList blockers={violations} />

              {a.status !== 'approved' && (
                <div className="flex flex-wrap gap-2 pt-1">
                  {!a.tc_opinion_id && (
                    <Button onClick={async () => {
                      await api.attachTcOpinion(a.id)
                      toast.push('success', 'Καταχωρήθηκε γνωμοδότηση Τεχνικού Συμβουλίου')
                    }}>
                      Καταχώριση γνωμοδότησης Τ.Σ.
                    </Button>
                  )}
                  {!a.contractor_signature && (
                    <>
                      <Button onClick={async () => {
                        await api.signApe(a.id, 'anepifylakta')
                        toast.push('success', 'Υπογραφή αναδόχου ανεπιφύλακτα')
                      }}>Υπογραφή ανεπιφύλακτα</Button>
                      <Button onClick={async () => {
                        await api.signApe(a.id, 'me_epifylaxi')
                        toast.push('info', 'Υπογραφή με επιφύλαξη',
                          'Ο ανάδοχος διατηρεί τα δικαιώματά του (άρθρο 156 §7).')
                      }}>Υπογραφή με επιφύλαξη</Button>
                    </>
                  )}
                  <Button
                    variant={hard.length === 0 ? 'primary' : 'secondary'}
                    onClick={async () => {
                      try {
                        await api.approveApe(a.id)
                        toast.push('success', 'Ο ΑΠΕ εγκρίθηκε')
                      } catch (e) {
                        toast.push('error', 'Η έγκριση απορρίφθηκε',
                          e instanceof RuleViolation
                            ? e.blockers.map(b => '• ' + b.message).join('\n')
                            : e instanceof Error ? e.message : undefined)
                      }
                    }}
                  >
                    {hard.length === 0 ? 'Έγκριση ΑΠΕ' : 'Απόπειρα έγκρισης'}
                  </Button>
                </div>
              )}
            </div>
          </Card>
        )
      })}
    </div>
  )
}

const SIGN: Record<string, string> = {
  anepifylakta: 'Ανεπιφύλακτα', me_epifylaxi: 'Με επιφύλαξη', arnisi: 'Άρνηση υπογραφής',
}

function LimitBar({ label, value, limit, note }: {
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
