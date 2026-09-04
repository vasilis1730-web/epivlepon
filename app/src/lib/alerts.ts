/**
 * Ειδοποιήσεις — τι πρέπει να γίνει σήμερα, σε όλα τα έργα του χρήστη.
 *
 * ΔΕΝ είναι μηνύματα: δεν αποθηκεύονται, δεν σημειώνονται «διαβασμένα» και
 * δεν σβήνονται. Παράγονται κάθε φορά από την κατάσταση των έργων, γιατί μια
 * εκπρόθεσμη προθεσμία δεν παύει να είναι εκπρόθεσμη επειδή την είδε κάποιος.
 * Η μόνη διαγραφή είναι η τακτοποίηση της ίδιας της εκκρεμότητας.
 *
 * Πηγές, κατά σειρά βαρύτητας:
 *   1. Προθεσμίες με ΣΙΩΠΗΡΗ ΕΓΚΡΙΣΗ (145 §2, 147 §5, 151 §7, 152) — η σιωπή
 *      παράγει έννομο αποτέλεσμα, οπότε δεν «περιμένουν».
 *   2. Παραβάσεις ορίων ΑΠΕ (άρθρο 156).
 *   3. Αφανείς εργασίες (άρθρο 151 §7).
 *   4. Προθεσμίες σταδίων του οδηγού.
 *   5. Λήξη της συνολικής προθεσμίας του έργου (άρθρο 147).
 */
import * as api from './api'
import { STAGES_BY_CODE } from './catalogue'
import { daysUntil } from './format'
import { apeViolations, hiddenWorkAlert } from './rules'
import type { Alert, AlertLevel } from './types'

/** Εκπρόθεσμο / ≤5 ημέρες / ≤15 ημέρες. Πέραν αυτού δεν είναι ειδοποίηση. */
function levelFor(days: number | null): AlertLevel | null {
  if (days === null) return null
  if (days < 0) return 'overdue'
  if (days <= 5) return 'critical'
  if (days <= 15) return 'warning'
  return null
}

const OPEN = ['available', 'in_progress', 'pending_approval', 'blocked', 'locked']

export async function getAlerts(): Promise<Alert[]> {
  const projects = await api.getProjects()
  const perProject = await Promise.all(projects.map(collect))
  return perProject.flat().sort(byUrgency)
}

const RANK: Record<AlertLevel, number> = { overdue: 0, critical: 1, warning: 2 }

function byUrgency(a: Alert, b: Alert): number {
  if (RANK[a.level] !== RANK[b.level]) return RANK[a.level] - RANK[b.level]
  // Η σιωπηρή έγκριση προηγείται: η αδράνεια εκεί ΠΑΡΑΓΕΙ απόφαση.
  const tacit = (x: Alert) => (x.kind === 'tacit_approval' ? 0 : 1)
  if (tacit(a) !== tacit(b)) return tacit(a) - tacit(b)
  return (a.days_left ?? 0) - (b.days_left ?? 0)
}

async function collect(p: { id: string; code: string; title: string }): Promise<Alert[]> {
  const [contract, stages, hidden, apes] = await Promise.all([
    api.getContract(p.id),
    api.getStages(p.id),
    api.getHiddenWorks(p.id).catch(() => []),
    api.getApes(p.id).catch(() => []),
  ])
  const base = { project_id: p.id, project_code: p.code, project_title: p.title }
  const out: Alert[] = []

  /* 1 & 4. Προθεσμίες σταδίων ------------------------------------- */
  for (const s of stages) {
    if (!OPEN.includes(s.status) || !s.due_date) continue
    const days = daysUntil(s.due_date)
    const level = levelFor(days)
    if (!level) continue
    const def = STAGES_BY_CODE.get(s.stage_code)
    const tacit = Boolean(def?.tacit_approval)
    out.push({
      ...base,
      id: `stage:${s.id}`,
      level,
      kind: tacit ? 'tacit_approval' : 'stage_deadline',
      title: def?.title ?? s.stage_code,
      detail: tacit
        ? `Η άπρακτη πάροδος της προθεσμίας παράγει μόνη της αποτέλεσμα: ${
            def?.tacit_effect ?? 'σιωπηρή έγκριση'}.`
        : def?.purpose ?? '',
      days_left: days,
      due_date: s.due_date,
      legal_ref: def?.legal_ref_id ?? null,
      href: `/erga/${p.id}/odigos`,
    })
  }

  /* 2. Όρια ΑΠΕ ---------------------------------------------------- */
  if (contract) {
    const approved = apes.filter(a => a.status === 'approved')
    for (const ape of apes) {
      if (ape.status === 'approved' || ape.status === 'rejected') continue
      const hard = apeViolations(ape, contract, approved.filter(a => a.id !== ape.id))
        .filter(b => b.severity === 'hard')
      if (!hard.length) continue
      out.push({
        ...base,
        id: `ape:${ape.id}`,
        level: 'overdue',
        kind: 'ape_violation',
        title: `${ape.serial_no}ος ΑΠΕ — ${hard.length === 1 ? 'παράβαση ορίου' : `${hard.length} παραβάσεις ορίων`}`,
        detail: hard.map(b => b.message).join(' '),
        days_left: null,
        due_date: null,
        legal_ref: hard[0].legal_ref,
        href: `/erga/${p.id}/ape`,
      })
    }
  }

  /* 3. Αφανείς εργασίες -------------------------------------------- */
  for (const h of hidden) {
    const a = hiddenWorkAlert(h)
    if (a.level === 'ok') continue
    out.push({
      ...base,
      id: `hidden:${h.id}`,
      level: a.level === 'error' ? 'overdue' : 'critical',
      kind: 'hidden_work',
      title: `Αφανής εργασία ${h.serial_no}: ${h.work_description}`,
      detail: a.text,
      days_left: h.inspected_at ? null : daysUntil(h.inspection_due),
      due_date: h.inspected_at ? h.approval_due : h.inspection_due,
      legal_ref: 'N4412/151/7',
      href: `/erga/${p.id}/afaneis`,
    })
  }

  /* 5. Συνολική προθεσμία του έργου -------------------------------- */
  if (contract?.current_end_date) {
    const days = daysUntil(contract.current_end_date)
    const level = levelFor(days)
    if (level) {
      out.push({
        ...base,
        id: `contract:${p.id}`,
        level,
        kind: 'contract_deadline',
        title: 'Λήξη συνολικής προθεσμίας του έργου',
        detail: (days ?? 0) < 0
          ? 'Το έργο είναι εκπρόθεσμο. Η παράταση ζητείται ΠΡΙΝ τη λήξη (άρθρο 147 §8)· '
            + 'μετά τη λήξη υπολογίζονται ποινικές ρήτρες (άρθρο 148).'
          : 'Αν απαιτείται παράταση, η αίτηση υποβάλλεται πριν από τη λήξη (άρθρο 147 §8).',
        days_left: days,
        due_date: contract.current_end_date,
        legal_ref: 'N4412/147/8',
        href: `/erga/${p.id}/prothesmies`,
      })
    }
  }

  return out
}
