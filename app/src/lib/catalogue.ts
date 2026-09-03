import raw from '../data/workflow.json'
import type { WorkflowStage, StageTask, StageDocument, LegalRef } from './types'

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

export function stageTitle(code: string): string {
  return STAGES_BY_CODE.get(code)?.title ?? code
}

export function legalTitle(id: string | null | undefined): string | null {
  if (!id) return null
  return LEGAL_BY_ID.get(id)?.title ?? null
}
