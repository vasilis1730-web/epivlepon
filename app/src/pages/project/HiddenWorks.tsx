import { useEffect, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import * as api from '@/lib/api'
import { RuleViolation } from '@/lib/store'
import {
  Badge, Button, Card, CardHeader, LegalRef, Modal, Spinner,
  Table, Td, Th,
} from '@/components/ui'
import { hiddenWorkAlert } from '@/lib/rules'
import { cx, date, daysUntil, relativeDays } from '@/lib/format'
import type { HiddenWorkNotice, HiddenWorkPhoto } from '@/lib/types'

export default function HiddenWorks() {
  const { projectId = '' } = useParams()
  const toast = useToast()
  const [inspecting, setInspecting] = useState<HiddenWorkNotice | null>(null)
  const [photos, setPhotos] = useState<HiddenWorkPhoto[]>([])
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  const { data, loading } = useQuery(() => api.getHiddenWorks(projectId), [projectId])

  // Οι ήδη ανεβασμένες φωτογραφίες της συγκεκριμένης δήλωσης.
  useEffect(() => {
    let live = true
    if (!inspecting) { setPhotos([]); return }
    api.getHiddenWorkPhotos(inspecting.id)
      .then(p => { if (live) setPhotos(p) })
      .catch(() => { if (live) setPhotos([]) })
    return () => { live = false }
  }, [inspecting])

  if (loading || !data) return <Spinner />

  const overdue = data.filter(h => !h.inspected_at && (daysUntil(h.inspection_due) ?? 0) < 0)

  async function addPhotos(files: FileList | null) {
    if (!inspecting || !files?.length) return
    setUploading(true)
    try {
      const n = await api.uploadHiddenWorkPhotos(projectId, inspecting.id, Array.from(files))
      setPhotos(await api.getHiddenWorkPhotos(inspecting.id))
      toast.push('success', n === 1 ? 'Ανέβηκε 1 φωτογραφία' : `Ανέβηκαν ${n} φωτογραφίες`)
    } catch (e) {
      toast.push('error', 'Το ανέβασμα απέτυχε',
        e instanceof Error ? e.message : undefined)
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function removePhoto(photo: HiddenWorkPhoto) {
    try {
      await api.deleteHiddenWorkPhoto(photo)
      setPhotos(ps => ps.filter(p => p.id !== photo.id))
    } catch (e) {
      toast.push('error', 'Η διαγραφή απέτυχε', e instanceof Error ? e.message : undefined)
    }
  }

  async function submitInspection() {
    if (!inspecting) return
    try {
      await api.inspectHiddenWork(inspecting.id)
      toast.push('success', 'Καταχωρήθηκε ο έλεγχος',
        photos.length === 1
          ? 'Μία ψηφιακή φωτογραφία εντάχθηκε στο Μητρώο του Έργου.'
          : `${photos.length} ψηφιακές φωτογραφίες εντάχθηκαν στο Μητρώο του Έργου.`)
      setInspecting(null); setPhotos([])
    } catch (e) {
      toast.push('error', 'Η καταχώριση απορρίφθηκε',
        e instanceof RuleViolation ? e.blockers.map(b => b.message).join('\n')
          : e instanceof Error ? e.message : undefined)
    }
  }

  return (
    <div className="space-y-5">
      <header>
        <div className="label-xs">Άρθρο 151 §7 ν. 4412/2016</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Αφανείς εργασίες</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Ο ανάδοχος υποβάλλει δήλωση γνωστοποίησης και καλεί τον επιβλέποντα{' '}
          <strong>πριν την επικάλυψη</strong>, σε ημερομηνία που δεν απέχει περισσότερο από
          τρεις ημέρες. Η έκθεση συνοδεύεται υποχρεωτικά από ψηφιακές φωτογραφίες.
        </p>
      </header>

      {overdue.length > 0 && (
        <div className="rounded border-l-2 border-l-oxide bg-oxide-soft/50 px-4 py-3">
          <div className="label-xs text-oxide">Υπερημερία κυρίου του έργου</div>
          <p className="mt-1 text-sm text-ink">
            {overdue.length} {overdue.length === 1 ? 'δήλωση' : 'δηλώσεις'} δεν ελέγχθηκαν εντός
            της τριήμερης προθεσμίας. Αν ο ανάδοχος υποστεί ζημία, η παράλειψη συνιστά
            υπερημερία του κυρίου του έργου. <LegalRef id="N4412/151/7" />
          </p>
        </div>
      )}

      <Card>
        <CardHeader title="Δηλώσεις & πρωτόκολλα" legalRef="N4412/151/7" />
        {data.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-ink3">Δεν έχουν δηλωθεί αφανείς εργασίες.</p>
        ) : (
          <Table minWidth={1000}>
            <thead>
              <tr>
                <Th className="w-10">Α/Α</Th><Th>Εργασία / θέση</Th>
                <Th align="end">Πρόσκληση</Th><Th align="end">Προθεσμία ελέγχου</Th>
                <Th align="end">Έλεγχος</Th><Th align="end">Φωτογρ.</Th>
                <Th align="end">Εγκριτική πράξη</Th><Th>Κατάσταση</Th><Th align="end" />
              </tr>
            </thead>
            <tbody>
              {data.map(h => {
                const alert = hiddenWorkAlert(h)
                const dueDays = daysUntil(h.inspection_due)
                return (
                  <tr key={h.id}>
                    <Td className="font-mono text-xs tnum">{h.serial_no}</Td>
                    <Td>
                      <div className="font-medium">{h.work_description}</div>
                      <div className="text-xs text-ink3">{h.location}</div>
                    </Td>
                    <Td align="end" className="font-mono text-xs">{date(h.invitation_sent_at)}</Td>
                    <Td align="end" className="font-mono text-xs">
                      {date(h.inspection_due)}
                      {!h.inspected_at && (
                        <span className={cx('block text-2xs', (dueDays ?? 0) < 0 ? 'text-oxide' : 'text-brass')}>
                          {relativeDays(dueDays)}
                        </span>
                      )}
                    </Td>
                    <Td align="end" className="font-mono text-xs">{date(h.inspected_at)}</Td>
                    <Td align="end">
                      <span className={cx('font-mono text-xs tnum', h.photos_count === 0 && h.inspected_at && 'text-oxide')}>
                        {h.photos_count}
                      </span>
                    </Td>
                    <Td align="end" className="font-mono text-xs">
                      {h.approved_at ? date(h.approved_at) : h.approval_due ? `έως ${date(h.approval_due)}` : '—'}
                    </Td>
                    <Td>
                      <Badge tone={alert.level === 'ok' ? 'accent' : alert.level === 'warn' ? 'brass' : 'oxide'}>
                        {alert.text}
                      </Badge>
                    </Td>
                    <Td align="end">
                      {!h.inspected_at && (
                        <Button onClick={() => setInspecting(h)}>Έλεγχος</Button>
                      )}
                      {h.inspected_at && !h.approved_at && (
                        <Button
                          variant="primary"
                          onClick={async () => {
                            await api.approveHiddenWork(h.id)
                            toast.push('success', 'Εκδόθηκε η εγκριτική πράξη')
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
        )}
      </Card>

      <Modal
        open={Boolean(inspecting)}
        onClose={() => setInspecting(null)}
        title="Έλεγχος αφανών εργασιών"
        footer={
          <>
            <Button onClick={() => setInspecting(null)}>Άκυρο</Button>
            <Button variant="primary" disabled={photos.length === 0 || uploading}
              onClick={submitInspection}>
              Καταχώριση ελέγχου
            </Button>
          </>
        }
      >
        <p className="text-sm text-ink2">{inspecting?.work_description}</p>
        <p className="mt-0.5 text-xs text-ink3">{inspecting?.location}</p>

        <div className="mt-4">
          <div className="label-xs mb-1 flex items-center gap-2">
            Ψηφιακές φωτογραφίες
            <LegalRef id="N4412/151/7" />
          </div>
          <p className="mb-2 text-xs text-ink3">
            Η έκθεση συνοδεύεται απαραίτητα από επαρκή αριθμό φωτογραφιών, οι οποίες
            εντάσσονται στο Μητρώο του Έργου. Ο αριθμός δεν δηλώνεται — προκύπτει από
            τα αρχεία που ανεβαίνουν.
          </p>

          <input
            ref={fileRef}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            multiple
            disabled={uploading}
            onChange={e => addPhotos(e.target.files)}
            className="block w-full text-xs text-ink2 file:mr-3 file:rounded file:border file:border-rule2 file:bg-paper file:px-3 file:py-1.5 file:text-xs file:text-ink"
          />
          {uploading && <p className="mt-2 text-xs text-ink3">Ανέβασμα…</p>}

          {photos.length > 0 && (
            <ul className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-4">
              {photos.map(p => (
                <li key={p.id} className="group relative">
                  <img src={p.url} alt={p.caption ?? 'Φωτογραφία αφανούς εργασίας'}
                    className="h-24 w-full rounded border border-rule2 object-cover" />
                  <button
                    type="button"
                    onClick={() => removePhoto(p)}
                    aria-label={`Διαγραφή ${p.caption ?? 'φωτογραφίας'}`}
                    className="absolute right-1 top-1 rounded bg-ink/70 px-1.5 text-xs text-paper opacity-0 transition group-hover:opacity-100 focus:opacity-100"
                  >
                    ✕
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {photos.length === 0 ? (
          <p className="mt-3 rounded border border-oxide bg-oxide-soft px-3 py-2 text-xs text-ink">
            Χωρίς φωτογραφία η καταχώριση απορρίπτεται από τον έλεγχο ακεραιότητας της
            βάσης (check constraint <span className="font-mono">hwn_photos_chk</span>).
          </p>
        ) : (
          <p className="mt-3 text-xs text-ink3">
            {photos.length === 1
              ? 'Μία φωτογραφία στον φάκελο της δήλωσης.'
              : `${photos.length} φωτογραφίες στον φάκελο της δήλωσης.`}
          </p>
        )}
      </Modal>
    </div>
  )
}
