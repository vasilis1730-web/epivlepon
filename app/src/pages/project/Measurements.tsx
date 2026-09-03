import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import * as api from '@/lib/api'
import {
  Badge, Button, Card, CardHeader, LegalRef, Meter, Spinner, Table, Td, Th,
} from '@/components/ui'
import { MEASUREMENT_STATUS } from '@/lib/labels'
import { cx, date, eur, relativeDays, daysUntil } from '@/lib/format'
import { requiredAuditCount } from '@/lib/rules'

export default function Measurements() {
  const { projectId = '' } = useParams()
  const toast = useToast()

  const { data, loading } = useQuery(async () => {
    const [measurements, finalM] = await Promise.all([
      api.getMeasurements(projectId), api.getFinalMeasurement(projectId),
    ])
    return { measurements, finalM }
  }, [projectId])

  if (loading || !data) return <Spinner />
  const partial = data.measurements.filter(m => m.mtype === 'tmimatiki')
  const submitted = partial.filter(m => m.submitted_at).length
  const audited = partial.filter(m => m.audited).length
  const required = requiredAuditCount(submitted)
  const shortfall = Math.max(0, required - audited)

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρο 151 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Επιμετρήσεις</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Υποβάλλονται ανά τμηματική προθεσμία ή μηνιαίως, με δήλωση περί της αλήθειας των
          στοιχείων. Η επιμέτρηση αποτελεί προϋπόθεση για κάθε πληρωμή.
        </p>
      </header>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="p-4">
          <div className="label-xs">Υποβληθείσες</div>
          <div className="tnum mt-1 font-serif text-2xl font-semibold">{submitted}</div>
        </Card>
        <Card className={cx('p-4', shortfall > 0 && 'border-oxide')}>
          <div className="label-xs">Δειγματοληπτικός έλεγχος</div>
          <div className="tnum mt-1 font-serif text-2xl font-semibold">
            {audited}<span className="text-ink3">/{required}</span>
          </div>
          <div className="mt-2"><Meter value={audited} max={Math.max(required, 1)} tone={shortfall > 0 ? 'oxide' : 'accent'} /></div>
          <p className="mt-2 text-xs text-ink3">
            Υποχρεωτικός έλεγχος 40% των υποβληθεισών, ή τουλάχιστον 4 όταν είναι λιγότερες
            από 10. <LegalRef id="N4412/151/3" />
          </p>
        </Card>
        <Card className="p-4">
          <div className="label-xs">Πιστοποιηθείσα δαπάνη</div>
          <div className="tnum mt-1 font-serif text-2xl font-semibold">
            {eur(partial.reduce((s, m) => s + m.total_amount, 0))}
          </div>
        </Card>
      </div>

      {shortfall > 0 && (
        <div className="rounded border-l-2 border-l-oxide bg-oxide-soft/50 px-4 py-3 text-sm">
          Εκκρεμούν <strong>{shortfall}</strong> δειγματοληπτικοί έλεγχοι. Το στάδιο των
          επιμετρήσεων δεν κλείνει μέχρι να καλυφθεί ο υποχρεωτικός έλεγχος.{' '}
          <LegalRef id="N4412/151/3" />
        </div>
      )}

      <Card>
        <CardHeader title="Τμηματικές επιμετρήσεις" legalRef="N4412/151/2" />
        <Table minWidth={980}>
          <thead>
            <tr>
              <Th className="w-10">Α/Α</Th><Th>Περίοδος</Th><Th>Τμήμα έργου</Th>
              <Th align="end">Συμβατικές</Th><Th align="end">Εκτός σύμβασης</Th>
              <Th align="end">Σύνολο</Th><Th align="end">Προθεσμία έγκρισης</Th>
              <Th>Κατάσταση</Th><Th align="center">Έλεγχος</Th><Th align="end" />
            </tr>
          </thead>
          <tbody>
            {partial.map(m => {
              const overdue = !m.approved_at && m.approval_due && (daysUntil(m.approval_due) ?? 0) < 0
              return (
                <tr key={m.id}>
                  <Td className="font-mono text-xs tnum">{m.serial_no}</Td>
                  <Td className="whitespace-nowrap font-mono text-xs">
                    {date(m.period_from)} – {date(m.period_to)}
                  </Td>
                  <Td className="text-xs text-ink2">{m.work_section ?? '—'}</Td>
                  <Td align="end">{eur(m.contractual_amount)}</Td>
                  <Td align="end" className={m.extra_amount > 0 ? 'text-brass' : 'text-ink3'}>
                    {m.extra_amount > 0 ? eur(m.extra_amount) : '—'}
                  </Td>
                  <Td align="end" className="font-semibold">{eur(m.total_amount)}</Td>
                  <Td align="end" className="font-mono text-xs">
                    {m.approved_at ? date(m.approved_at) : date(m.approval_due)}
                    {overdue && <span className="block text-2xs text-oxide">{relativeDays(daysUntil(m.approval_due))}</span>}
                  </Td>
                  <Td>
                    <Badge tone={['approved', 'deemed_approved'].includes(m.status) ? 'accent' : 'brass'}>
                      {MEASUREMENT_STATUS[m.status]}
                    </Badge>
                  </Td>
                  <Td align="center">
                    {m.audited
                      ? <Badge tone="accent">ελέγχθηκε</Badge>
                      : <Badge tone="muted">—</Badge>}
                  </Td>
                  <Td align="end">
                    <div className="flex justify-end gap-1">
                      {!m.audited && (
                        <Button onClick={async () => {
                          await api.auditMeasurement(m.id)
                          toast.push('success', 'Καταχωρήθηκε δειγματοληπτικός έλεγχος',
                            `Επιμέτρηση Α/Α ${m.serial_no}`)
                        }}>Δειγματοληψία</Button>
                      )}
                      {m.status === 'submitted' && (
                        <Button variant="primary" onClick={async () => {
                          await api.approveMeasurement(m.id)
                          toast.push('success', 'Η επιμέτρηση εγκρίθηκε')
                        }}>Έγκριση</Button>
                      )}
                    </div>
                  </Td>
                </tr>
              )
            })}
          </tbody>
        </Table>
      </Card>

      <Card>
        <CardHeader
          title="Τελική επιμέτρηση"
          subtitle="Δύο μήνες για τον ανάδοχο, δύο για την έκθεση του επιβλέποντος, δύο για την έγκριση της Δ.Υ."
          legalRef="N4412/151/9"
        />
        {!data.finalM ? (
          <p className="px-4 py-6 text-sm text-ink3">
            Δεν έχει ανοίξει διαδικασία τελικής επιμέτρησης — προϋποθέτει Βεβαίωση Περάτωσης.
          </p>
        ) : (
          <div className="grid gap-4 px-4 py-4 sm:grid-cols-4">
            <Milestone label="Περαίωση" value={date(data.finalM.completion_date)} done />
            <Milestone label="Υποβολή αναδόχου" value={date(data.finalM.submitted_at)}
              due={data.finalM.contractor_due} done={Boolean(data.finalM.submitted_at)} />
            <Milestone label="Έκθεση επιβλέποντος" value={date(data.finalM.supervisor_report_at)}
              due={data.finalM.supervisor_report_due} done={Boolean(data.finalM.supervisor_report_at)} />
            <Milestone label="Έγκριση Δ.Υ." value={date(data.finalM.approved_at)}
              due={data.finalM.approval_due} done={Boolean(data.finalM.approved_at)} />
            {data.finalM.penalty_amount > 0 && (
              <div className="sm:col-span-4 rounded border border-oxide bg-oxide-soft/50 px-3 py-2 text-sm">
                Ποινική ρήτρα καθυστέρησης: <strong>{eur(data.finalM.penalty_amount)}</strong>{' '}
                ({data.finalM.penalty_months} μήνες × 2‰) <LegalRef id="N4412/151/10" />
              </div>
            )}
            {data.finalM.approved_at && (
              <p className="sm:col-span-4 text-sm text-accent">
                Η έγκριση της τελικής επιμέτρησης ενεργοποιεί τη μείωση της εγγύησης καλής
                εκτέλεσης κατά 70%. <LegalRef id="N4412/72/14b" />
              </p>
            )}
          </div>
        )}
      </Card>
    </div>
  )
}

function Milestone({ label, value, due, done }: {
  label: string; value: string; due?: string | null; done?: boolean
}) {
  return (
    <div className={cx('rounded border p-3', done ? 'border-accent bg-accent-soft/40' : 'border-rule')}>
      <div className="label-xs">{label}</div>
      <div className="tnum mt-1 font-mono text-sm">{value}</div>
      {due && <div className="mt-0.5 text-2xs text-ink3">προθεσμία {date(due)}</div>}
    </div>
  )
}
