import { Link } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import * as api from '@/lib/api'
import { Badge, Card, LegalRef, Meter, Spinner, Table, Td, Th } from '@/components/ui'
import { CATEGORY } from '@/lib/labels'
import { cx, date, daysUntil, eur, pct, relativeDays } from '@/lib/format'
import { STAGES_BY_CODE } from '@/lib/catalogue'
import type { Blocker, ProjectFinancials, ProjectStage } from '@/lib/types'

interface Row {
  id: string
  code: string
  title: string
  category: string
  contractor: string
  fin: ProjectFinancials | undefined
  stages: ProjectStage[]
  blockers: { stage: ProjectStage; items: Blocker[] }[]
}

export default function Dashboard() {
  const { data: me } = useQuery(() => api.getProfile().catch(() => null), [])
  const { data, loading } = useQuery(async (): Promise<Row[]> => {
    const projects = await api.getProjects()
    return Promise.all(
      projects.map(async p => {
        const [contract, fin, stages] = await Promise.all([
          api.getContract(p.id), api.getFinancials(p.id), api.getStages(p.id),
        ])
        const active = stages.filter(s => ['in_progress', 'available', 'pending_approval'].includes(s.status))
        const blockers = await Promise.all(
          active.map(async s => ({ stage: s, items: await api.getStageBlockers(s.id) })),
        )
        return {
          id: p.id, code: p.code, title: p.title, category: CATEGORY[p.category] ?? p.category,
          contractor: contract?.contractor_name ?? '—',
          fin, stages,
          blockers: blockers.filter(b => b.items.some(i => i.severity === 'hard')),
        }
      }),
    )
  }, [])

  if (loading || !data) return <Spinner />

  const totalHard = data.reduce(
    (s, r) => s + r.blockers.reduce((n, b) => n + b.items.filter(i => i.severity === 'hard').length, 0), 0,
  )
  const totalValue = data.reduce((s, r) => s + (r.fin?.current_value_net ?? 0), 0)
  const totalCertified = data.reduce((s, r) => s + (r.fin?.certified_total ?? 0), 0)
  const urgent = data.filter(r => (r.fin?.days_to_deadline ?? 999) < 60).length

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="label-xs">Χαρτοφυλάκιο επίβλεψης</div>
          <h1 className="mt-1 font-serif text-3xl font-bold tracking-tight">Έργα σε εξέλιξη</h1>
        </div>
        {api.canCreateProject(me) && (
          <Link
            to="/neo-ergo"
            className="inline-flex items-center gap-2 rounded border border-accent bg-accent px-3 py-1.5 text-sm font-medium text-paper transition-[filter] hover:brightness-110"
          >
            <span aria-hidden="true">+</span> Νέο έργο
          </Link>
        )}
      </header>

      <div className="grid gap-px overflow-hidden rounded border border-rule bg-rule sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Ενεργά έργα" value={String(data.length)} />
        <Stat label="Συμβατική αξία" value={eur(totalValue)} />
        <Stat label="Πιστοποιημένα" value={eur(totalCertified)}
          note={totalValue ? pct((totalCertified / totalValue) * 100) + ' του συνόλου' : undefined} />
        <Stat
          label="Εμπόδια ελέγχου"
          value={String(totalHard)}
          tone={totalHard > 0 ? 'oxide' : 'accent'}
          note={urgent > 0 ? `${urgent} έργα με προθεσμία < 60 ημ.` : 'καμία κρίσιμη προθεσμία'}
        />
      </div>

      {data.length === 0 && <NoProjects canCreate={api.canCreateProject(me)} />}

      <div className="space-y-4">
        {data.map(r => (
          <Card key={r.id}>
            <div className="flex flex-wrap items-start justify-between gap-4 border-b border-rule px-4 py-3">
              <div className="min-w-0">
                <div className="font-mono text-2xs text-ink3">{r.code} · {r.category}</div>
                <h2 className="mt-0.5 font-serif text-lg font-semibold leading-tight">
                  <Link to={`/erga/${r.id}`} className="hover:text-accent">{r.title}</Link>
                </h2>
                <p className="mt-1 text-xs text-ink2">Ανάδοχος: {r.contractor}</p>
              </div>
              <div className="text-right">
                <div className="label-xs">Λήξη προθεσμίας</div>
                <div className="tnum font-serif text-lg font-semibold">
                  {date(r.fin?.current_end_date)}
                </div>
                <div
                  className={cx(
                    'font-mono text-2xs',
                    (r.fin?.days_to_deadline ?? 0) < 0 ? 'text-oxide'
                      : (r.fin?.days_to_deadline ?? 0) < 60 ? 'text-brass' : 'text-ink3',
                  )}
                >
                  {relativeDays(r.fin?.days_to_deadline ?? null)}
                </div>
              </div>
            </div>

            <div className="grid gap-5 px-4 py-4 lg:grid-cols-[1fr_1.1fr]">
              <div className="space-y-3">
                <div>
                  <div className="mb-1 flex items-baseline justify-between text-xs">
                    <span className="text-ink2">Οικονομική πρόοδος</span>
                    <span className="tnum font-mono text-ink3">
                      {eur(r.fin?.certified_total)} / {eur(r.fin?.current_value_net)}
                    </span>
                  </div>
                  <Meter value={r.fin?.certified_total ?? 0} max={r.fin?.current_value_net ?? 1} />
                </div>
                <div>
                  <div className="mb-1 flex items-baseline justify-between text-xs">
                    <span className="text-ink2">Στάδια οδηγού</span>
                    <span className="tnum font-mono text-ink3">
                      {r.stages.filter(s => s.status === 'completed' || s.status === 'overdue').length}
                      {' / '}{r.stages.length}
                    </span>
                  </div>
                  <Meter
                    value={r.stages.filter(s => ['completed', 'overdue'].includes(s.status)).length}
                    max={r.stages.length}
                    tone="brass"
                  />
                </div>
                <dl className="grid grid-cols-2 gap-x-4 gap-y-1 pt-1 text-xs">
                  <Pair k="Αξία αρχικής σύμβασης" v={eur(r.fin?.initial_value_net)} />
                  <Pair k="Μεταβολή από ΑΠΕ" v={`${eur(r.fin?.ape_delta)} (${pct(r.fin?.ape_delta_pct ?? 0)})`} />
                  <Pair k="Απρόβλεπτα" v={`${eur(r.fin?.contingency_amount)} · ${r.fin?.contingency_pct}%`} />
                  <Pair k="Ενεργές εγγυήσεις" v={eur(r.fin?.guarantees_active)} />
                </dl>
              </div>

              <div>
                <div className="label-xs mb-2">Τι μπλοκάρει τώρα</div>
                {r.blockers.length === 0 ? (
                  <p className="text-sm text-accent">Κανένα εμπόδιο στα ενεργά στάδια.</p>
                ) : (
                  <ul className="space-y-2">
                    {r.blockers.slice(0, 4).map(b => (
                      <li key={b.stage.id} className="rounded border border-rule bg-paper px-3 py-2">
                        <div className="flex items-baseline justify-between gap-2">
                          <Link
                            to={`/erga/${r.id}/odigos`}
                            className="text-sm font-medium hover:text-accent"
                          >
                            {STAGES_BY_CODE.get(b.stage.stage_code)?.title ?? b.stage.stage_code}
                          </Link>
                          <Badge tone="oxide">
                            {b.items.filter(i => i.severity === 'hard').length}
                            {b.items.filter(i => i.severity === 'hard').length === 1 ? ' εμπόδιο' : ' εμπόδια'}
                          </Badge>
                        </div>
                        <p className="mt-1 text-xs text-ink2">
                          {b.items.find(i => i.severity === 'hard')?.message}
                        </p>
                        <LegalRef id={b.items.find(i => i.severity === 'hard')?.legal_ref} />
                      </li>
                    ))}
                    {r.blockers.length > 4 && (
                      <li className="text-xs text-ink3">
                        …και {r.blockers.length - 4} ακόμη στάδια με εκκρεμότητες.
                      </li>
                    )}
                  </ul>
                )}
              </div>
            </div>
          </Card>
        ))}
      </div>

      <UpcomingDeadlines rows={data} />
    </div>
  )
}

