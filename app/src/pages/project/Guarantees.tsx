import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import * as api from '@/lib/api'
import { RuleViolation } from '@/lib/store'
import {
  Badge, BlockerList, Button, Card, CardHeader, LegalRef, Meter, Spinner,
  Table, Td, Th,
} from '@/components/ui'
import { GUARANTEE_STATUS, GUARANTEE_TYPE } from '@/lib/labels'
import { date, eur } from '@/lib/format'
import { guaranteeReduction70Blockers, guaranteeReleaseBlockers } from '@/lib/rules'

const EVENT: Record<string, string> = {
  meiosi_70: 'Μείωση 70%', apodesmevsi: 'Επιστροφή', merikia_apodesmevsi: 'Μερική αποδέσμευση',
  katapt: 'Κατάπτωση', ananeosi: 'Ανανέωση', avxisi: 'Αύξηση',
}

export default function Guarantees() {
  const { projectId = '' } = useParams()
  const toast = useToast()

  const { data, loading } = useQuery(async () => {
    const [guarantees, finalM, payments] = await Promise.all([
      api.getGuarantees(projectId), api.getFinalMeasurement(projectId), api.getPayments(projectId),
    ])
    return { guarantees, finalM, payments }
  }, [projectId])

  if (loading || !data) return <Spinner />
  const { guarantees, finalM, payments } = data

  const finalPaymentApproved = payments.some(
    p => p.ptype === 'telikos' && ['approved', 'deemed_approved', 'paid'].includes(p.status),
  )
  const reductionBlockers = guaranteeReduction70Blockers(finalM)
  const releaseBlockers = guaranteeReleaseBlockers({
    acceptanceApproved: false, finalPaymentApproved,
  })

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρο 72 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Εγγυήσεις</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Η εγγύηση καλής εκτέλεσης μειώνεται κατά 70% <strong>αμέσως μετά την έγκριση της
          τελικής επιμέτρησης</strong> και επιστρέφεται στο σύνολό της μετά την έγκριση του
          πρωτοκόλλου παραλαβής και του τελικού λογαριασμού.
        </p>
      </header>

      {guarantees.length === 0 ? (
        <Card><p className="px-4 py-8 text-center text-sm text-ink3">Δεν έχουν καταχωρηθεί εγγυητικές επιστολές.</p></Card>
      ) : (
        guarantees.map(g => {
          const canReduce = reductionBlockers.length === 0 && g.status === 'energi'
          const canRelease = releaseBlockers.length === 0 && g.status !== 'apodesmevmeni'
          return (
            <Card key={g.id}>
              <CardHeader
                title={`${GUARANTEE_TYPE[g.gtype]} — ${g.guarantee_no}`}
                subtitle={`Εκδότης: ${g.issuer} · Έκδοση ${date(g.issued_at)}`}
                legalRef="N4412/72/4"
                right={<Badge tone={g.status === 'energi' ? 'accent' : g.status === 'meiomeni_70' ? 'brass' : 'muted'}>
                  {GUARANTEE_STATUS[g.status]}
                </Badge>}
              />

              <div className="grid gap-5 px-4 py-4 lg:grid-cols-[1fr_1.2fr]">
                <div>
                  <div className="flex items-baseline justify-between text-sm">
                    <span className="text-ink2">Τρέχον ποσό</span>
                    <span className="tnum font-serif text-xl font-semibold">{eur(g.current_amount)}</span>
                  </div>
                  <div className="mt-2"><Meter value={g.current_amount} max={g.original_amount} /></div>
                  <div className="mt-1 flex justify-between text-2xs text-ink3">
                    <span>αρχικό {eur(g.original_amount)}</span>
                    <span>{g.pct_of_contract}% της αξίας</span>
                  </div>

                  {g.events.length > 0 && (
                    <div className="mt-4">
                      <div className="label-xs mb-1.5">Ιστορικό πράξεων</div>
                      <ul className="space-y-1 text-xs">
                        {g.events.map(e => (
                          <li key={e.id} className="flex justify-between gap-2 border-b border-rule py-1">
                            <span>{EVENT[e.event_type]}</span>
                            <span className="tnum font-mono text-ink2">
                              {eur(e.amount_before)} → {eur(e.amount_after)}
                            </span>
                            <span className="font-mono text-ink3">{date(e.decision_date)}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>

                <div className="space-y-4">
                  <div>
                    <div className="label-xs mb-1.5">
                      Μείωση κατά 70% <LegalRef id="N4412/72/14b" />
                    </div>
                    <BlockerList blockers={reductionBlockers} dense />
                    {g.status === 'energi' && (
                      <Button
                        className="mt-2"
                        variant={canReduce ? 'primary' : 'secondary'}
                        onClick={async () => {
                          try {
                            await api.reduceGuarantee70(g.id)
                            toast.push('success', 'Καταχωρήθηκε η μείωση 70%',
                              'Η πράξη συνδέθηκε με την εγκεκριμένη τελική επιμέτρηση.')
                          } catch (e) {
                            toast.push('error', 'Η μείωση απορρίφθηκε',
                              e instanceof RuleViolation ? e.blockers.map(b => b.message).join('\n')
                                : e instanceof Error ? e.message : undefined)
                          }
                        }}
                      >
                        {canReduce ? 'Έκδοση πράξης μείωσης 70%' : 'Απόπειρα μείωσης 70%'}
                      </Button>
                    )}
                  </div>

                  <div className="border-t border-rule pt-3">
                    <div className="label-xs mb-1.5">
                      Ολική επιστροφή <LegalRef id="N4412/72/14b" />
                    </div>
                    <BlockerList blockers={releaseBlockers} dense />
                    {g.status !== 'apodesmevmeni' && (
                      <Button
                        className="mt-2"
                        variant={canRelease ? 'primary' : 'secondary'}
                        onClick={async () => {
                          try {
                            await api.releaseGuarantee(g.id)
                            toast.push('success', 'Η εγγύηση επιστράφηκε')
                          } catch (e) {
                            toast.push('error', 'Η επιστροφή απορρίφθηκε',
                              e instanceof RuleViolation ? e.blockers.map(b => b.message).join('\n')
                                : e instanceof Error ? e.message : undefined)
                          }
                        }}
                      >
                        {canRelease ? 'Επιστροφή εγγύησης' : 'Απόπειρα επιστροφής'}
                      </Button>
                    )}
                  </div>
                </div>
              </div>
            </Card>
          )
        })
      )}

      <Card>
        <CardHeader title="Ακολουθία αποδέσμευσης" subtitle="Η σειρά που επιβάλλει ο νόμος." />
        <Table minWidth={620}>
          <thead>
            <tr><Th className="w-8" /><Th>Βήμα</Th><Th>Προϋπόθεση</Th><Th>Διάταξη</Th></tr>
          </thead>
          <tbody>
            <tr>
              <Td className="font-mono text-xs text-ink3">1</Td>
              <Td>Έγκριση τελικής επιμέτρησης</Td>
              <Td className="text-xs text-ink2">Υποβολή αναδόχου, έκθεση επιβλέποντος, πράξη Δ.Υ.</Td>
              <Td><LegalRef id="N4412/151/9" /></Td>
            </tr>
            <tr>
              <Td className="font-mono text-xs text-ink3">2</Td>
              <Td>Μείωση εγγύησης κατά 70%</Td>
              <Td className="text-xs text-ink2">Αμέσως μετά το βήμα 1</Td>
              <Td><LegalRef id="N4412/72/14b" /></Td>
            </tr>
            <tr>
              <Td className="font-mono text-xs text-ink3">3</Td>
              <Td>Παραλαβή & έγκριση πρωτοκόλλου</Td>
              <Td className="text-xs text-ink2">Μετά τη λήξη του χρόνου συντήρησης</Td>
              <Td><LegalRef id="N4412/172" /></Td>
            </tr>
            <tr>
              <Td className="font-mono text-xs text-ink3">4</Td>
              <Td>Έγκριση τελικού λογαριασμού</Td>
              <Td className="text-xs text-ink2">Εκκαθάριση εκατέρωθεν απαιτήσεων</Td>
              <Td><LegalRef id="N4412/152" /></Td>
            </tr>
            <tr>
              <Td className="font-mono text-xs text-ink3">5</Td>
              <Td>Ολική επιστροφή εγγυήσεων</Td>
              <Td className="text-xs text-ink2">Μόνο εφόσον ολοκληρωθούν τα βήματα 3 και 4</Td>
              <Td><LegalRef id="N4412/72/14b" /></Td>
            </tr>
          </tbody>
        </Table>
      </Card>
    </div>
  )
}
