/**
 * Τοπική μνήμη κατάστασης για τη λειτουργία επίδειξης.
 * Κρατά τα δεδομένα, ενημερώνει τους συνδρομητές και αναπαράγει τους
 * κανόνες της βάσης (fail-safe) ώστε η επίδειξη να συμπεριφέρεται όπως
 * το πραγματικό σύστημα.
 */
import {
  DEMO_ACCEPTANCE, DEMO_APES, DEMO_COMPLETED_STAGES, DEMO_COMPLETIONS, DEMO_CONTRACTS,
  DEMO_DIARY, DEMO_DOCUMENTS, DEMO_FINAL_MEASUREMENTS, DEMO_GUARANTEES, DEMO_HIDDEN,
  DEMO_INPROGRESS_STAGES, DEMO_MEASUREMENTS, DEMO_NA_STAGES, DEMO_PAYMENTS,
  DEMO_PROJECTS, DEMO_SCHEDULES,
} from './demoData'
import { computeStageDue, DOCS_BY_STAGE, STAGES, TASKS_BY_STAGE } from './catalogue'
import type {
  Ape, ApeLine, Blocker, BudgetItem, BudgetItemDraft, BudgetVersion, Completion,
  Contract, DiaryEntry, DocumentRow, FinalMeasurement, Guarantee, HiddenWorkNotice,
  Measurement, NewApeInput, NewPaymentInput, PaymentCertificate, Project,
  ProjectStage, ProjectStageTask, StageStatus,
} from './types'
import { addDays, addMonths, daysUntil, today } from './format'
import {
  apeTotals, apeViolations, guardBlockers, guaranteeReduction70Blockers,
  guaranteeReleaseBlockers, missingDiaryDays, paymentTotals, type GuardContext,
} from './rules'
import { derive, type NewProjectInput } from './newProject'

export interface DemoState {
  projects: Project[]
  contracts: Record<string, Contract>
  stages: ProjectStage[]
  stageTasks: ProjectStageTask[]
  diary: Record<string, DiaryEntry[]>
  hidden: HiddenWorkNotice[]
  measurements: Measurement[]
  payments: PaymentCertificate[]
  apes: Ape[]
  guarantees: Guarantee[]
  completions: Record<string, Completion>
  finalMeasurements: Record<string, FinalMeasurement>
  acceptance: typeof DEMO_ACCEPTANCE
  schedules: typeof DEMO_SCHEDULES
  documents: DocumentRow[]
  budgetVersions: BudgetVersion[]
  budgetItems: BudgetItem[]
}

let version = 0
const listeners = new Set<() => void>()

function notify() {
  version++
  listeners.forEach(l => l())
}

export function subscribe(l: () => void) {
  listeners.add(l)
  return () => listeners.delete(l)
}

export const getVersion = () => version

/* ------------------------------------------------------------------ */
/* Αρχικοποίηση                                                        */
/* ------------------------------------------------------------------ */
function buildStages(): { stages: ProjectStage[]; tasks: ProjectStageTask[] } {
  const stages: ProjectStage[] = []
  const tasks: ProjectStageTask[] = []

  for (const p of DEMO_PROJECTS) {
    const contract = DEMO_CONTRACTS[p.id]
    const done = new Set(DEMO_COMPLETED_STAGES[p.id] ?? [])
    const running = new Set(DEMO_INPROGRESS_STAGES[p.id] ?? [])
    const na = new Set(DEMO_NA_STAGES[p.id] ?? [])

    for (const s of STAGES) {
      // Στάδια υπό αίρεση: εξαιρούνται αν δεν συντρέχει η προϋπόθεση
      if (s.code === 'S01B_IFE' && contract.supervision_mode !== 'ife') continue
      if (s.code === 'S12_HMEROLOGIO' && contract.diary_mode !== 'imerisio') continue

      const id = `${p.id}:${s.code}`
      let status: StageStatus = 'locked'
      if (done.has(s.code)) status = 'completed'
      else if (na.has(s.code)) status = 'not_applicable'
      else if (running.has(s.code)) status = 'in_progress'

      const completion = DEMO_COMPLETIONS[p.id]
      const due = computeStageDue(s, {
        signedAt: contract.signed_at,
        worksStartDeadline: contract.works_start_deadline,
        currentEndDate: contract.current_end_date,
        certificateIssuedAt: completion?.certificate_issued_at ?? null,
        maintenanceEndsOn: completion?.certificate_issued_at
          ? addMonths(completion.certificate_issued_at, contract.maintenance_months)
          : null,
      })

      stages.push({
        id, project_id: p.id, stage_code: s.code, cycle_no: 1, status,
        due_date: due, completed_at: status === 'completed' ? addDays(today(), -30) : null,
        override_reason: null,
        na_reason: status === 'not_applicable'
          ? 'Δεν συντρέχει περίπτωση εφαρμογής για τη συγκεκριμένη σύμβαση.' : null,
        hard_blockers: 0, soft_blockers: 0, tasks_total: 0, tasks_done: 0,
      })

      for (const t of TASKS_BY_STAGE[s.code] ?? []) {
        tasks.push({
          id: `${id}:${t.id}`, project_stage_id: id, stage_task_id: t.id,
          is_done: status === 'completed',
          done_at: status === 'completed' ? addDays(today(), -30) : null,
          waived: false, waive_reason: null, evidence_doc_id: null,
        })
      }
    }
  }
  return { stages, tasks }
}

