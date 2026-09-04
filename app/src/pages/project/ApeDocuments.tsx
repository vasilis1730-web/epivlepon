/**
 * Έγγραφα του Ανακεφαλαιωτικού Πίνακα.
 *
 * Παράγονται εξ ολοκλήρου από τα στοιχεία του ΑΠΕ και της σύμβασης — δεν
 * πληκτρολογείται κανένα ποσό. Έτσι η αιτιολογική έκθεση, το φύλλο ελέγχου
 * και η εισήγηση λένε πάντα ό,τι λέει και ο πίνακας.
 */
import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import * as api from '@/lib/api'
import { useQuery } from '@/hooks/useQuery'
import {
  Badge, Button, Card, CardHeader, LegalRef, Spinner,
} from '@/components/ui'
import { aitiologikiEkthesi, eisigisiEpitropis, fylloElegchou } from '@/lib/apeDocuments'
import { apeCheckSheet } from '@/lib/rules'
import { cx, eur } from '@/lib/format'

type DocKind = 'ekthesi' | 'fyllo' | 'eisigisi'

const DOCS: { kind: DocKind; title: string; legal: string; note: string }[] = [
  {
    kind: 'ekthesi', title: 'Αιτιολογική Έκθεση', legal: 'N4412/156/2',
    note: 'Α. Ιστορικό — Β. Ανακεφαλαιωτικός Πίνακας — Γ. Δαπάνη',
  },
  {
    kind: 'fyllo', title: 'Φύλλο ελέγχου επί έλαττον', legal: 'N4412/156/3c',
    note: 'Έλεγχος ανά ομάδα εργασιών κατά τις εγκυκλίους 20/2006 και 30/2007',
  },
  {
    kind: 'eisigisi', title: 'Εισήγηση προς τη Δημοτική Επιτροπή', legal: 'N4412/156',
    note: 'Για τη λήψη της εγκριτικής απόφασης',
  },
]

export default function ApeDocuments() {
  const { projectId = '', apeId = '' } = useParams()
  const nav = useNavigate()
  const [kind, setKind] = useState<DocKind>('ekthesi')

  const { data, loading } = useQuery(async () => {
    const [org, project, contract, apes, me] = await Promise.all([
      api.getOrganization(), api.getProject(projectId), api.getContract(projectId),
      api.getApes(projectId), api.getProfile().catch(() => null),
    ])
    return { org, project, contract, ape: apes.find(a => a.id === apeId), me }
  }, [projectId, apeId])

  const html = useMemo(() => {
    if (!data?.ape || !data.contract || !data.project || !data.org) return ''
    const ctx = {
      org: data.org,
      project: data.project,
      contract: data.contract,
      ape: data.ape,
      author: data.me
        ? { full_name: data.me.full_name, specialty: data.me.specialty }
        : null,
      head: null,
    }
    if (kind === 'ekthesi') return aitiologikiEkthesi(ctx)
    if (kind === 'fyllo') return fylloElegchou(ctx)
    return eisigisiEpitropis(ctx)
  }, [data, kind])

  const check = useMemo(() => {
    if (!data?.ape || !data.contract) return null
    const c = data.contract
    return apeCheckSheet(data.ape.lines, {
      geOePct: c.ge_oe_pct ?? 18,
      contractWorksPlusGeOe:
        Math.round((c.initial_value_net - c.contingency_amount) * 100) / 100,
      contingencyAmount: c.contingency_amount,
    })
  }, [data])

  if (loading) return <Spinner />
  if (!data?.ape) {
    return (
      <Card className="mx-auto max-w-xl">
        <CardHeader title="Ο ΑΠΕ δεν βρέθηκε" />
        <div className="px-4 py-4 text-sm text-ink2">
          <p>Ο πίνακας που ζητήθηκε δεν υπάρχει σε αυτό το έργο.</p>
          <div className="pt-3">
            <Button onClick={() => nav(`/erga/${projectId}/ape`)}>Πίσω στους ΑΠΕ</Button>
          </div>
        </div>
      </Card>
    )
  }

  const printDoc = () => {
    const w = window.open('', '_blank')
    if (!w) return
    w.document.write(html)
    w.document.close()
    w.focus()
    setTimeout(() => w.print(), 250)
  }

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="label-xs">Άρθρα 156 &amp; 132 ν. 4412/2016</div>
          <h1 className="mt-1 font-serif text-2xl font-bold">
            Έγγραφα {data.ape.serial_no}ου ΑΠΕ
          </h1>
          <p className="mt-1 max-w-3xl text-sm text-ink2">
            Παράγονται από τα στοιχεία του πίνακα. Κανένα ποσό δεν πληκτρολογείται
            ξανά — αν αλλάξει ο ΑΠΕ, αλλάζουν και τα τρία έγγραφα.
          </p>
        </div>
        <div className="flex shrink-0 gap-2">
          <Button variant="secondary" onClick={() => nav(`/erga/${projectId}/ape`)}>
            Πίσω
          </Button>
          <Button onClick={printDoc}>Εκτύπωση</Button>
        </div>
      </header>

      {check && (
        <Card>
          <CardHeader
            title="Έλεγχος ορίων"
            legalRef="N4412/156/3c"
            right={<Badge tone={check.passes ? 'accent' : 'oxide'}>
              {check.passes ? 'χωρίς παράβαση' : 'παράβαση'}
            </Badge>}
          />
          <div className="grid gap-4 px-4 py-4 text-sm sm:grid-cols-3">
            <Stat k="Χρησιμοποιηθέντα απρόβλεπτα" v={eur(check.contingencyApplied)}
              sub={`από ${eur(check.contingencyAmount)}`} />
            <Stat k="Επί πλέον καθ' υπέρβαση 20%" v={eur(check.s2OverExcess)}
              sub={check.overBeyondContingency
                ? `μη καλυπτόμενο: ${eur(check.overBeyondContingency)}`
                : 'καλύπτεται από τα απρόβλεπτα'}
              warn={check.overBeyondContingency > 0} />
            <Stat k="Επί έλαττον" v={eur(check.s2Under)}
              sub={`όριο 10%: ${eur(check.maxSavings)}`}
              warn={check.rule10Breach > 0} />
          </div>
        </Card>
      )}

      <div className="flex flex-wrap gap-2">
        {DOCS.map(d => (
          <button
            key={d.kind}
            onClick={() => setKind(d.kind)}
            className={cx(
              'rounded border px-3 py-2 text-left text-sm transition',
              kind === d.kind
                ? 'border-accent bg-accent-soft text-ink'
                : 'border-rule2 bg-surface text-ink2 hover:border-rule',
            )}
          >
            <div className="font-medium">{d.title}</div>
            <div className="mt-0.5 text-2xs text-ink3">
              {d.note} · <LegalRef id={d.legal} />
            </div>
          </button>
        ))}
      </div>

      <Card className="overflow-hidden">
        <iframe
          title={DOCS.find(d => d.kind === kind)!.title}
          srcDoc={html}
          className="h-[900px] w-full border-0 bg-white"
        />
      </Card>
    </div>
  )
}

function Stat({ k, v, sub, warn }: {
  k: string; v: string; sub: string; warn?: boolean
}) {
  return (
    <div>
      <div className="label-xs">{k}</div>
      <div className="tnum mt-0.5 font-mono text-base font-semibold">{v}</div>
      <div className={cx('mt-0.5 text-2xs', warn ? 'text-oxide' : 'text-ink3')}>{sub}</div>
    </div>
  )
}
