/**
 * Παραγωγή & προεπισκόπηση εγγράφου από πρότυπο της Υπηρεσίας.
 *
 * Ροή: προεπισκόπηση (dry-run, χωρίς πρωτόκολλο) → έλεγχος τυχόν κενών
 * υποχρεωτικών πεδίων → οριστική παραγωγή, που αποδίδει αριθμό
 * πρωτοκόλλου και καταχωρίζει το έγγραφο στον φάκελο του έργου.
 */
import { useCallback, useEffect, useState } from 'react'
import * as api from '@/lib/api'
import { TEMPLATE_BY_CODE } from '@/lib/docgen'
import { Badge, Button, LegalRef, Modal, Spinner } from './ui'

export interface GenerateTarget {
  projectId: string
  docCode: string
  entityId?: string | null
  projectStageId?: string | null
}

export function hasTemplate(docCode: string): boolean {
  return docCode in TEMPLATE_BY_CODE
}

/** Κουμπί που ανοίγει τον διάλογο παραγωγής, μόνο αν υπάρχει πρότυπο. */
export function GenerateButton({
  target, label = 'Παραγωγή', onDone,
}: {
  target: GenerateTarget
  label?: string
  onDone?: () => void
}) {
  const [open, setOpen] = useState(false)
  if (!hasTemplate(target.docCode)) return null
  return (
    <>
      <Button variant="secondary" className="px-2 py-1 text-xs" onClick={() => setOpen(true)}>
        {label}
      </Button>
      {open && (
        <DocumentGenerator
          target={target}
          onClose={() => { setOpen(false); onDone?.() }}
        />
      )}
    </>
  )
}

export function DocumentGenerator({
  target, onClose,
}: {
  target: GenerateTarget
  onClose: () => void
}) {
  const tpl = TEMPLATE_BY_CODE[target.docCode]
  const [doc, setDoc] = useState<api.GeneratedDocument | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(true)
  const [saved, setSaved] = useState(false)

  const preview = useCallback(async () => {
    setBusy(true)
    setError(null)
    try {
      setDoc(await api.generateDocument({ ...target, dryRun: true }))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }, [target.projectId, target.docCode, target.entityId])

  useEffect(() => { void preview() }, [preview])

  async function finalise() {
    setBusy(true)
    setError(null)
    try {
      const res = await api.generateDocument({ ...target, dryRun: false })
      setDoc(d => ({ ...(d as api.GeneratedDocument), ...res, html: res.html || d?.html || '' }))
      setSaved(true)
      if (res.downloadUrl) window.open(res.downloadUrl, '_blank', 'noopener')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  function printDoc() {
    if (!doc?.html) return
    const w = window.open('', '_blank', 'noopener,width=900,height=1000')
    if (!w) return
    w.document.write(doc.html)
    w.document.close()
    w.focus()
    setTimeout(() => w.print(), 400)
  }

  return (
    <Modal
      open
      wide
      onClose={onClose}
      title={tpl?.title ?? target.docCode}
      footer={
        <>
          <div className="mr-auto flex items-center gap-2 text-xs text-ink3">
            {tpl && <LegalRef id={tpl.legal_ref_id} />}
            {saved && <Badge tone="accent">καταχωρίστηκε</Badge>}
          </div>
          <Button onClick={printDoc} disabled={!doc?.html || busy}>Εκτύπωση / PDF</Button>
          <Button variant="primary" onClick={finalise} disabled={busy || saved}>
            {saved ? 'Ολοκληρώθηκε' : 'Οριστική παραγωγή'}
          </Button>
          <Button variant="ghost" onClick={onClose}>Κλείσιμο</Button>
        </>
      }
    >
      {busy && <Spinner label="Σύνθεση εγγράφου…" />}

      {error && (
        <div className="rounded border border-oxide bg-oxide-soft px-3 py-2 text-sm text-oxide">
          {error}
        </div>
      )}

      {!busy && doc && (
        <div className="space-y-3">
          {doc.missing.length > 0 && (
            <div className="rounded border border-brass bg-brass-soft px-3 py-2 text-sm">
              <b>Ελλιπή στοιχεία.</b> Δεν έχουν συμπληρωθεί τα εξής υποχρεωτικά πεδία, τα
              οποία εμφανίζονται ως «—» στο έγγραφο:
              <ul className="mt-1 list-disc pl-5 font-mono text-xs">
                {doc.missing.map(m => (
                  <li key={m}>{tpl?.fields[`{{${m}}}`]?.label ?? m}</li>
                ))}
              </ul>
            </div>
          )}

          {doc.protocolNo && (
            <p className="text-sm">
              Αριθμός πρωτοκόλλου: <b className="font-mono">{doc.protocolNo}</b>
            </p>
          )}

          <iframe
            title="Προεπισκόπηση εγγράφου"
            srcDoc={doc.html}
            className="h-[60vh] w-full rounded border border-rule2 bg-white"
          />
        </div>
      )}
    </Modal>
  )
}