const built = buildStages()

export const state: DemoState = {
  projects: DEMO_PROJECTS,
  contracts: DEMO_CONTRACTS,
  stages: built.stages,
  stageTasks: built.tasks,
  diary: DEMO_DIARY,
  hidden: DEMO_HIDDEN,
  measurements: DEMO_MEASUREMENTS,
  payments: DEMO_PAYMENTS,
  apes: DEMO_APES,
  guarantees: DEMO_GUARANTEES,
  completions: DEMO_COMPLETIONS,
  finalMeasurements: DEMO_FINAL_MEASUREMENTS,
  acceptance: DEMO_ACCEPTANCE,
  schedules: DEMO_SCHEDULES,
  documents: DEMO_DOCUMENTS,
  budgetVersions: [],
  budgetItems: [],
}

/* ------------------------------------------------------------------ */
/* Υπολογισμός εμποδίων (αντιστοιχεί στην app.stage_blockers)          */
/* ------------------------------------------------------------------ */
export function buildGuardContext(projectId: string): GuardContext {
  const contract = state.contracts[projectId]
  const diary = state.diary[projectId] ?? []
  const sched = state.schedules[projectId]
  const hidden = state.hidden.filter(h => h.project_id === projectId)
  const meas = state.measurements.filter(m => m.project_id === projectId && m.mtype === 'tmimatiki')
  const acc = state.acceptance[projectId]
  const g = state.guarantees.filter(x => x.project_id === projectId)
  const startIso =
    contract.works_start_deadline && contract.works_start_deadline < today()
      ? contract.works_start_deadline
      : contract.signed_at

  return {
    contract,
    guarantees: g,
    scheduleSubmittedAt: sched?.submitted_at ?? null,
    scheduleApprovedAt: sched?.approved_at ?? null,
    scheduleDeemedApproved: sched?.deemed_approved ?? false,
    scheduleMethod: sched?.method ?? null,
    diaryMissingDays: diary.length ? missingDiaryDays(diary, startIso).length : 0,
    diaryUnreviewed: diary.filter(d => d.status === 'submitted' && (daysUntil(d.entry_date) ?? 0) < -2).length,
    hiddenOverdue: hidden.filter(h => !h.inspected_at && (daysUntil(h.inspection_due) ?? 0) < 0).length,
    hiddenCoveredUnchecked: hidden.filter(h => h.covered_at && !h.inspected_at).length,
    measurementsSubmitted: meas.filter(m => m.submitted_at).length,
    measurementsAudited: meas.filter(m => m.audited).length,
    apes: state.apes.filter(a => a.project_id === projectId),
    completion: state.completions[projectId],
    finalMeasurement: state.finalMeasurements[projectId],
    acceptanceApproved: Boolean(acc?.approved_at),
    acceptanceCommitteeSize: acc?.committee_size ?? 0,
    guaranteeReduced70: g.some(x => x.events.some(e => e.event_type === 'meiosi_70')),
    openDefects: 0,
  }
}

