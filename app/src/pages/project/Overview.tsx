import { Link, useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import * as api from '@/lib/api'
import { Badge, Card, CardHeader, LegalRef, Meter, Spinner, Table, Td, Th } from '@/components/ui'
import { CATEGORY, PHASE } from '@/lib/labels'
import { cx, date, eur, pct, relativeDays } from '@/lib/format'
import { STAGES_BY_CODE } from '@/lib/catalogue'

export default function Overview() {
  const { projectId = '' } = useParams()

  const { data, loading } = useQuery(async () => {
    const [project, contract, fin, stages, guarantees] = await Promise.all([
      api.getProject(projectId), api.getContract(projectId), api.getFinancials(projectId),
      api.getStages(projectId), api.getGuarantees(projectId),
    ])
    return { project, contract, fin, stages, guarantees }
  }, [projectId])

  if (loading || !data?.project || !data.contract) return <Spinner />
  const { project, contract, fin, stages } = data

  const byPhase = (Object.keys(PHASE) as (keyof typeof PHASE)[]).map(ph => {
    const list = stages.filter(s => STAGES_BY_CODE.get(s.stage_code)?.phase === ph)
    return {
      ph,
      total: list.length,
      done: list.filter(s => ['completed', 'overdue', 'not_applicable'].includes(s.status)).length,
      blocked: list.filter(s => s.hard_blockers > 0 && s.status !== 'completed').length,
    }
  }).filter(x => x.total > 0)

  const nextStages = stages
    .filter(s => ['available', 'in_progress', 'pending_approval'].includes(s.status))
    .slice(0, 6)

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="label-xs">{project.code} · {CATEGORY[project.category]}</div>
          <h1 className="mt-1 max-w-3xl font-serif text-2xl font-bold leading-tight">{project.title}</h1>
          <p className="mt-1 text-sm text-ink2">
            {project.location} · Χρηματοδότηση: {project.funding_source}
          </p>
        </div>
        <Badge tone={contract.status === 'active' ? 'accent' : 'neutral'}>
          {contract.status === 'active' ? 'σε εκτέλεση' : contract.status}
        </Badge>
      </header>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader title="Στοιχεία σύμβασης" legalRef="N4412/135" />
          <dl className="grid grid-cols-2 gap-x-6 gap-y-2 px-4 py-4 text-sm sm:grid-cols-3">
            <Item k="Ανάδοχος" v={contract.contractor_name} />
            <Item k="Α.Φ.Μ." v={contract.contractor_afm} mono />
            <Item k="Αρ. σύμβασης" v={contract.contract_no} mono />
            <Item k="Ημ/νία υπογραφής" v={date(contract.signed_at)} mono />
            <Item k="Μέση έκπτωση" v={pct(contract.discount_pct)} mono />
            <Item k="Αξία αρχικής σύμβασης" v={eur(contract.initial_value_net)} mono />
            <Item k="Απρόβλεπτα" v={`${eur(contract.contingency_amount)} (${contract.contingency_pct}%)`} mono />
            <Item k="Συνολική προθεσμία" v={`${contract.total_duration_days} ημέρες`} mono />
            <Item k="Λήξη προθεσμίας" v={date(contract.current_end_date)} mono />
            <Item k="Επίβλεψη" v={contract.supervision_mode === 'ife' ? 'Ιδιωτικός Φορέας' : 'Υπηρεσιακή'} />
            <Item k="Ημερολόγιο" v={contract.diary_mode === 'imerisio' ? 'Ημερήσιο' : 'Εβδομαδιαίο'} />
            <Item k="Χρόνος συντήρησης" v={`${contract.maintenance_months} μήνες`} mono />
          </dl>
        </Card>

        <Card>
          <CardHeader title="Οικονομική εικόνα" legalRef="N4412/156/1" />
          <div className="space-y-4 px-4 py-4">
            <div>
              <div className="mb-1 flex items-baseline justify-between text-xs">
                <span className="text-ink2">Πιστοποιημένα</span>
                <span className="tnum font-mono">{pct(fin?.financial_progress_pct ?? 0)}</span>
              </div>
              <Meter value={fin?.certified_total ?? 0} max={fin?.current_value_net ?? 1} />
              <div className="mt-1 tnum text-right font-mono text-2xs text-ink3">
                {eur(fin?.certified_total)} / {eur(fin?.current_value_net)}
              </div>
            </div>
            <div>
              <div className="mb-1 flex items-baseline justify-between text-xs">
                <span className="text-ink2">Μεταβολή από ΑΠΕ</span>
                <span className="tnum font-mono">{pct(fin?.ape_delta_pct ?? 0)}</span>
              </div>
              <Meter
                value={Math.abs(fin?.ape_delta ?? 0)}
                max={fin?.limit_50pct ?? 1}
                tone={(fin?.ape_delta_pct ?? 0) > 40 ? 'oxide' : 'brass'}
              />
              <div className="mt-1 text-2xs text-ink3">
                Όριο 50%: {eur(fin?.limit_50pct)} — άρθρο 156 §1
              </div>
            </div>
            <dl className="space-y-1 border-t border-rule pt-3 text-xs">
              <Row k="Πληρωμένα" v={eur(fin?.paid_total)} />
              <Row k="Ενεργές εγγυήσεις" v={eur(fin?.guarantees_active)} />
              <Row k="Ποινικές ρήτρες" v={eur(fin?.penalties_total)} />
              <Row k="Απομένουν" v={relativeDays(fin?.days_to_deadline ?? null)} />
            </dl>
          </div>
        </Card>
      </div>

      <Card>
        <CardHeader
          title="Πρόοδος οδηγού"
          subtitle="Κάθε φάση ολοκληρώνεται μόνο όταν κλείσουν όλα τα στάδιά της."
          right={<Link to={`/erga/${projectId}/odigos`} className="text-sm text-accent hover:underline">Άνοιγμα οδηγού →</Link>}
        />
        <div className="grid gap-px bg-rule sm:grid-cols-2 lg:grid-cols-5">
          {byPhase.map(x => (
            <div key={x.ph} className="bg-surface px-4 py-3">
              <div className="flex items-baseline gap-2">
                <span className="font-mono text-2xs text-accent">{PHASE[x.ph].key}</span>
                <span className="text-xs font-semibold leading-tight">{PHASE[x.ph].name}</span>
              </div>
              <div className="tnum mt-2 font-serif text-xl font-semibold">
                {x.done}<span className="text-ink3">/{x.total}</span>
              </div>
              <div className="mt-1.5"><Meter value={x.done} max={x.total} /></div>
              {x.blocked > 0 && (
                <div className="mt-2 font-mono text-2xs text-oxide">{x.blocked} με εμπόδια</div>
              )}
            </div>
          ))}
        </div>
      </Card>

      <Card>
        <CardHeader title="Ενεργά στάδια" subtitle="Τι είναι ανοιχτό αυτή τη στιγμή και ποιος έχει την πρωτοβουλία." />
        {nextStages.length === 0 ? (
          <p className="px-4 py-6 text-sm text-ink3">Δεν υπάρχουν ενεργά στάδια.</p>
        ) : (
          <Table minWidth={700}>
            <thead>
              <tr>
                <Th className="w-10">#</Th><Th>Στάδιο</Th><Th>Υπόχρεος</Th>
                <Th align="end">Ενέργειες</Th><Th align="end">Εμπόδια</Th><Th>Διάταξη</Th>
              </tr>
            </thead>
            <tbody>
              {nextStages.map(s => {
                const def = STAGES_BY_CODE.get(s.stage_code)
                return (
                  <tr key={s.id}>
                    <Td className="font-mono text-xs text-ink3">
                      {String(def?.ordinal ?? 0).padStart(2, '0')}
                    </Td>
                    <Td>
                      <Link to={`/erga/${projectId}/odigos`} className="font-medium hover:text-accent">
                        {def?.title}
                      </Link>
                    </Td>
                    <Td className="text-xs text-ink2">{def && PARTY[def.responsible]}</Td>
                    <Td align="end" className="font-mono text-xs">{s.tasks_done}/{s.tasks_total}</Td>
                    <Td align="end">
                      <span className={cx('font-mono text-xs', s.hard_blockers > 0 ? 'text-oxide' : 'text-accent')}>
                        {s.hard_blockers}
                      </span>
                    </Td>
                    <Td><LegalRef id={def?.legal_ref_id} /></Td>
                  </tr>
                )
              })}
            </tbody>
          </Table>
        )}
      </Card>
    </div>
  )
}

const PARTY: Record<string, string> = {
  anadochos: 'Ανάδοχος', epivlepon: 'Επιβλέπων',
  dieuthynousa_ypiresia: 'Διευθύνουσα Υπηρεσία', proistameni_arxi: 'Προϊσταμένη Αρχή',
  techniko_symvoulio: 'Τεχνικό Συμβούλιο', epitropi: 'Επιτροπή', ife: 'Ι.Φ.Ε.',
  kyrios_ergou: 'Κύριος του Έργου',
}

function Item({ k, v, mono }: { k: string; v: string; mono?: boolean }) {
  return (
    <div>
      <dt className="label-xs">{k}</dt>
      <dd className={cx('mt-0.5', mono && 'font-mono text-[13px] tnum')}>{v}</dd>
    </div>
  )
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex justify-between">
      <dt className="text-ink3">{k}</dt>
      <dd className="tnum font-mono text-ink2">{v}</dd>
    </div>
  )
}
