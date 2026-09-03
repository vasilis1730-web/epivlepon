import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import * as api from '@/lib/api'
import { Badge, Card, CardHeader, LegalRef, Spinner } from '@/components/ui'
import { cx, date, daysUntil, relativeDays } from '@/lib/format'

export default function CompletionPage() {
  const { projectId = '' } = useParams()

  const { data, loading } = useQuery(async () => {
    const [completion, finalM, contract] = await Promise.all([
      api.getCompletion(projectId), api.getFinalMeasurement(projectId), api.getContract(projectId),
    ])
    return { completion, finalM, contract }
  }, [projectId])

  if (loading || !data?.contract) return <Spinner />
  const { completion, finalM, contract } = data

  const steps: Step[] = [
    {
      title: 'Λήξη εγκεκριμένου χρόνου περαίωσης',
      legal: 'N4412/147/1',
      party: 'Σύμβαση',
      date: completion?.approved_completion_date ?? contract.current_end_date,
      done: Boolean(completion),
      note: 'Αφετηρία όλων των προθεσμιών περαίωσης.',
    },
    {
      title: 'Δήλωση περαίωσης αναδόχου',
      legal: 'N4412/168/2',
      party: 'Ανάδοχος',
      date: completion?.contractor_declared_at ?? null,
      done: Boolean(completion?.contractor_declared_at),
      note: 'Μπορεί να υποβληθεί και πριν τη λήξη, εφόσον οι εργασίες ολοκληρώθηκαν.',
    },
    {
      title: 'Έκθεση επιβλέποντος περί περαίωσης',
      legal: 'N4412/168/1',
      party: 'Επιβλέπων',
      date: completion?.supervisor_report_at ?? null,
      due: completion?.supervisor_report_due ?? null,
      done: Boolean(completion?.supervisor_report_at),
      note: 'Εντός 30 ημερών από τη λήξη του εγκεκριμένου χρόνου περαίωσης.',
    },
    {
      title: 'Βεβαίωση Περάτωσης Εργασιών',
      legal: 'N4412/168/2',
      party: 'Προϊστάμενος Δ.Υ.',
      date: completion?.certificate_issued_at ?? null,
      due: completion?.certificate_due ?? null,
      done: Boolean(completion?.certificate_issued_at),
      note: 'Εντός 10 ημερών από την έκθεση· άλλως τεκμαίρεται εκδοθείσα 30 ημέρες μετά την όχληση.',
    },
    {
      title: 'Τελική επιμέτρηση — υποβολή',
      legal: 'N4412/151/9',
      party: 'Ανάδοχος',
      date: finalM?.submitted_at ?? null,
      due: finalM?.contractor_due ?? null,
      done: Boolean(finalM?.submitted_at),
      note: 'Εντός 2 μηνών από την περαίωση· καθυστέρηση επισύρει ρήτρα 2‰/μήνα.',
    },
    {
      title: 'Τελική επιμέτρηση — έγκριση Δ.Υ.',
      legal: 'N4412/151/9',
      party: 'Διευθύνουσα Υπηρεσία',
      date: finalM?.approved_at ?? null,
      due: finalM?.approval_due ?? null,
      done: Boolean(finalM?.approved_at),
      note: 'Ενεργοποιεί τη μείωση της εγγύησης κατά 70%.',
    },
    {
      title: 'Χρόνος υποχρεωτικής συντήρησης',
      legal: 'N4412/171',
      party: 'Ανάδοχος',
      date: completion?.certificate_issued_at
        ? addMonthsIso(completion.certificate_issued_at, contract.maintenance_months) : null,
      done: false,
      note: `${contract.maintenance_months} μήνες από την επομένη της Βεβαίωσης Περάτωσης.`,
    },
    {
      title: 'Ορισμός επιτροπής παραλαβής',
      legal: 'N4412/172',
      party: 'Προϊσταμένη Αρχή',
      date: null,
      done: false,
      note: 'Πενταμελής, τουλάχιστον 3 μήνες πριν τη λήξη της συντήρησης.',
    },
    {
      title: 'Παραλαβή & πρωτόκολλο',
      legal: 'N4412/172',
      party: 'Επιτροπή Παραλαβής',
      date: null,
      done: false,
      note: 'Εντός 3 μηνών· άπρακτη πάροδος = αυτοδίκαιη παραλαβή.',
    },
    {
      title: 'Τελικός λογαριασμός & επιστροφή εγγυήσεων',
      legal: 'N4412/152',
      party: 'Ανάδοχος / Δ.Υ.',
      date: null,
      done: false,
      note: 'Εκκαθάριση εκατέρωθεν απαιτήσεων· μετά ακολουθεί η ολική επιστροφή εγγυήσεων.',
    },
  ]

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρα 168, 171, 172 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Περαίωση & παραλαβή</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Η αλυσίδα από τη λήξη της προθεσμίας έως την επιστροφή των εγγυήσεων. Κάθε κρίκος
          δεσμεύει χρονικά τον επόμενο.
        </p>
      </header>

      {completion?.deemed_issued && (
        <div className="rounded border-l-2 border-l-brass bg-brass-soft/50 px-4 py-3 text-sm">
          Η Βεβαίωση Περάτωσης <strong>τεκμαίρεται εκδοθείσα</strong> λόγω άπρακτης παρόδου
          30 ημερών από την όχληση του αναδόχου. Οι υπαίτιοι υπέχουν πειθαρχική ευθύνη.{' '}
          <LegalRef id="N4412/168/2" />
        </div>
      )}

      <Card>
        <CardHeader title="Αλυσίδα περαίωσης" />
        <ol className="divide-y divide-rule">
          {steps.map((s, i) => {
            const days = s.due && !s.date ? daysUntil(s.due) : null
            return (
              <li key={i} className="grid grid-cols-[2rem_1fr] gap-3 px-4 py-3.5">
                <span
                  className={cx(
                    'mt-0.5 flex h-6 w-6 items-center justify-center rounded-full border font-mono text-2xs',
                    s.done ? 'border-accent bg-accent text-paper' : 'border-rule2 text-ink3',
                  )}
                >
                  {i + 1}
                </span>
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className={cx('font-medium', !s.done && 'text-ink2')}>{s.title}</span>
                    <Badge tone="muted">{s.party}</Badge>
                    <LegalRef id={s.legal} />
                  </div>
                  <p className="mt-0.5 text-xs text-ink3">{s.note}</p>
                  <div className="mt-1.5 flex flex-wrap gap-3 font-mono text-xs">
                    {s.date && <span className="text-accent">✓ {date(s.date)}</span>}
                    {s.due && !s.date && (
                      <span className={cx((days ?? 0) < 0 ? 'text-oxide' : 'text-brass')}>
                        προθεσμία {date(s.due)} · {relativeDays(days)}
                      </span>
                    )}
                    {!s.date && !s.due && <span className="text-ink3">εκκρεμεί</span>}
                  </div>
                </div>
              </li>
            )
          })}
        </ol>
      </Card>
    </div>
  )
}

interface Step {
  title: string; legal: string; party: string
  date: string | null; due?: string | null; done: boolean; note: string
}

function addMonthsIso(iso: string, months: number) {
  const d = new Date(iso + 'T00:00:00')
  d.setMonth(d.getMonth() + months)
  return d.toISOString().slice(0, 10)
}