export function stageBlockers(stageId: string): Blocker[] {
  const ps = state.stages.find(s => s.id === stageId)
  if (!ps) return []
  // Ένα στάδιο που έχει ήδη κλείσει δεν έχει «εμπόδια»: η πύλη έχει περαστεί.
  if (['completed', 'overdue', 'not_applicable'].includes(ps.status)) return []
  const def = STAGES.find(s => s.code === ps.stage_code)!
  const out: Blocker[] = []

  // (α) Προαπαιτούμενα στάδια
  for (const req of def.prerequisites ?? []) {
    const other = state.stages.find(s => s.project_id === ps.project_id && s.stage_code === req)
    if (!other) continue
    if (!['completed', 'not_applicable'].includes(other.status)) {
      const reqDef = STAGES.find(s => s.code === req)
      out.push({
        code: `PREREQ_${req}`, severity: 'hard',
        legal_ref: reqDef?.legal_ref_id ?? '',
        message: `Εκκρεμεί το προαπαιτούμενο στάδιο «${reqDef?.title ?? req}».`,
      })
    }
  }

  // (β) Υποχρεωτικές ενέργειες
  for (const t of TASKS_BY_STAGE[ps.stage_code] ?? []) {
    if (!t.is_mandatory) continue
    const inst = state.stageTasks.find(x => x.project_stage_id === ps.id && x.stage_task_id === t.id)
    if (inst && !inst.is_done && !inst.waived) {
      out.push({
        code: `TASK_${t.id}`, severity: 'hard', legal_ref: t.legal_ref_id ?? '',
        message: `Εκκρεμής υποχρεωτική ενέργεια (${PARTY_SHORT[t.party] ?? t.party}): ${t.title}`,
      })
    }
  }

  // (γ) Υποχρεωτικά έγγραφα
  for (const d of DOCS_BY_STAGE[ps.stage_code] ?? []) {
    if (!d.is_mandatory) continue
    const exists = state.documents.some(
      x => x.project_id === ps.project_id && x.doc_code === d.doc_code &&
           ['approved', 'signed', 'communicated', 'deemed_approved'].includes(x.status),
    )
    if (!exists) {
      out.push({
        code: `DOC_${d.doc_code}`, severity: 'hard', legal_ref: d.legal_ref_id ?? '',
        message: `Λείπει το υποχρεωτικό έγγραφο: ${d.title}.`,
      })
    }
  }

  // (δ) Ειδικός νομικός κανόνας του σταδίου
  out.push(...guardBlockers(def.guard_fn, buildGuardContext(ps.project_id)))

  return out
}

const PARTY_SHORT: Record<string, string> = {
  anadochos: 'Ανάδοχος', epivlepon: 'Επιβλέπων',
  dieuthynousa_ypiresia: 'Διευθύνουσα Υπηρεσία', proistameni_arxi: 'Προϊσταμένη Αρχή',
  techniko_symvoulio: 'Τεχνικό Συμβούλιο', epitropi: 'Επιτροπή',
  ife: 'Ιδιωτικός Φορέας Επίβλεψης', kyrios_ergou: 'Κύριος του Έργου',
}

/** Ξεκλειδώνει τα στάδια των οποίων ικανοποιούνται τα προαπαιτούμενα. */
export function recomputeAvailability(projectId: string) {
  for (const ps of state.stages.filter(s => s.project_id === projectId)) {
    if (!['locked', 'available'].includes(ps.status)) continue
    const hardPrereq = stageBlockers(ps.id).filter(
      b => b.severity === 'hard' && b.code.startsWith('PREREQ'),
    ).length
    ps.status = hardPrereq === 0 ? 'available' : 'locked'
  }
}

for (const p of state.projects) recomputeAvailability(p.id)

/* ------------------------------------------------------------------ */
/* Ενέργειες                                                           */
/* ------------------------------------------------------------------ */
export class RuleViolation extends Error {
  constructor(public blockers: Blocker[]) {
    super('Η ενέργεια απορρίφθηκε από τους κανόνες ελέγχου.')
    this.name = 'RuleViolation'
  }
}

export function setTaskDone(taskInstanceId: string, done: boolean) {
  const t = state.stageTasks.find(x => x.id === taskInstanceId)
  if (!t) return
  t.is_done = done
  t.done_at = done ? new Date().toISOString() : null
  notify()
}

