import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import * as api from '@/lib/api'
import {
  Badge, BlockerList, Button, Card, CardHeader, LegalRef, Spinner, Table, Td, Th,
} from '@/components/ui'
import { PAYMENT_STATUS } from '@/lib/labels'
import { cx, date, daysUntil, eur, relativeDays } from '@/lib/format'
import { paymentViolations } from '@/lib/rules'

export default function Payments() {
  const { projectId = '' } = useParams()
  const toast = useToast()

  const { data, loading } = useQuery(async () => {
    const [payments, measurements, contract] = await Promise.all([
      api.getPayments(projectId), api.getMeasurements(projectId), api.getContract(projectId),
    ])
    return { payments, measurements, contract }
  }, [projectId])

  if (loading || !data?.contract) return <Spinner />
  const { payments, measurements } = data

  const totalCertified = Math.max(0, ...payments.map(p => p.gross_cumulative))
  const totalPaid = payments.filter(p => p.paid_at).reduce((s, p) => s + p.net_payable, 0)
  const totalRetentions = payments.reduce((s, p) => s + p.retentions_amount, 0)

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρο 152 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Λογαριασμοί</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Η Διευθύνουσα Υπηρεσία ελέγχει, διορθώνει και εγκρίνει εντός ενός μηνός. Άπρακτη
          πάροδος της προθεσμίας καθιστά τον λογαριασμό εγκεκριμένο και πληρωτέο.
        </p>
      </header>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="p-4">
          <div className="label-xs">Πιστοποιημένα σωρευτικά</div>
          <div className="tnum mt-1 font-serif text-2xl font-semibold">{eur(totalCertified)}</div>
        </Card>
        <Card className="p-4">
          <div className="label-xs">Πληρωμένα (καθαρά)</div>
          <div className="tnum mt-1 font-serif text-2xl font-semibold">{eur(totalPaid)}</div>
        </Card>
        <Card className="p-4">
          <div className="label-xs">Κρατήσεις 5%</div>
          <div className="tnum mt-1 font-serif text-2xl font-semibold">{eur(totalRetentions)}</div>
          <div className="mt-1 text-xs text-ink3"><LegalRef id="N4412/152" /></div>
        </Card>
      </div>

      <Card>
        <CardHeader title="Πίνακας λογαριασμών" legalRef="N4412/152" />
        <Table minWidth={1100}>
          <thead>
            <tr>
              <Th className="w-10">Α/Α</Th><Th>Περίοδος</Th><Th>Επιμέτρηση</Th>
              <Th align="end">Σωρευτικά</Th><Th align="end">Περιόδου</Th>
              <Th align="end">Κρατήσεις</Th><Th align="end">Πληρωτέο</Th>
              <Th align="end">Προθεσμία</Th><Th>Κατάσταση</Th><Th align="end" />
            </tr>
          </thead>
          <tbody>
            {payments.map(p => {
              const m = measurements.find(x => x.id === p.measurement_id)
              const violations = paymentViolations(p, m, false)
              const dueDays = daysUntil(p.approval_due)
              const tacit = !p.approved_at && dueDays != null && dueDays < 0
              return (
                <tr key={p.id}>
                  <Td className="font-mono text-xs tnum">{p.serial_no}</Td>
                  <Td className="whitespace-nowrap font-mono text-xs">
                    {date(p.period_from)} – {date(p.period_to)}
                  </Td>
                  <Td className="font-mono text-xs">
                    {m ? `Α/Α ${m.serial_no}` : <span className="text-oxide">—</span>}
                  </Td>
                  <Td align="end">{eur(p.gross_cumulative)}</Td>
                  <Td align="end">{eur(p.period_amount)}</Td>
                  <Td align="end" className="text-ink3">−{eur(p.retentions_amount)}</Td>
                  <Td align="end" className="font-semibold">{eur(p.net_payable)}</Td>
                  <Td align="end" className="font-mono text-xs">
                    {date(p.approval_due)}
                    {!p.approved_at && (
                      <span className={cx('block text-2xs', tacit ? 'text-oxide' : 'text-brass')}>
                        {relativeDays(dueDays)}
                      </span>
                    )}
                  </Td>
                  <Td>
                    <Badge tone={
                      p.status === 'paid' ? 'accent'
                        : p.status === 'approved' ? 'accent'
                          : tacit ? 'oxide' : 'brass'
                    }>
                      {tacit ? 'σιωπηρά εγκεκριμένος' : PAYMENT_STATUS[p.status]}
                    </Badge>
                    {violations.filter(v => v.severity === 'hard').length > 0 && (
                      <Badge tone="oxide" className="ml-1">
                        {violations.filter(v => v.severity === 'hard').length}
                        {violations.filter(v => v.severity === 'hard').length === 1 ? ' εμπόδιο' : ' εμπόδια'}
                      </Badge>
                    )}
                  </Td>
                  <Td align="end">
                    {!p.approved_at && (
                      <Button
                        variant={violations.some(v => v.severity === 'hard') ? 'secondary' : 'primary'}
                        onClick={async () => {
                          const hard = violations.filter(v => v.severity === 'hard')
                          if (hard.length) {
                            toast.push('error', 'Ο λογαριασμός δεν μπορεί να εγκριθεί',
                              hard.map(h => '• ' + h.message).join('\n'))
                            return
                          }
                          await api.approvePayment(p.id)
                          toast.push('success', 'Ο λογαριασμός εγκρίθηκε')
                        }}
                      >
                        Έγκριση
                      </Button>
                    )}
                  </Td>
                </tr>
              )
            })}
          </tbody>
        </Table>
      </Card>

      {payments.filter(p => !p.approved_at).map(p => {
        const m = measurements.find(x => x.id === p.measurement_id)
        const v = paymentViolations(p, m, false)
        if (v.length === 0) return null
        return (
          <Card key={p.id}>
            <CardHeader title={`Έλεγχος ${p.serial_no}ου λογαριασμού`} legalRef="N4412/152" />
            <div className="px-4 py-4"><BlockerList blockers={v} /></div>
          </Card>
        )
      })}
    </div>
  )
}