/** Πρώτη οθόνη σε κενή εγκατάσταση: από πού ξεκινά η επίβλεψη. */
function NoProjects({ canCreate }: { canCreate: boolean }) {
  return (
    <Card>
      <div className="px-5 py-8">
        <h2 className="font-serif text-xl font-semibold">Δεν υπάρχει ακόμη κανένα έργο</h2>
        <p className="mt-2 max-w-2xl text-sm text-ink2">
          Η επίβλεψη ξεκινά από τη σύμβαση. Καταχωρίστε την όπως υπογράφηκε — αριθμό,
          ημερομηνία, έκπτωση, προθεσμία, ανάδοχο και τον ορισμό του επιβλέποντος — και
          το σύστημα στήνει από μόνο του τα στάδια του οδηγού με τις προθεσμίες τους,
          από την ανάληψη καθηκόντων μέχρι τη Βεβαίωση Περάτωσης.
        </p>
        {canCreate ? (
          <Link
            to="/neo-ergo"
            className="mt-5 inline-flex items-center gap-2 rounded border border-accent bg-accent px-4 py-2 text-sm font-medium text-paper hover:brightness-110"
          >
            Καταχώριση πρώτου έργου
          </Link>
        ) : (
          <p className="mt-4 text-sm text-ink3">
            Τα έργα τα ανοίγει η Διευθύνουσα Υπηρεσία, η οποία ορίζει και τον επιβλέποντα
            (άρθρο 136 §2 ν. 4412/2016). Μόλις οριστείτε, το έργο θα εμφανιστεί εδώ.
          </p>
        )}
      </div>
    </Card>
  )
}