export function completeStage(stageId: string, override?: { reason: string }) {
  const ps = state.stages.find(s => s.id === stageId)
  if (!ps) return
  const hard = stageBlockers(stageId).filter(b => b.severity === 'hard')
  if (hard.length > 0 && !override) throw new RuleViolation(hard)

  ps.status = ps.due_date && (daysUntil(ps.due_date) ?? 0) < 0 ? 'overdue' : 'completed'
  ps.completed_at = new Date().toISOString()
  if (override) ps.override_reason = override.reason
  recomputeAvailability(ps.project_id)
  notify()
}

export function startStage(stageId: string) {
  const ps = state.stages.find(s => s.id === stageId)
  if (!ps) return
  const hard = stageBlockers(stageId).filter(b => b.severity === 'hard' && b.code.startsWith('PREREQ'))
  if (hard.length > 0) throw new RuleViolation(hard)
  ps.status = 'in_progress'
  notify()
}

export function markNotApplicable(stageId: string, reason: string) {
  const ps = state.stages.find(s => s.id === stageId)
  if (!ps) return
  ps.status = 'not_applicable'
  ps.na_reason = reason
  recomputeAvailability(ps.project_id)
  notify()
}

export function inspectHiddenWork(id: string, photos: number) {
  const h = state.hidden.find(x => x.id === id)
  if (!h) return
  if (photos <= 0) {
    throw new RuleViolation([{
      code: 'HW_NO_PHOTOS', severity: 'hard', legal_ref: 'N4412/151/7',
      message: 'Δεν επιτρέπεται καταχώριση ελέγχου αφανών εργασιών χωρίς ψηφιακές φωτογραφίες (εντάσσονται στο Μητρώο του Έργου).',
    }])
  }
  h.inspected_at = today()
  h.supervisor_report_at = today()
  h.photos_count = photos
  h.approval_due = addDays(today(), 30)
  h.status = 'reported'
  notify()
}

export function approveHiddenWork(id: string) {
  const h = state.hidden.find(x => x.id === id)
  if (!h) return
  h.approved_at = today()
  h.status = 'approved'
  notify()
}

export function auditMeasurement(id: string) {
  const m = state.measurements.find(x => x.id === id)
  if (!m) return
  m.audited = true
  m.selected_for_audit = true
  notify()
}

export function approveMeasurement(id: string) {
  const m = state.measurements.find(x => x.id === id)
  if (!m) return
  m.status = 'approved'
  m.approved_at = today()
  notify()
}

export function approvePayment(id: string) {
  const p = state.payments.find(x => x.id === id)
  if (!p) return
  p.status = 'approved'
  p.approved_at = today()
  notify()
}

export function approveApe(id: string) {
  const a = state.apes.find(x => x.id === id)
  if (!a) return
  const contract = state.contracts[a.project_id]
  const others = state.apes.filter(x => x.project_id === a.project_id && x.status === 'approved')
  // Ο έλεγχος γίνεται με τους ίδιους κανόνες που επιβάλλει η βάση
  const hard = apeViolations(a, contract, others).filter(b => b.severity === 'hard')
  if (hard.length) throw new RuleViolation(hard)
  a.status = 'approved'
  a.approved_at = today()
  notify()
}

export function attachTcOpinion(apeId: string) {
  const a = state.apes.find(x => x.id === apeId)
  if (!a) return
  a.tc_opinion_id = `tc-${Date.now()}`
  notify()
}

export function signApe(apeId: string, kind: 'anepifylakta' | 'me_epifylaxi' | 'arnisi') {
  const a = state.apes.find(x => x.id === apeId)
  if (!a) return
  a.contractor_signature = kind
  a.status = kind === 'arnisi' ? 'not_signed'
    : kind === 'me_epifylaxi' ? 'signed_me_epifylaxi' : 'signed_anepifylakta'
  notify()
}

