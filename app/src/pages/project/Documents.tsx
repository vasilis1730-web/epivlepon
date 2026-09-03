import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import * as api from '@/lib/api'
import { Badge, Card, CardHeader, LegalRef, Spinner, Table, Td, Th } from '@/components/ui'
import { GenerateButton, hasTemplate } from '@/components/DocumentGenerator'
import { catalogue, DOCS_BY_STAGE, STAGES } from '@/lib/catalogue'
import { PARTY } from '@/lib/labels'
import { date } from '@/lib/format'

export default function Documents() {
  const { projectId = '' } = useParams()
  const { data, loading } = useQuery(() => api.getDocuments(projectId), [projectId])
  if (loading || !data) return <Spinner />

  const existing = new Set(data.map(d => d.doc_code))
  const required = STAGES.flatMap(s =>
    (DOCS_BY_STAGE[s.code] ?? []).map(d => ({ ...d, stageTitle: s.title, ordinal: s.ordinal })),
  ).sort((a, b) => a.ordinal - b.ordinal)

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Αυτοματοποίηση εγγράφων</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Έγγραφα έργου</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Τα πρότυπα της Υπηρεσίας συμπληρώνονται αυτόματα από τα δεδομένα του έργου. Κάθε
          παραγόμενο έγγραφο φέρει αριθμό πρωτοκόλλου και, όπου απαιτείται, ΑΔΑ/ΑΔΑΜ.
          Επιλέξτε «Παραγωγή» σε όποιο έγγραφο διαθέτει πρότυπο για προεπισκόπηση πριν την
          οριστική έκδοση.
        </p>
      </header>

      <Card>
        <CardHeader title="Παραχθέντα έγγραφα" subtitle={`${data.length} έγγραφα στον φάκελο`} />
        {data.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-ink3">Δεν έχουν παραχθεί έγγραφα.</p>
        ) : (
          <Table minWidth={760}>
            <thead>
              <tr>
                <Th>Έγγραφο</Th><Th>Κωδικός προτύπου</Th>
                <Th align="end">Αρ. πρωτ.</Th><Th align="end">Ημερομηνία</Th>
                <Th>ΑΔΑ</Th><Th>Κατάσταση</Th>
              </tr>
            </thead>
            <tbody>
              {data.map(d => (
                <tr key={d.id}>
                  <Td className="font-medium">{d.title}</Td>
                  <Td className="font-mono text-xs text-ink2">{d.doc_code}</Td>
                  <Td align="end" className="font-mono text-xs">{d.protocol_no ?? '—'}</Td>
                  <Td align="end" className="font-mono text-xs">{date(d.protocol_date)}</Td>
                  <Td className="font-mono text-xs text-brass">{d.ada ?? '—'}</Td>
                  <Td><Badge tone={d.status === 'approved' ? 'accent' : 'neutral'}>{d.status}</Badge></Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      <Card>
        <CardHeader
          title="Υποχρεωτικά έγγραφα ανά στάδιο"
          subtitle="Το στάδιο δεν κλείνει αν λείπει έγγραφο σημειωμένο ως υποχρεωτικό."
        />
        <Table minWidth={820}>
          <thead>
            <tr>
              <Th className="w-10">#</Th><Th>Στάδιο</Th><Th>Έγγραφο</Th>
              <Th>Συντάσσεται από</Th><Th>Διάταξη</Th><Th align="center">Στον φάκελο</Th>
              <Th align="end">Ενέργεια</Th>
            </tr>
          </thead>
          <tbody>
            {required.map(d => (
              <tr key={d.stage_code + d.doc_code}>
                <Td className="font-mono text-xs text-ink3 tnum">
                  {String(d.ordinal).padStart(2, '0')}
                </Td>
                <Td className="text-xs text-ink2">{d.stageTitle}</Td>
                <Td>
                  {d.title}
                  <span className="ml-2 font-mono text-2xs text-ink3">{d.doc_code}</span>
                </Td>
                <Td className="text-xs text-ink2">{PARTY[d.produced_by]}</Td>
                <Td><LegalRef id={d.legal_ref_id} /></Td>
                <Td align="center">
                  {existing.has(d.doc_code)
                    ? <Badge tone="accent">ναι</Badge>
                    : <Badge tone={d.is_mandatory ? 'oxide' : 'muted'}>{d.is_mandatory ? 'λείπει' : '—'}</Badge>}
                </Td>
                <Td align="end">
                  {hasTemplate(d.doc_code)
                    ? <GenerateButton target={{ projectId, docCode: d.doc_code }} />
                    : <span className="text-2xs text-ink3">χωρίς πρότυπο</span>}
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Card>

      <Card>
        <CardHeader
          title="Μητρώο διατάξεων"
          subtitle={`${catalogue.legal.length} διατάξεις τεκμηριώνουν τους ελέγχους της εφαρμογής.`}
        />
        <Table minWidth={700}>
          <thead>
            <tr><Th>Παραπομπή</Th><Th>Αντικείμενο</Th><Th>ΦΕΚ</Th></tr>
          </thead>
          <tbody>
            {catalogue.legal.map(l => (
              <tr key={l.id}>
                <Td><LegalRef id={l.id} /></Td>
                <Td className="text-sm">{l.title}</Td>
                <Td className="font-mono text-xs text-ink3">{(l as { fek?: string }).fek ?? '—'}</Td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Card>
    </div>
  )
}
