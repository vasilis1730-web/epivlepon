import raw from '../data/workflow.json'
import type { WorkflowStage, StageTask, StageDocument, LegalRef } from './types'
import { addDays, addMonths } from './format'

/**
 * Ο κατάλογος της πρότυπης ροής. Είναι τα ίδια δεδομένα με τους πίνακες
 * workflow_stages / stage_tasks / stage_documents / legal_refs της βάσης
 * (migrations 0013-0014), ενσωματωμένα ώστε το UI να αποδίδει άμεσα και
 * να λειτουργεί και εκτός σύνδεσης.
 */
interface Catalogue {
  stages: WorkflowStage[]
  tasks: StageTask[]
  documents: StageDocument[]
  legal: LegalRef[]
  workGroups: { category: string; code: string; title: string }[]
}

export const catalogue = raw as unknown as Catalogue

export const STAGES = catalogue.stages
export const STAGES_BY_CODE = new Map(STAGES.map(s => [s.code, s]))

export const TASKS_BY_STAGE = catalogue.tasks.reduce<Record<string, StageTask[]>>((acc, t) => {
  ;(acc[t.stage_code] ??= []).push(t)
  return acc
}, {})

export const DOCS_BY_STAGE = catalogue.documents.reduce<Record<string, StageDocument[]>>((acc, d) => {
  ;(acc[d.stage_code] ??= []).push(d)
  return acc
}, {})

export const LEGAL_BY_ID = new Map(catalogue.legal.map(l => [l.id, l]))

export const WORK_GROUPS = catalogue.workGroups

/**
 * Προθεσμία σταδίου — αντίστοιχο της app.compute_stage_due().
 *
 * Υπολογίζεται ΜΟΝΟ όταν υπάρχει η αφετηρία που ορίζει ο νόμος. Τα στάδια
 * που μετρούν από υποβολή εγγράφου ή κοινοποίηση πράξης δεν αποκτούν
 * ημερομηνία στο στάδιο: η προθεσμία τους τηρείται στην κάθε εγγραφή
 * χωριστά. Πλασματική ημερομηνία δεν παράγεται ποτέ — ένας ψευδής
 * συναγερμός κοστίζει περισσότερο από την απουσία του.
 */
export function computeStageDue(
  stage: WorkflowStage,
  anchors: {
    signedAt: string
    worksStartDeadline?: string | null
    currentEndDate?: string | null
    certificateIssuedAt?: string | null
    maintenanceEndsOn?: string | null
  },
): string | null {
  if (stage.deadline_days == null && stage.deadline_months == null) return null

  let base: string | null | undefined
  switch (stage.deadline_basis) {
    case 'ypografi_symvasis':  base = anchors.signedAt; break
    case 'enarxi_ergasion':    base = anchors.worksStartDeadline; break
    case 'lixi_prothesmias':   base = anchors.currentEndDate; break
    case 'bebaiosi_peratosis': base = anchors.certificateIssuedAt; break
    case 'lixi_syntirisis':    base = anchors.maintenanceEndsOn; break
    default:                   base = null
  }
  if (!base) return null

  let d = base
  if (stage.deadline_months != null) d = addMonths(d, stage.deadline_months)
  if (stage.deadline_days != null) d = addDays(d, stage.deadline_days)
  return d
}

export function stageTitle(code: string): string {
  return STAGES_BY_CODE.get(code)?.title ?? code
}

export function legalTitle(id: string | null | undefined): string | null {
  if (!id) return null
  return LEGAL_BY_ID.get(id)?.title ?? null
}