export function reduceGuarantee70(guaranteeId: string) {
  const g = state.guarantees.find(x => x.id === guaranteeId)
  if (!g) return
  const fm = state.finalMeasurements[g.project_id]
  const blockers = guaranteeReduction70Blockers(fm)
  if (blockers.length) throw new RuleViolation(blockers)

  const after = Math.round(g.current_amount * 0.3 * 100) / 100
  g.events.push({
    id: `ge-${Date.now()}`, event_type: 'meiosi_70',
    amount_before: g.current_amount, amount_after: after,
    trigger_event: 'egkrisi_telikis_epimetrisis', decision_date: today(),
  })
  g.current_amount = after
  g.status = 'meiomeni_70'
  notify()
}

export function releaseGuarantee(guaranteeId: string) {
  const g = state.guarantees.find(x => x.id === guaranteeId)
  if (!g) return
  const acc = state.acceptance[g.project_id]
  const finalPaid = state.payments.some(
    p => p.project_id === g.project_id && p.ptype === 'telikos' &&
         ['approved', 'deemed_approved', 'paid'].includes(p.status),
  )
  const blockers = guaranteeReleaseBlockers({
    acceptanceApproved: Boolean(acc?.approved_at),
    finalPaymentApproved: finalPaid,
  })
  if (blockers.length) throw new RuleViolation(blockers)

  g.events.push({
    id: `ge-${Date.now()}`, event_type: 'apodesmevsi',
    amount_before: g.current_amount, amount_after: 0,
    trigger_event: 'egkrisi_paralavis_kai_telikou_logariasmou', decision_date: today(),
  })
  g.current_amount = 0
  g.status = 'apodesmevmeni'
  notify()
}

/* ------------------------------------------------------------------ */
/* Προϋπολογισμός μελέτης                                              */
/* ------------------------------------------------------------------ */
export function getBudget(projectId: string) {
  const version = state.budgetVersions.find(
    v => v.project_id === projectId && v.version_no === 0)
  if (!version) return undefined
  return {
    version,
    items: state.budgetItems.filter(i => i.version_id === version.id)
      .sort((a, b) => a.line_no - b.line_no),
  }
}

export function saveBudget(projectId: string, lines: BudgetItemDraft[]) {
  const totalNet =
    Math.round(lines.reduce((s, l) => s + l.unit_price * l.quantity, 0) * 100) / 100

  let version = state.budgetVersions.find(
    v => v.project_id === projectId && v.version_no === 0)

  if (version) {
    const v = version
    state.budgetVersions = state.budgetVersions.map(
      x => (x.id === v.id ? { ...x, total_net: totalNet } : x))
    state.budgetItems = state.budgetItems.filter(i => i.version_id !== v.id)
  } else {
    version = {
      id: `bv-${Date.now().toString(36)}`,
      project_id: projectId, version_no: 0, label: 'Αρχική Σύμβαση',
      is_current: true, ape_id: null, approved_at: null,
      total_net: totalNet, created_at: today(),
    }
    state.budgetVersions = [...state.budgetVersions, version]
  }

  const vid = version.id
  state.budgetItems = [
    ...state.budgetItems,
    ...lines.map((l, i) => ({
      id: `bi-${Date.now().toString(36)}-${i}`,
      version_id: vid,
      line_no: l.line_no,
      item_code: l.item_code,
      description: l.description,
      unit: l.unit,
      work_group: l.work_group,
      unit_price: l.unit_price,
      quantity: l.quantity,
      amount: Math.round(l.unit_price * l.quantity * 100) / 100,
      is_new_price: false,
      is_apologistiki: false,
    })),
  ]
  notify()
  return { versionId: vid, itemCount: lines.length, totalNet }
}