function Stat({ label, value, note, tone = 'ink' }: {
  label: string; value: string; note?: string; tone?: 'ink' | 'accent' | 'oxide'
}) {
  return (
    <div className="bg-surface px-4 py-3">
      <div className="label-xs">{label}</div>
      <div
        className={cx(
          'tnum mt-1 font-serif text-2xl font-semibold',
          tone === 'accent' && 'text-accent', tone === 'oxide' && 'text-oxide',
        )}
      >
        {value}
      </div>
      {note && <div className="mt-0.5 text-xs text-ink3">{note}</div>}
    </div>
  )
}

function Pair({ k, v }: { k: string; v: string }) {
  return (
    <>
      <dt className="text-ink3">{k}</dt>
      <dd className="tnum text-right font-mono text-ink2">{v}</dd>
    </>
  )
}

function UpcomingDeadlines({ rows }: { rows: Row[] }) {
  const items = rows
    .flatMap(r =>
      r.stages
        .filter(s => s.due_date && !['completed', 'not_applicable'].includes(s.status))
        .map(s => ({
          projectId: r.id, projectCode: r.code, stage: s,
          def: STAGES_BY_CODE.get(s.stage_code),
          days: daysUntil(s.due_date),
        })),
    )
    .filter(x => x.days != null && x.days < 45)
    .sort((a, b) => (a.days ?? 0) - (b.days ?? 0))
    .slice(0, 10)

  if (items.length === 0) return null

  return (
    <Card>
      <div className="border-b border-rule px-4 py-3">
        <h2 className="font-serif text-base font-semibold">Ραντάρ προθεσμιών</h2>
        <p className="mt-0.5 text-xs text-ink2">
          Στάδια με προθεσμία που λήγει εντός 45 ημερών ή έχει ήδη παρέλθει.
        </p>
      </div>
      <Table minWidth={720}>
        <thead>
          <tr>
            <Th>Έργο</Th><Th>Στάδιο</Th><Th>Υπόχρεος</Th>
            <Th align="end">Προθεσμία</Th><Th align="end">Κατάσταση</Th><Th>Διάταξη</Th>
          </tr>
        </thead>
        <tbody>
          {items.map(x => (
            <tr key={x.stage.id}>
              <Td><span className="font-mono text-xs">{x.projectCode}</span></Td>
              <Td>
                <Link to={`/erga/${x.projectId}/odigos`} className="hover:text-accent">
                  {x.def?.title}
                </Link>
              </Td>
              <Td className="text-xs text-ink2">{x.def && PARTY_LABEL[x.def.responsible]}</Td>
              <Td align="end" className="font-mono text-xs">{date(x.stage.due_date)}</Td>
              <Td align="end">
                <Badge tone={(x.days ?? 0) < 0 ? 'oxide' : (x.days ?? 0) <= 5 ? 'brass' : 'neutral'}>
                  {relativeDays(x.days ?? null)}
                </Badge>
              </Td>
              <Td><LegalRef id={x.def?.legal_ref_id} /></Td>
            </tr>
          ))}
        </tbody>
      </Table>
    </Card>
  )
}

const PARTY_LABEL: Record<string, string> = {
  anadochos: 'Ανάδοχος', epivlepon: 'Επιβλέπων',
  dieuthynousa_ypiresia: 'Διευθύνουσα Υπηρεσία', proistameni_arxi: 'Προϊσταμένη Αρχή',
  techniko_symvoulio: 'Τεχνικό Συμβούλιο', epitropi: 'Επιτροπή',
  ife: 'Ι.Φ.Ε.', kyrios_ergou: 'Κύριος του Έργου',
}
