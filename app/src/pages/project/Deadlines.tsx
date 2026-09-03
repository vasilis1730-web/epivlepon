import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import * as api from '@/lib/api'
import { Badge, Card, CardHeader, LegalRef, Spinner, Table, Td, Th } from '@/components/ui'
import { STAGES_BY_CODE } from '@/lib/catalogue'
import { PARTY, STAGE_STATUS } from '@/lib/labels'
import { alertLevel, cx, date, daysUntil, relativeDays } from '@/lib/format'

const LEVEL_TONE = {
  overdue: 'oxide', critical: 'oxide', warning: 'brass', ok: 'neutral', none: 'muted',
} as const

const LEVEL_LABEL = {
  overdue: 'Εκπρόθεσμο', critical: 'Κρίσιμο', warning: 'Προσοχή', ok: 'Εντός', none: '—',
} as const

export default function Deadlines() {
  const { projectId = '' } = useParams()

  const { data, loading } = useQuery(async () => {
    const [stages, contract] = await Promise.all([api.getStages(projectId), api.getContract(projectId)])
    return { stages, contract }
  }, [projectId])

  if (loading || !data?.contract) return <Spinner />

  const rows = data.stages
    .filter(s => s.due_date && !['completed', 'not_applicable'].includes(s.status))
    .map(s => ({ s, def: STAGES_BY_CODE.get(s.stage_code)!, days: daysUntil(s.due_date) }))
    .sort((a, b) => (a.days ?? 0) - (b.days ?? 0))

  const tacit = data.stages
    .map(s => ({ s, def: STAGES_BY_CODE.get(s.stage_code)! }))
    .filter(x => x.def?.tacit_approval && !['completed', 'not_applicable'].includes(x.s.status))

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρα 147, 148 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Προθεσμίες</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Όλες οι προθεσμίες αρχίζουν από την υπογραφή της σύμβασης, εκτός αν τα συμβατικά
          τεύχη ορίζουν διαφορετικά.
        </p>
      </header>

      <div className="grid gap-4 sm:grid-cols-3">
        <Card className="p-4">
          <div className="label-xs">Υπογραφή σύμβασης</div>
          <div className="tnum mt-1 font-serif text-xl font-semibold">{date(data.contract.signed_at)}</div>
        </Card>
        <Card className="p-4">
          <div className="label-xs">Λήξη συνολικής προθεσμίας</div>
          <div className="tnum mt-1 font-serif text-xl font-semibold">{date(data.contract.current_end_date)}</div>
          <div className="mt-0.5 text-xs text-ink3">
            {relativeDays(daysUntil(data.contract.current_end_date))}
          </div>
        </Card>
        <Card className="p-4">
          <div className="label-xs">Οριακή προθεσμία</div>
          <div className="tnum mt-1 font-serif text-xl font-semibold">
            {date(addDaysIso(data.contract.current_end_date,
              Math.max(90, Math.round(data.contract.total_duration_days / 2))))}
          </div>
          <div className="mt-0.5 text-xs text-ink3">
            το ήμισυ της αρχικής, τουλάχιστον 3 μήνες · <LegalRef id="N4412/147/4" />
          </div>
        </Card>
      </div>

      <Card>
        <CardHeader
          title="Ραντάρ προθεσμιών σταδίων"
          subtitle="Ταξινόμηση κατά επείγον. Κρίσιμο = εντός 5 ημερών."
        />
        {rows.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-ink3">Δεν εκκρεμούν προθεσμίες σταδίων.</p>
        ) : (
          <Table minWidth={860}>
            <thead>
              <tr>
                <Th className="w-10">#</Th><Th>Στάδιο</Th><Th>Υπόχρεος</Th>
                <Th align="end">Προθεσμία</Th><Th align="end">Υπόλοιπο</Th>
                <Th>Κατάσταση</Th><Th>Διάταξη</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map(({ s, def, days }) => {
                const level = alertLevel(days)
                return (
                  <tr key={s.id}>
                    <Td className="font-mono text-xs text-ink3 tnum">
                      {String(def.ordinal).padStart(2, '0')}
                    </Td>
                    <Td className="font-medium">{def.title}</Td>
                    <Td className="text-xs text-ink2">{PARTY[def.responsible]}</Td>
                    <Td align="end" className="font-mono text-xs">{date(s.due_date)}</Td>
                    <Td align="end">
                      <span className={cx('font-mono text-xs', level === 'overdue' && 'text-oxide')}>
                        {relativeDays(days)}
                      </span>
                    </Td>
                    <Td>
                      <Badge tone={LEVEL_TONE[level]}>{LEVEL_LABEL[level]}</Badge>
                      <span className="ml-1 text-2xs text-ink3">{STAGE_STATUS[s.status]}</span>
                    </Td>
                    <Td><LegalRef id={def.legal_ref_id} /></Td>
                  </tr>
                )
              })}
            </tbody>
          </Table>
        )}
      </Card>

      {tacit.length > 0 && (
        <Card>
          <CardHeader
            title="Προθεσμίες με σιωπηρή έγκριση"
            subtitle="Η άπρακτη πάροδος παράγει έννομο αποτέλεσμα χωρίς πράξη της Υπηρεσίας — πρέπει να καταχωρηθεί."
          />
          <ul className="divide-y divide-rule">
            {tacit.map(({ s, def }) => (
              <li key={s.id} className="px-4 py-3">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">{def.title}</span>
                  <LegalRef id={def.legal_ref_id} />
                  {s.due_date && (
                    <Badge tone={(daysUntil(s.due_date) ?? 0) < 0 ? 'oxide' : 'brass'}>
                      {date(s.due_date)} · {relativeDays(daysUntil(s.due_date))}
                    </Badge>
                  )}
                </div>
                <p className="mt-1 text-sm text-ink2">{def.tacit_effect}</p>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  )
}

function addDaysIso(iso: string, days: number) {
  const d = new Date(iso + 'T00:00:00')
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}