/* ------------------------------------------------------------------ */
/* Σύνταξη ΑΠΕ (άρθρο 156 §2)                                          */
/* ------------------------------------------------------------------ */
export function createApe(input: NewApeInput) {
  const contract = state.contracts[input.project_id]
  if (!contract) throw new Error('Δεν βρέθηκε σύμβαση για το έργο.')

  const serialNo = state.apes
    .filter(a => a.project_id === input.project_id)
    .reduce((m, a) => Math.max(m, a.serial_no), 0) + 1

  const t = apeTotals(input.lines, contract.initial_value_net)
  const id = `ape-${Date.now().toString(36)}`

  const lines: ApeLine[] = input.lines.map((l, i) => ({
    id: `${id}-l${i}`,
    work_group: l.work_group,
    item_code: l.item_code,
    description: l.description,
    unit: l.unit,
    unit_price: l.unit_price,
    qty_initial: l.qty_initial,
    qty_new: l.qty_new,
    amount_initial: Math.round(l.qty_initial * l.unit_price * 100) / 100,
    amount_new: Math.round(l.qty_new * l.unit_price * 100) / 100,
    delta_amount: Math.round((l.qty_new - l.qty_initial) * l.unit_price * 100) / 100,
    funding_source: l.funding_source,
    is_new_item: l.is_new_item,
  }))

  state.apes = [...state.apes, {
    id,
    project_id: input.project_id,
    serial_no: serialNo,
    atype: input.atype,
    reason: input.reason,
    drafted_at: input.drafted_at,
    initial_contract_value: contract.initial_value_net,
    new_total_value: t.newTotal,
    delta_amount: t.delta,
    contingency_used: t.contingencyUsed,
    savings_used: t.savings,
    supplementary_needed: input.supplementary_needed,
    tc_opinion_id: null,
    contractor_signature: null,
    status: 'draft',
    approved_at: null,
    lines,
  }]
  notify()
  return { apeId: id, serialNo }
}

/* ------------------------------------------------------------------ */
/* Σύνταξη λογαριασμού (άρθρο 152)                                     */
/* ------------------------------------------------------------------ */
export function createPayment(input: NewPaymentInput) {
  const prior = state.payments.filter(p => p.project_id === input.project_id)
  const serialNo = prior
    .filter(p => p.ptype === input.ptype)
    .reduce((m, p) => Math.max(m, p.serial_no), 0) + 1

  const t = paymentTotals(input, prior)
  const id = `pc-${Date.now().toString(36)}`

  state.payments = [...state.payments, {
    id,
    project_id: input.project_id,
    ptype: input.ptype,
    serial_no: serialNo,
    period_from: input.period_from,
    period_to: input.period_to,
    measurement_id: input.measurement_id,
    submitted_at: input.submitted_at,
    // Άρθρο 152: έγκριση εντός ενός μηνός από την υποβολή.
    approval_due: addMonths(input.submitted_at, 1),
    approved_at: null,
    status: 'submitted',
    gross_cumulative: t.gross,
    previous_certified: t.previousCertified,
    period_amount: t.period,
    advance_amortization: input.advance_amortization,
    penalties_amount: input.penalties_amount,
    retentions_amount: t.retentions,
    net_payable: t.net,
    vat_amount: t.vat,
    has_summary_table: input.has_summary_table,
    has_revision_calc: input.has_revision_calc,
    paid_at: null,
  }]
  notify()
  return { paymentId: id, serialNo }
}

export function addDiaryEntry(entry: DiaryEntry) {
  ;(state.diary[entry.project_id] ??= []).push(entry)
  state.diary[entry.project_id].sort((a, b) => b.entry_date.localeCompare(a.entry_date))
  notify()
}

export function reviewDiaryEntry(projectId: string, entryId: string) {
  const e = (state.diary[projectId] ?? []).find(x => x.id === entryId)
  if (!e) return
  e.status = 'reviewed'
  e.reviewed_at = new Date().toISOString()
  notify()
}

/** Καταχώριση παραχθέντος εγγράφου στον φάκελο του έργου (επίδειξη). */
export function addDocument(projectId: string, docCode: string, title: string): DocumentRow {
  const year = new Date().getFullYear()
  const row: DocumentRow = {
    id: `doc-${Date.now()}`,
    project_id: projectId,
    doc_code: docCode,
    title,
    protocol_no: `${year}/${1000 + state.documents.length + 1}`,
    protocol_date: today(),
    ada: null,
    status: 'draft',
    created_at: new Date().toISOString(),
  }
  state.documents = [row, ...state.documents]
  notify()
  return row
}

/* ------------------------------------------------------------------ */
/* Νέο έργο (επίδειξη)                                                 */
/* ------------------------------------------------------------------ */
/**
 * Αντίγραφο της public.create_project_full() για τη λειτουργία επίδειξης:
 * δημιουργεί έργο, σύμβαση, εγγύηση και ολόκληρη τη ροή των σταδίων με
 * τους ίδιους υπολογισμούς και τις ίδιες προθεσμίες που εφαρμόζει η βάση.
 */
