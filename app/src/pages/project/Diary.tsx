import { useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import * as api from '@/lib/api'
import {
  Badge, Button, Card, CardHeader, Field, Input, LegalRef, Modal, Select,
  Spinner, Table, Td, Textarea, Th,
} from '@/components/ui'
import { DIARY_STATUS, WEATHER } from '@/lib/labels'
import { cx, date, eur, today } from '@/lib/format'
import { diaryPenalty, missingDiaryDays } from '@/lib/rules'
import type { DiaryEntry } from '@/lib/types'

export default function Diary() {
  const { projectId = '' } = useParams()
  const toast = useToast()
  const [newOpen, setNewOpen] = useState(false)

  const { data, loading } = useQuery(async () => {
    const [entries, contract] = await Promise.all([api.getDiary(projectId), api.getContract(projectId)])
    return { entries, contract }
  }, [projectId])

  const missing = useMemo(() => {
    if (!data?.contract) return []
    const start = data.contract.works_start_deadline && data.contract.works_start_deadline < today()
      ? data.contract.works_start_deadline : data.contract.signed_at
    return data.entries.length ? missingDiaryDays(data.entries, start) : []
  }, [data])

  if (loading || !data?.contract) return <Spinner />
  const { entries, contract } = data
  const penalty = diaryPenalty(missing.length, contract.diary_penalty_per_day)

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="label-xs">Άρθρο 146 ν. 4412/2016</div>
          <h1 className="mt-1 font-serif text-2xl font-bold">Ημερολόγιο έργου</h1>
          <p className="mt-1 max-w-3xl text-sm text-ink2">
            Τηρείται καθημερινά και ηλεκτρονικά από τεχνικό του αναδόχου· ο επιβλέπων
            ελέγχει και διορθώνει εντός δύο εργασίμων ημερών.
          </p>
        </div>
        <Button variant="primary" onClick={() => setNewOpen(true)}>Νέα εγγραφή</Button>
      </header>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="p-4">
          <div className="label-xs">Εγγραφές</div>
          <div className="tnum mt-1 font-serif text-2xl font-semibold">{entries.length}</div>
        </Card>
        <Card className={cx('p-4', missing.length > 0 && 'border-oxide')}>
          <div className="label-xs">Ημέρες χωρίς εγγραφή</div>
          <div className={cx('tnum mt-1 font-serif text-2xl font-semibold', missing.length > 0 && 'text-oxide')}>
            {missing.length}
          </div>
          {missing.length > 0 && (
            <div className="mt-1 text-xs text-ink3">
              {missing.slice(0, 5).map(d => date(d)).join(' · ')}
              {missing.length > 5 && ` +${missing.length - 5}`}
            </div>
          )}
        </Card>
        <Card className={cx('p-4', penalty > 0 && 'border-oxide')}>
          <div className="label-xs">Ειδική ποινική ρήτρα</div>
          <div className={cx('tnum mt-1 font-serif text-2xl font-semibold', penalty > 0 && 'text-oxide')}>
            {eur(penalty)}
          </div>
          <div className="mt-1 text-xs text-ink3">
            {eur(contract.diary_penalty_per_day)} ανά ημέρα · <LegalRef id="N4412/146" />
          </div>
        </Card>
      </div>

      <Card>
        <CardHeader
          title="Εγγραφές ημερολογίου"
          subtitle="Οι εγγραφές σε κατάσταση «Υποβλήθηκε» εκκρεμούν έλεγχο από τον επιβλέποντα."
          legalRef="N4412/146"
        />
        {entries.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-ink3">
            Δεν έχουν καταχωρηθεί εγγραφές. Η μη τήρηση επισύρει ποινική ρήτρα ανά ημέρα.
          </p>
        ) : (
          <Table minWidth={900}>
            <thead>
              <tr>
                <Th>Ημερομηνία</Th><Th>Καιρός</Th><Th>Προσωπικό</Th>
                <Th>Εργασίες</Th><Th>Κατάσταση</Th><Th align="end">Ενέργεια</Th>
              </tr>
            </thead>
            <tbody>
              {entries.slice(0, 60).map(e => (
                <tr key={e.id}>
                  <Td className="whitespace-nowrap font-mono text-xs">{date(e.entry_date)}</Td>
                  <Td className="text-xs text-ink2">{e.weather ? WEATHER[e.weather] : '—'}</Td>
                  <Td className="text-xs text-ink2">
                    {e.personnel.reduce((s, p) => s + p.arithmos, 0)} άτομα
                    <span className="block text-ink3">
                      {e.personnel.map(p => `${p.eidikotita} ${p.arithmos}`).join(', ')}
                    </span>
                  </Td>
                  <Td className="max-w-md text-xs">
                    {e.works_description}
                    {e.delay_reasons && (
                      <span className="mt-0.5 block text-oxide">Καθυστέρηση: {e.delay_reasons}</span>
                    )}
                  </Td>
                  <Td>
                    <Badge tone={e.status === 'approved' ? 'accent' : e.status === 'submitted' ? 'brass' : 'neutral'}>
                      {DIARY_STATUS[e.status]}
                    </Badge>
                  </Td>
                  <Td align="end">
                    {e.status === 'submitted' && (
                      <Button
                        onClick={async () => {
                          await api.reviewDiaryEntry(projectId, e.id)
                          toast.push('success', 'Ελέγχθηκε', `Εγγραφή ${date(e.entry_date)}`)
                        }}
                      >
                        Έλεγχος
                      </Button>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      <NewEntryModal
        open={newOpen}
        onClose={() => setNewOpen(false)}
        projectId={projectId}
        onSaved={() => { setNewOpen(false); toast.push('success', 'Η εγγραφή καταχωρήθηκε') }}
      />
    </div>
  )
}

function NewEntryModal({ open, onClose, projectId, onSaved }: {
  open: boolean; onClose: () => void; projectId: string; onSaved: () => void
}) {
  const [entryDate, setEntryDate] = useState(today())
  const [weather, setWeather] = useState('aithria')
  const [crew, setCrew] = useState(6)
  const [works, setWorks] = useState('')
  const [delays, setDelays] = useState('')

  async function save() {
    const entry: DiaryEntry = {
      id: `new-${Date.now()}`, project_id: projectId, entry_date: entryDate,
      weather, personnel: [{ eidikotita: 'Συνεργείο', arithmos: crew }],
      equipment: [], works_description: works,
      delay_reasons: delays || null, accidents: null, supervisor_orders: null,
      status: 'submitted', submitted_at: new Date().toISOString(),
      reviewed_at: null, approved_at: null,
    }
    await api.addDiaryEntry(entry)
    setWorks(''); setDelays('')
    onSaved()
  }

  return (
    <Modal
      open={open} onClose={onClose} title="Νέα εγγραφή ημερολογίου" wide
      footer={
        <>
          <Button onClick={onClose}>Άκυρο</Button>
          <Button variant="primary" disabled={works.trim().length < 5} onClick={save}>Καταχώριση</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-3">
        <Field label="Ημερομηνία">
          <Input type="date" value={entryDate} onChange={e => setEntryDate(e.target.value)} />
        </Field>
        <Field label="Καιρικές συνθήκες">
          <Select value={weather} onChange={e => setWeather(e.target.value)}>
            {Object.entries(WEATHER).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </Select>
        </Field>
        <Field label="Προσωπικό (άτομα)">
          <Input type="number" min={0} value={crew} onChange={e => setCrew(Number(e.target.value))} />
        </Field>
      </div>
      <div className="mt-4 space-y-4">
        <Field label="Εκτελεσθείσες εργασίες" legalRef="N4412/146">
          <Textarea value={works} onChange={e => setWorks(e.target.value)}
            placeholder="Θέση, είδος και ποσότητα εργασιών, κρίσιμες έναρξεις/περατώσεις…" />
        </Field>
        <Field label="Καθυστερήσεις / έκτακτα περιστατικά" hint="Προαιρετικό">
          <Textarea value={delays} onChange={e => setDelays(e.target.value)} />
        </Field>
      </div>
    </Modal>
  )
}
