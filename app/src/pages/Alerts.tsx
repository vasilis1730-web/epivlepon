/**
 * Ειδοποιήσεις — μία οθόνη με ό,τι τρέχει σε ΟΛΑ τα έργα του χρήστη.
 *
 * Δεν υπάρχει «διάβασα το μήνυμα»: η ειδοποίηση φεύγει μόνο όταν φύγει η
 * αιτία της. Πρώτες έρχονται οι προθεσμίες σιωπηρής έγκρισης, γιατί εκεί η
 * αδράνεια δεν αναβάλλει την απόφαση — την παίρνει.
 */
import { Link } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { getAlerts } from '@/lib/alerts'
import { Badge, Card, CardHeader, LegalRef, Spinner } from '@/components/ui'
import { cx, date, relativeDays } from '@/lib/format'
import type { Alert, AlertLevel } from '@/lib/types'

const LEVEL: Record<AlertLevel, { label: string; tone: 'oxide' | 'brass' | 'neutral' }> = {
  overdue: { label: 'Εκπρόθεσμο', tone: 'oxide' },
  critical: { label: 'Κρίσιμο', tone: 'oxide' },
  warning: { label: 'Προσοχή', tone: 'brass' },
}

const KIND: Record<Alert['kind'], string> = {
  tacit_approval: 'Σιωπηρή έγκριση',
  ape_violation: 'Όρια ΑΠΕ',
  hidden_work: 'Αφανείς εργασίες',
  stage_deadline: 'Προθεσμία σταδίου',
  contract_deadline: 'Προθεσμία έργου',
}

export default function Alerts() {
  const { data, loading } = useQuery(() => getAlerts(), [])
  if (loading || !data) return <Spinner />

  const counts = {
    overdue: data.filter(a => a.level === 'overdue').length,
    critical: data.filter(a => a.level === 'critical').length,
    warning: data.filter(a => a.level === 'warning').length,
  }
  const tacit = data.filter(a => a.kind === 'tacit_approval')

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρα 145, 147, 151, 152, 156 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-3xl font-bold tracking-tight">Ειδοποιήσεις</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Ό,τι εκκρεμεί σε όλα τα έργα σας. Δεν σημειώνονται «διαβασμένες» και δεν
          σβήνονται: μια ειδοποίηση φεύγει μόνο όταν τακτοποιηθεί η αιτία της.
        </p>
      </header>

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat k="Εκπρόθεσμα" v={counts.overdue} warn={counts.overdue > 0} />
        <Stat k="Κρίσιμα (≤5 ημέρες)" v={counts.critical} warn={counts.critical > 0} />
        <Stat k="Προσοχή (≤15 ημέρες)" v={counts.warning} />
      </div>

      {tacit.length > 0 && (
        <Card>
          <CardHeader
            title="Προθεσμίες που παράγουν μόνες τους αποτέλεσμα"
            subtitle="Η άπρακτη πάροδος ισοδυναμεί με έγκριση — η αναβολή δεν είναι ουδέτερη"
            legalRef="N4412/152"
            right={<Badge tone="oxide">{tacit.length}</Badge>}
          />
          <div className="divide-y divide-rule2">
            {tacit.map(a => <Row key={a.id} a={a} />)}
          </div>
        </Card>
      )}

      <Card>
        <CardHeader
          title="Όλες οι εκκρεμότητες"
          subtitle="Κατά σειρά επείγοντος"
          right={<Badge tone="muted">{data.length}</Badge>}
        />
        {data.length === 0 ? (
          <div className="px-4 py-10 text-center text-sm text-ink3">
            Καμία εκκρεμότητα εντός δεκαπενθημέρου.
          </div>
        ) : (
          <div className="divide-y divide-rule2">
            {data.map(a => <Row key={a.id} a={a} />)}
          </div>
        )}
      </Card>
    </div>
  )
}

function Row({ a }: { a: Alert }) {
  const l = LEVEL[a.level]
  return (
    <Link to={a.href} className="block px-4 py-3 transition hover:bg-raised">
      <div className="flex flex-wrap items-baseline gap-2">
        <Badge tone={l.tone}>{l.label}</Badge>
        <span className="text-2xs uppercase tracking-wide text-ink3">{KIND[a.kind]}</span>
        <span className="font-medium">{a.title}</span>
        <span className="ml-auto shrink-0 text-xs text-ink3">
          {a.project_code}
        </span>
      </div>
      <p className="mt-1 text-xs text-ink2">{a.detail}</p>
      <div className="mt-1 flex flex-wrap items-center gap-2 text-2xs text-ink3">
        {a.due_date && (
          <span className={cx('tnum', a.level === 'overdue' && 'text-oxide')}>
            {date(a.due_date)} · {relativeDays(a.days_left)}
          </span>
        )}
        {a.legal_ref && <LegalRef id={a.legal_ref} />}
        <span className="truncate">{a.project_title}</span>
      </div>
    </Link>
  )
}

function Stat({ k, v, warn }: { k: string; v: number; warn?: boolean }) {
  return (
    <Card className="p-4">
      <div className="label-xs">{k}</div>
      <div className={cx('tnum mt-1 font-serif text-2xl font-semibold',
        warn ? 'text-oxide' : 'text-ink')}>{v}</div>
    </Card>
  )
}