export function createProject(input: NewProjectInput): { projectId: string; stages: number } {
  const d = derive(input.contract)
  const code = input.project.code.trim()

  if (state.projects.some(p => p.code === code)) {
    throw new Error(`Υπάρχει ήδη έργο με κωδικό «${code}».`)
  }

  const id = `p-${Date.now().toString(36)}`

  const project: Project = {
    id, code,
    title: input.project.title.trim(),
    category: input.project.category,
    location: input.project.location.trim() || null,
    funding_source: input.project.funding_source.trim() || null,
    study_budget_net: d.studyBudgetNet,
    estimated_value_net: d.studyBudgetNet,
  }

  const c = input.contract
  const contract: Contract = {
    project_id: id,
    contractor_name: input.contractor.name.trim(),
    contractor_afm: input.contractor.afm.trim(),
    contract_no: c.contract_no.trim(),
    signed_at: c.signed_at,
    discount_pct: c.discount_pct,
    initial_value_net: d.initialValueNet,
    contingency_pct: c.contingency_pct,
    contingency_amount: d.contingency,
    vat_rate: c.vat_rate,
    total_duration_days: c.total_duration_days,
    original_end_date: d.originalEndDate!,
    current_end_date: d.originalEndDate!,
    works_start_deadline: d.worksStartDue,
    maintenance_months: c.maintenance_months,
    supervision_mode: c.supervision_mode,
    diary_mode: c.diary_mode,
    diary_penalty_per_day: c.diary_penalty_per_day,
    status: 'active',
  }

  // Ροή σταδίων — ίδιοι κανόνες εφαρμογής με την app.stage_applies()
  const stages: ProjectStage[] = []
  const tasks: ProjectStageTask[] = []
  for (const s of STAGES) {
    if (s.code === 'S01B_IFE' && c.supervision_mode !== 'ife') continue
    if (s.code === 'S12_HMEROLOGIO' && c.diary_mode !== 'imerisio') continue

    const sid = `${id}:${s.code}`
    // Νέο έργο: υπάρχουν μόνο οι αφετηρίες της σύμβασης. Τα στάδια που
    // μετρούν από μεταγενέστερο γεγονός μένουν χωρίς προθεσμία.
    const due = computeStageDue(s, {
      signedAt: c.signed_at,
      worksStartDeadline: d.worksStartDue,
      currentEndDate: d.originalEndDate,
    })

    stages.push({
      id: sid, project_id: id, stage_code: s.code, cycle_no: 1,
      status: 'locked', due_date: due, completed_at: null,
      override_reason: null, na_reason: null,
      hard_blockers: 0, soft_blockers: 0, tasks_total: 0, tasks_done: 0,
    })
    for (const t of TASKS_BY_STAGE[s.code] ?? []) {
      tasks.push({
        id: `${sid}:${t.id}`, project_stage_id: sid, stage_task_id: t.id,
        is_done: false, done_at: null, waived: false, waive_reason: null, evidence_doc_id: null,
      })
    }
  }

  state.projects = [...state.projects, project]
  state.contracts[id] = contract
  state.stages = [...state.stages, ...stages]
  state.stageTasks = [...state.stageTasks, ...tasks]
  state.diary[id] = []

  const g = input.guarantee
  if (g.guarantee_no.trim() && g.original_amount > 0) {
    state.guarantees = [...state.guarantees, {
      id: `g-${Date.now().toString(36)}`,
      project_id: id, gtype: 'kalis_ektelesis',
      issuer: g.issuer.trim(), guarantee_no: g.guarantee_no.trim(),
      issued_at: g.issued_at || c.signed_at,
      valid_to: g.valid_to || null,
      original_amount: g.original_amount, current_amount: g.original_amount,
      pct_of_contract: d.initialValueNet
        ? Math.round((g.original_amount / d.initialValueNet) * 100_000) / 1000 : null,
      status: 'energi', events: [],
    } as Guarantee]
  }

  // Ξεκλείδωμα των σταδίων χωρίς προαπαιτούμενα (app.recompute_availability)
  recomputeAvailability(id)
  notify()
  return { projectId: id, stages: stages.length }
}
