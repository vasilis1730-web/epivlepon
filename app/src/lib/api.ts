/**
 * Ενιαίο επίπεδο πρόσβασης δεδομένων.
 *
 *  • DEMO_MODE  → διαβάζει/γράφει στην τοπική μνήμη (store.ts)
 *  • Παραγωγή   → Supabase/PostgREST, με τους ίδιους τύπους
 *
 * Το UI καλεί ΜΟΝΟ αυτό το module· δεν γνωρίζει ποια πηγή είναι ενεργή.
 */
import { DEMO_MODE, supabase } from './supabase'
import * as store from './store'
import * as docgen from './docgen'
import { DEMO_ORG, DEMO_PROFILE } from './demoData'
import type {
  Ape, Blocker, BudgetItem, BudgetItemDraft, BudgetVersion, Completion, Contract,
  DiaryEntry, DocumentRow, FinalMeasurement, Guarantee, HiddenWorkNotice,
  Measurement, NewApeInput, NewPaymentInput, PaymentCertificate, Profile,
  Project, ProjectFinancials, ProjectStage, ProjectStageTask,
} from './types'
import { addMonths, daysUntil } from './format'
import { STAGES } from './catalogue'
import { derive, type NewProjectInput } from './newProject'
import { apeTotals, paymentTotals } from './rules'

const sb = () => {
  if (!supabase) throw new Error('Δεν υπάρχει σύνδεση Supabase.')
  return supabase
}

async function pick<T>(res: { data: T | null; error: { message: string } | null }): Promise<T> {
  if (res.error) throw new Error(res.error.message)
  return (res.data ?? []) as T
}

/* ================================================================== */
/* Ταυτότητα                                                          */
/* ================================================================== */
export async function getProfile(): Promise<Profile> {
  if (DEMO_MODE) return DEMO_PROFILE
  const { data: auth } = await sb().auth.getUser()
  if (!auth.user) throw new Error('Δεν υπάρχει ενεργή συνεδρία.')
  const profile = await pick<Omit<Profile, 'roles'>[]>(
    await sb().from('profiles').select('id, org_id, full_name, email, specialty').eq('id', auth.user.id),
  )
  const roles = await pick<{ role: string }[]>(
    await sb().from('org_roles').select('role').eq('profile_id', auth.user.id),
  )
  return { ...profile[0], roles: roles.map(r => r.role) as Profile['roles'] }
}

export async function getOrganization() {
  if (DEMO_MODE) return DEMO_ORG
  const rows = await pick<{ id: string; name: string; unit: string }[]>(
    await sb().from('organizations').select('id, name, unit').limit(1),
  )
  return rows[0]
}

export async function signIn(email: string, password: string) {
  if (DEMO_MODE) return
  const { error } = await sb().auth.signInWithPassword({ email, password })
  if (error) throw new Error(error.message)
}

export async function signOut() {
  if (DEMO_MODE) return
  await sb().auth.signOut()
}

/* ================================================================== */
/* Έργα & συμβάσεις                                                    */
/* ================================================================== */
export async function getProjects(): Promise<Project[]> {
  if (DEMO_MODE) return store.state.projects
  return pick<Project[]>(
    await sb().from('projects')
      .select('id, code, title, category, location, funding_source, study_budget_net, estimated_value_net')
      .eq('is_archived', false).order('code'),
  )
}

export async function getProject(id: string): Promise<Project | undefined> {
  const all = await getProjects()
  return all.find(p => p.id === id)
}

/* ------------------------------------------------------------------ */
/* Έναρξη επίβλεψης νέου έργου                                         */
/* ------------------------------------------------------------------ */
/**
 * Το έργο το ανοίγει η Διευθύνουσα Υπηρεσία, η οποία ορίζει και τον
 * επιβλέποντα (άρθρο 136 §2 ν. 4412/2016). Ο έλεγχος επαναλαμβάνεται και
 * στη βάση· εδώ γίνεται μόνο για να μη δείχνουμε πόρτα που δεν ανοίγει.
 */
const SERVICE_WIDE: string[] = ['admin', 'proistamenos_dy', 'proistameni_arxi', 'techniko_symvoulio']

export const canCreateProject = (p: Profile | null | undefined) =>
  Boolean(p?.roles?.some(r => SERVICE_WIDE.includes(r)))

export interface OrgPerson {
  id: string
  full_name: string
  email: string
  specialty: string | null
  grade: string | null
  registry_no: string | null
  roles: string[]
}

export async function getOrgPeople(): Promise<OrgPerson[]> {
  if (DEMO_MODE) {
    return [
      { ...DEMO_PROFILE, grade: 'ΠΕ', registry_no: null, roles: ['epivlepon'] },
      {
        id: 'demo-proistamenos', full_name: 'Γεώργιος Παπαδόπουλος',
        email: 'proistamenos@example.gr', specialty: 'Πολιτικός Μηχανικός',
        grade: 'ΠΕ', registry_no: null, roles: ['proistamenos_dy'],
      },
      {
        id: 'demo-voithos', full_name: 'Ελένη Σαββάκη',
        email: 'voithos@example.gr', specialty: 'ΤΕ Πολιτικός Μηχανικός',
        grade: 'ΤΕ', registry_no: null, roles: [],
      },
    ]
  }
  return pick<OrgPerson[]>(await sb().rpc('org_people'))
}

export interface ContractorRow {
  id: string
  name: string
  afm: string
  doy: string | null
  email: string | null
  phone: string | null
  legal_rep_name: string | null
}

export async function getContractors(): Promise<ContractorRow[]> {
  if (DEMO_MODE) {
    return Object.values(store.state.contracts).map((c, i) => ({
      id: `demo-contractor-${i}`, name: c.contractor_name, afm: c.contractor_afm,
      doy: null, email: null, phone: null, legal_rep_name: null,
    }))
  }
  return pick<ContractorRow[]>(
    await sb().from('contractors')
      .select('id, name, afm, doy, email, phone, legal_rep_name').order('name'),
  )
}

export interface CreateProjectResult {
  projectId: string
  stagesCreated: number
  code: string
}

export async function createProject(input: NewProjectInput): Promise<CreateProjectResult> {
  if (DEMO_MODE) {
    const r = store.createProject(input)
    return { projectId: r.projectId, stagesCreated: r.stages, code: input.project.code.trim() }
  }

  const d = derive(input.contract)
  const { data, error } = await sb().rpc('create_project_full', {
    payload: {
      project: {
        ...input.project,
        study_budget_net: d.studyBudgetNet,
        estimated_value_net: d.studyBudgetNet,
        vat_rate: input.contract.vat_rate,
      },
      contractor: input.contractor.id
        ? { id: input.contractor.id }
        : { ...input.contractor, id: null },
      contract: {
        ...input.contract,
        works_start_deadline: d.worksStartDue,
      },
      assignments: input.assignments,
      guarantee: input.guarantee.guarantee_no.trim() ? input.guarantee : null,
    },
  })
  if (error) throw new Error(error.message)

  return {
    projectId: data.project_id as string,
    stagesCreated: (data.stages_created as number) ?? 0,
    code: data.code as string,
  }
}

export async function getContract(projectId: string): Promise<Contract | undefined> {
  if (DEMO_MODE) return store.state.contracts[projectId]
  const rows = await pick<any[]>(
    await sb().from('contracts')
      .select('*, contractors(name, afm)')
      .eq('project_id', projectId),
  )
  const c = rows[0]
  if (!c) return undefined
  return { ...c, contractor_name: c.contractors?.name, contractor_afm: c.contractors?.afm }
}

export async function getFinancials(projectId: string): Promise<ProjectFinancials | undefined> {
  if (DEMO_MODE) {
    const c = store.state.contracts[projectId]
    if (!c) return undefined
    const apes = store.state.apes.filter(a => a.project_id === projectId && a.status === 'approved')
    const delta = apes.reduce((s, a) => s + a.delta_amount, 0)
    const pays = store.state.payments.filter(p => p.project_id === projectId)
    const certified = Math.max(0, ...pays.map(p => p.gross_cumulative))
    const paid = pays.filter(p => p.paid_at).reduce((s, p) => s + p.net_payable, 0)
    const guarantees = store.state.guarantees
      .filter(g => g.project_id === projectId && ['energi', 'meiomeni_70'].includes(g.status))
      .reduce((s, g) => s + g.current_amount, 0)
    const current = c.initial_value_net + delta
    return {
      project_id: projectId,
      initial_value_net: c.initial_value_net,
      contingency_amount: c.contingency_amount,
      contingency_pct: c.contingency_pct,
      ape_delta: delta,
      current_value_net: current,
      ape_delta_pct: c.initial_value_net ? (delta / c.initial_value_net) * 100 : null,
      limit_50pct: c.initial_value_net * 0.5,
      limit_savings_10pct: c.initial_value_net * 0.1,
      certified_total: certified,
      paid_total: paid,
      financial_progress_pct: current ? (certified / current) * 100 : null,
      advance_total: 0,
      advance_outstanding: 0,
      penalties_total: pays.reduce((s, p) => s + p.penalties_amount, 0),
      guarantees_active: guarantees,
      original_end_date: c.original_end_date,
      current_end_date: c.current_end_date,
      days_to_deadline: daysUntil(c.current_end_date) ?? 0,
    }
  }
  const rows = await pick<ProjectFinancials[]>(
    await sb().from('v_project_financials').select('*').eq('project_id', projectId),
  )
  return rows[0]
}

/* ================================================================== */
/* Ροή σταδίων                                                         */
/* ================================================================== */
export async function getStages(projectId: string): Promise<ProjectStage[]> {
  if (DEMO_MODE) {
    return store.state.stages
      .filter(s => s.project_id === projectId)
      .map(s => {
        const b = store.stageBlockers(s.id)
        const tasks = store.state.stageTasks.filter(t => t.project_stage_id === s.id)
        return {
          ...s,
          hard_blockers: b.filter(x => x.severity === 'hard').length,
          soft_blockers: b.filter(x => x.severity === 'soft').length,
          tasks_total: tasks.length,
          tasks_done: tasks.filter(t => t.is_done || t.waived).length,
        }
      })
      .sort((a, b) => ord(a.stage_code) - ord(b.stage_code))
  }
  return pick<ProjectStage[]>(
    await sb().from('v_stage_board').select('*').eq('project_id', projectId).order('ordinal'),
  )
}

const ord = (code: string) => STAGES.find(s => s.code === code)?.ordinal ?? 999

export async function getStageBlockers(stageId: string): Promise<Blocker[]> {
  if (DEMO_MODE) return store.stageBlockers(stageId)
  return pick<Blocker[]>(await sb().rpc('stage_blockers', { p_project_stage_id: stageId }))
}

export async function getStageTasks(stageId: string): Promise<ProjectStageTask[]> {
  if (DEMO_MODE) return store.state.stageTasks.filter(t => t.project_stage_id === stageId)
  return pick<ProjectStageTask[]>(
    await sb().from('project_stage_tasks').select('*').eq('project_stage_id', stageId),
  )
}

export async function toggleStageTask(taskInstanceId: string, done: boolean) {
  if (DEMO_MODE) return store.setTaskDone(taskInstanceId, done)
  const { error } = await sb().from('project_stage_tasks')
    .update({ is_done: done, done_at: done ? new Date().toISOString() : null })
    .eq('id', taskInstanceId)
  if (error) throw new Error(error.message)
}

export async function completeStage(stageId: string, override?: { reason: string; profileId: string }) {
  if (DEMO_MODE) return store.completeStage(stageId, override ? { reason: override.reason } : undefined)
  const payload: Record<string, unknown> = { status: 'completed' }
  if (override) {
    payload.override_by = override.profileId
    payload.override_reason = override.reason
  }
  const { error } = await sb().from('project_stages').update(payload).eq('id', stageId)
  if (error) throw new Error(error.message) // Το trigger επιστρέφει τη νομική αιτιολογία
}

export async function startStage(stageId: string) {
  if (DEMO_MODE) return store.startStage(stageId)
  const { error } = await sb().from('project_stages').update({ status: 'in_progress' }).eq('id', stageId)
  if (error) throw new Error(error.message)
}

export async function markStageNotApplicable(stageId: string, reason: string) {
  if (DEMO_MODE) return store.markNotApplicable(stageId, reason)
  const { error } = await sb().from('project_stages')
    .update({ status: 'not_applicable', na_reason: reason }).eq('id', stageId)
  if (error) throw new Error(error.message)
}

/* ================================================================== */
/* Ημερολόγιο                                                          */
/* ================================================================== */
export async function getDiary(projectId: string): Promise<DiaryEntry[]> {
  if (DEMO_MODE) return [...(store.state.diary[projectId] ?? [])].sort((a, b) => b.entry_date.localeCompare(a.entry_date))
  return pick<DiaryEntry[]>(
    await sb().from('diary_entries').select('*').eq('project_id', projectId)
      .order('entry_date', { ascending: false }).limit(400),
  )
}

export async function addDiaryEntry(e: DiaryEntry) {
  if (DEMO_MODE) return store.addDiaryEntry(e)
  const { error } = await sb().from('diary_entries').insert(e)
  if (error) throw new Error(error.message)
}

export async function reviewDiaryEntry(projectId: string, entryId: string) {
  if (DEMO_MODE) return store.reviewDiaryEntry(projectId, entryId)
  const { error } = await sb().from('diary_entries')
    .update({ status: 'reviewed', reviewed_at: new Date().toISOString() }).eq('id', entryId)
  if (error) throw new Error(error.message)
}

/* ================================================================== */
/* Αφανείς εργασίες                                                    */
/* ================================================================== */
export async function getHiddenWorks(projectId: string): Promise<HiddenWorkNotice[]> {
  if (DEMO_MODE) return store.state.hidden.filter(h => h.project_id === projectId)
  return pick<HiddenWorkNotice[]>(
    await sb().from('hidden_work_notices').select('*').eq('project_id', projectId).order('serial_no'),
  )
}

export async function inspectHiddenWork(id: string, photos: number) {
  if (DEMO_MODE) return store.inspectHiddenWork(id, photos)
  const { error } = await sb().from('hidden_work_notices')
    .update({
      inspected_at: new Date().toISOString().slice(0, 10),
      supervisor_report_at: new Date().toISOString().slice(0, 10),
      photos_count: photos, status: 'reported',
    }).eq('id', id)
  if (error) throw new Error(error.message)
}

export async function approveHiddenWork(id: string) {
  if (DEMO_MODE) return store.approveHiddenWork(id)
  const { error } = await sb().from('hidden_work_notices')
    .update({ approved_at: new Date().toISOString().slice(0, 10), status: 'approved' }).eq('id', id)
  if (error) throw new Error(error.message)
}

/* ================================================================== */
/* Επιμετρήσεις                                                        */
/* ================================================================== */
export async function getMeasurements(projectId: string): Promise<Measurement[]> {
  if (DEMO_MODE) return store.state.measurements.filter(m => m.project_id === projectId)
  return pick<Measurement[]>(
    await sb().from('measurements').select('*').eq('project_id', projectId)
      .order('mtype').order('serial_no'),
  )
}

export async function auditMeasurement(id: string) {
  if (DEMO_MODE) return store.auditMeasurement(id)
  const { error } = await sb().from('measurement_audits').insert({
    measurement_id: id, ordered_at: new Date().toISOString().slice(0, 10),
    auditor: 'Δειγματοληπτικός έλεγχος', performed_at: new Date().toISOString().slice(0, 10),
  })
  if (error) throw new Error(error.message)
}

export async function approveMeasurement(id: string) {
  if (DEMO_MODE) return store.approveMeasurement(id)
  const { error } = await sb().from('measurements')
    .update({ status: 'approved', approved_at: new Date().toISOString().slice(0, 10) }).eq('id', id)
  if (error) throw new Error(error.message)
}

export async function getFinalMeasurement(projectId: string): Promise<FinalMeasurement | undefined> {
  if (DEMO_MODE) return store.state.finalMeasurements[projectId]
  const rows = await pick<FinalMeasurement[]>(
    await sb().from('final_measurement').select('*').eq('project_id', projectId),
  )
  return rows[0]
}

/* ================================================================== */
/* Λογαριασμοί                                                         */
/* ================================================================== */
export async function getPayments(projectId: string): Promise<PaymentCertificate[]> {
  if (DEMO_MODE) return store.state.payments.filter(p => p.project_id === projectId)
  return pick<PaymentCertificate[]>(
    await sb().from('payment_certificates').select('*').eq('project_id', projectId).order('serial_no'),
  )
}

export async function approvePayment(id: string) {
  if (DEMO_MODE) return store.approvePayment(id)
  const { error } = await sb().from('payment_certificates')
    .update({ status: 'approved', approved_at: new Date().toISOString().slice(0, 10) }).eq('id', id)
  if (error) throw new Error(error.message)
}

/* ================================================================== */
/* ΑΠΕ                                                                 */
/* ================================================================== */
export async function getApes(projectId: string): Promise<Ape[]> {
  if (DEMO_MODE) return store.state.apes.filter(a => a.project_id === projectId)
  const rows = await pick<any[]>(
    await sb().from('ape')
      .select('*, ape_lines(*, work_groups(code, title))')
      .eq('project_id', projectId).order('serial_no'),
  )
  // Η βάση τηρεί `work_group_id`· ο έλεγχος του ορίου 20% ανά ομάδα
  // (άρθρο 156 §3γ) χρειάζεται τον ΤΙΤΛΟ της ομάδας. Χωρίς αυτή την
  // αντιστοίχιση όλες οι γραμμές θα ομαδοποιούνταν σε μία «undefined»
  // ομάδα και το όριο δεν θα ελεγχόταν ποτέ πραγματικά.
  return rows.map(r => ({
    ...r,
    lines: (r.ape_lines ?? []).map((l: any) => ({
      ...l,
      work_group: l.work_groups?.title ?? l.work_groups?.code ?? '—',
    })),
  }))
}

export async function approveApe(id: string) {
  if (DEMO_MODE) return store.approveApe(id)
  const { error } = await sb().from('ape').update({ status: 'approved' }).eq('id', id)
  if (error) throw new Error(error.message)
}

export async function attachTcOpinion(apeId: string) {
  if (DEMO_MODE) return store.attachTcOpinion(apeId)
  const { data, error } = await sb().from('technical_council_opinions').insert({
    project_id: (await sb().from('ape').select('project_id').eq('id', apeId).single()).data?.project_id,
    subject: 'Γνωμοδότηση επί ΑΠΕ', subject_kind: 'ape',
    requested_at: new Date().toISOString().slice(0, 10), outcome: 'accepted',
  }).select('id').single()
  if (error) throw new Error(error.message)
  await sb().from('ape').update({ tc_opinion_id: data!.id }).eq('id', apeId)
}

export async function signApe(apeId: string, kind: 'anepifylakta' | 'me_epifylaxi' | 'arnisi') {
  if (DEMO_MODE) return store.signApe(apeId, kind)
  const status = kind === 'arnisi' ? 'not_signed'
    : kind === 'me_epifylaxi' ? 'signed_me_epifylaxi' : 'signed_anepifylakta'
  const { error } = await sb().from('ape')
    .update({ contractor_signature: kind, status }).eq('id', apeId)
  if (error) throw new Error(error.message)
}

/* ================================================================== */
/* Προϋπολογισμός μελέτης                                              */
/* ================================================================== */

/**
 * Αντιστοίχιση ομάδας εργασιών → id της βάσης, ανά κατηγορία έργου.
 * Το front-end μεταφέρει τον ΤΙΤΛΟ της ομάδας (ώστε ο έλεγχος του ορίου 20%
 * ανά ομάδα να διαβάζεται από άνθρωπο), αλλά ο χάρτης δέχεται και τον κωδικό
 * — μια γραμμή που προσυμπληρώθηκε από παλαιότερη εγγραφή μπορεί να φέρει
 * οποιοδήποτε από τα δύο.
 */
async function workGroupIds(category: string): Promise<Map<string, number>> {
  const rows = await pick<{ id: number; code: string; title: string }[]>(
    await sb().from('work_groups').select('id, code, title').eq('category', category),
  )
  const m = new Map<string, number>()
  for (const r of rows) {
    m.set(r.code, r.id)
    m.set(r.title, r.id)
  }
  return m
}

export async function getBudget(
  projectId: string,
): Promise<{ version: BudgetVersion; items: BudgetItem[] } | undefined> {
  if (DEMO_MODE) return store.getBudget(projectId)
  const versions = await pick<BudgetVersion[]>(
    await sb().from('budget_versions').select('*')
      .eq('project_id', projectId).order('version_no'),
  )
  const version = versions.find(v => v.version_no === 0)
  if (!version) return undefined
  const rows = await pick<any[]>(
    await sb().from('budget_items')
      .select('*, work_groups(code, title)')
      .eq('version_id', version.id).order('line_no'),
  )
  return {
    version,
    items: rows.map(r => ({ ...r, work_group: r.work_groups?.title ?? '—' })),
  }
}

/** Καταχώριση του ΑΡΧΙΚΟΥ (συμβατικού) προϋπολογισμού — έκδοση 0. */
export async function saveBudget(
  projectId: string,
  lines: BudgetItemDraft[],
): Promise<{ versionId: string; itemCount: number; totalNet: number }> {
  if (DEMO_MODE) return store.saveBudget(projectId, lines)

  const totalNet =
    Math.round(lines.reduce((s, l) => s + l.unit_price * l.quantity, 0) * 100) / 100

  const project = await pick<{ category: string }[]>(
    await sb().from('projects').select('category').eq('id', projectId),
  )
  const groups = await workGroupIds(project[0]?.category ?? '')

  // Μία έκδοση 0 ανά έργο: αν υπάρχει, αντικαθίστανται οι γραμμές της.
  const existing = await pick<BudgetVersion[]>(
    await sb().from('budget_versions').select('*')
      .eq('project_id', projectId).eq('version_no', 0),
  )

  let versionId: string
  if (existing[0]) {
    versionId = existing[0].id
    const { error } = await sb().from('budget_versions')
      .update({ total_net: totalNet }).eq('id', versionId)
    if (error) throw new Error(error.message)
    const del = await sb().from('budget_items').delete().eq('version_id', versionId)
    if (del.error) throw new Error(del.error.message)
  } else {
    const { data, error } = await sb().from('budget_versions').insert({
      project_id: projectId, version_no: 0, label: 'Αρχική Σύμβαση',
      is_current: true, total_net: totalNet,
    }).select('id').single()
    if (error) throw new Error(error.message)
    versionId = data!.id
  }

  const { error: insErr } = await sb().from('budget_items').insert(
    lines.map(l => ({
      project_id: projectId,
      version_id: versionId,
      line_no: l.line_no,
      item_code: l.item_code,
      description: l.description,
      unit: l.unit,
      work_group_id: groups.get(l.work_group) ?? null,
      unit_price: l.unit_price,
      quantity: l.quantity,
    })),
  )
  if (insErr) throw new Error(insErr.message)

  return { versionId, itemCount: lines.length, totalNet }
}

/* ================================================================== */
/* Σύνταξη ΑΠΕ (άρθρο 156 §2) — συντάσσει η Υπηρεσία                   */
/* ================================================================== */
export async function createApe(input: NewApeInput): Promise<{ apeId: string; serialNo: number }> {
  if (DEMO_MODE) return store.createApe(input)

  const contract = await getContract(input.project_id)
  if (!contract) throw new Error('Δεν βρέθηκε σύμβαση για το έργο.')

  const existing = await pick<{ serial_no: number }[]>(
    await sb().from('ape').select('serial_no')
      .eq('project_id', input.project_id).order('serial_no', { ascending: false }),
  )
  const serialNo = (existing[0]?.serial_no ?? 0) + 1

  const t = apeTotals(input.lines, contract.initial_value_net)

  const project = await pick<{ category: string }[]>(
    await sb().from('projects').select('category').eq('id', input.project_id),
  )
  const groups = await workGroupIds(project[0]?.category ?? '')

  const { data, error } = await sb().from('ape').insert({
    project_id: input.project_id,
    serial_no: serialNo,
    atype: input.atype,
    reason: input.reason,
    drafted_at: input.drafted_at,
    initial_contract_value: contract.initial_value_net,
    previous_ape_value: t.previousValue,
    contingency_used: t.contingencyUsed,
    contingency_remaining:
      Math.round((contract.contingency_amount - t.contingencyUsed) * 100) / 100,
    savings_used: t.savings,
    new_total_value: t.newTotal,
    delta_pct: contract.initial_value_net
      ? Math.round((t.delta / contract.initial_value_net) * 1_000_000) / 10_000
      : null,
    supplementary_needed: input.supplementary_needed,
    status: 'draft',
    legal_ref_id: 'N4412/156/2',
  }).select('id').single()
  if (error) throw new Error(error.message)

  const apeId = data!.id
  // amount_initial / amount_new / delta_amount είναι ΠΑΡΑΓΟΜΕΝΕΣ στήλες —
  // δεν αποστέλλονται.
  const { error: linesErr } = await sb().from('ape_lines').insert(
    input.lines.map(l => ({
      ape_id: apeId,
      work_group_id: groups.get(l.work_group) ?? null,
      item_code: l.item_code,
      description: l.description,
      unit: l.unit,
      unit_price: l.unit_price,
      qty_initial: l.qty_initial,
      qty_previous: l.qty_previous,
      qty_new: l.qty_new,
      funding_source: l.funding_source,
      is_new_item: l.is_new_item,
    })),
  )
  if (linesErr) throw new Error(linesErr.message)

  return { apeId, serialNo }
}

/* ================================================================== */
/* Σύνταξη λογαριασμού (άρθρο 152)                                     */
/* ================================================================== */
export async function createPayment(
  input: NewPaymentInput,
): Promise<{ paymentId: string; serialNo: number }> {
  if (DEMO_MODE) return store.createPayment(input)

  const existing = await pick<{ serial_no: number }[]>(
    await sb().from('payment_certificates').select('serial_no')
      .eq('project_id', input.project_id).eq('ptype', input.ptype)
      .order('serial_no', { ascending: false }),
  )
  const serialNo = (existing[0]?.serial_no ?? 0) + 1

  const prior = await pick<any[]>(
    await sb().from('payment_certificates')
      .select('gross_cumulative, retentions_amount')
      .eq('project_id', input.project_id),
  )
  const t = paymentTotals(input, prior)

  const { data, error } = await sb().from('payment_certificates').insert({
    project_id: input.project_id,
    ptype: input.ptype,
    serial_no: serialNo,
    period_from: input.period_from,
    period_to: input.period_to,
    measurement_id: input.measurement_id,
    submitted_at: input.submitted_at,
    // Άρθρο 152: η Δ.Υ. εγκρίνει εντός ΕΝΟΣ ΜΗΝΟΣ από την υποβολή.
    approval_due: addMonths(input.submitted_at, 1),
    status: 'submitted',
    works_cumulative: input.works_cumulative,
    ge_oe_amount: input.ge_oe_amount,
    apologistika_amount: input.apologistika_amount,
    revision_amount: input.revision_amount,
    compensations: input.compensations,
    gross_cumulative: t.gross,
    previous_certified: t.previousCertified,
    advance_amortization: input.advance_amortization,
    penalties_amount: input.penalties_amount,
    other_deductions: input.other_deductions,
    retentions_pct: input.retentions_pct,
    retentions_amount: t.retentions,
    vat_rate: input.vat_rate,
    vat_amount: t.vat,
    net_payable: t.net,
    has_summary_table: input.has_summary_table,
    has_revision_calc: input.has_revision_calc,
    legal_ref_id: 'N4412/152',
  }).select('id').single()
  if (error) throw new Error(error.message)

  return { paymentId: data!.id, serialNo }
}

/* ================================================================== */
/* Εγγυήσεις                                                           */
/* ================================================================== */
export async function getGuarantees(projectId: string): Promise<Guarantee[]> {
  if (DEMO_MODE) return store.state.guarantees.filter(g => g.project_id === projectId)
  const rows = await pick<any[]>(
    await sb().from('guarantees').select('*, guarantee_events(*)').eq('project_id', projectId),
  )
  return rows.map(r => ({ ...r, events: r.guarantee_events ?? [] }))
}

export async function reduceGuarantee70(guaranteeId: string) {
  if (DEMO_MODE) return store.reduceGuarantee70(guaranteeId)
  const g = (await sb().from('guarantees').select('*').eq('id', guaranteeId).single()).data!
  const { error } = await sb().from('guarantee_events').insert({
    guarantee_id: guaranteeId, event_type: 'meiosi_70',
    amount_before: g.current_amount, amount_after: Math.round(g.current_amount * 0.3 * 100) / 100,
    trigger_event: 'egkrisi_telikis_epimetrisis',
    decision_date: new Date().toISOString().slice(0, 10), reduction_pct: 70,
  })
  if (error) throw new Error(error.message)
}

export async function releaseGuarantee(guaranteeId: string) {
  if (DEMO_MODE) return store.releaseGuarantee(guaranteeId)
  const g = (await sb().from('guarantees').select('*').eq('id', guaranteeId).single()).data!
  const { error } = await sb().from('guarantee_events').insert({
    guarantee_id: guaranteeId, event_type: 'apodesmevsi',
    amount_before: g.current_amount, amount_after: 0,
    trigger_event: 'egkrisi_paralavis_kai_telikou_logariasmou',
    decision_date: new Date().toISOString().slice(0, 10),
  })
  if (error) throw new Error(error.message)
}

/* ================================================================== */
/* Περαίωση & έγγραφα                                                  */
/* ================================================================== */
export async function getCompletion(projectId: string): Promise<Completion | undefined> {
  if (DEMO_MODE) return store.state.completions[projectId]
  const rows = await pick<Completion[]>(
    await sb().from('completions').select('*').eq('project_id', projectId),
  )
  return rows[0]
}

/**
 * Έγκριση πρωτοκόλλου παραλαβής (άρθρο 172). ΔΙΑΦΟΡΕΤΙΚΗ από τη Βεβαίωση
 * Περάτωσης του άρθρου 168: μόνο η εγκεκριμένη παραλαβή θεμελιώνει τον
 * ΤΕΛΙΚΟ λογαριασμό και την επιστροφή των εγγυήσεων.
 */
export async function isAcceptanceApproved(projectId: string): Promise<boolean> {
  if (DEMO_MODE) return Boolean(store.state.acceptance[projectId]?.approved_at)
  const rows = await pick<{ approved_at: string | null }[]>(
    await sb().from('acceptances').select('approved_at').eq('project_id', projectId),
  )
  return Boolean(rows[0]?.approved_at)
}

export async function getDocuments(projectId: string): Promise<DocumentRow[]> {
  if (DEMO_MODE) return store.state.documents.filter(d => d.project_id === projectId)
  return pick<DocumentRow[]>(
    await sb().from('documents')
      .select('id, project_id, doc_code, title, protocol_no, protocol_date, ada, status, created_at')
      .eq('project_id', projectId).order('created_at', { ascending: false }),
  )
}

/* ================================================================== */
/* Παραγωγή εγγράφων από τα πρότυπα της Υπηρεσίας                      */
/* ------------------------------------------------------------------ */
/* Παραγωγή : Edge Function `generate-document` — διαβάζει με το JWT   */
/*            του χρήστη (ισχύουν τα RLS), αποδίδει αριθμό             */
/*            πρωτοκόλλου, αποθηκεύει στο bucket «documents» και       */
/*            καταχωρίζει εγγραφή στον πίνακα documents.               */
/* Επίδειξη : τοπική απόδοση μέσω docgen.ts (μόνο προεπισκόπηση).      */
/* ================================================================== */
export interface GeneratedDocument {
  html: string
  missing: string[]
  title: string
  docCode: string
  protocolNo: string | null
  downloadUrl: string | null
  stored: boolean
}

export async function generateDocument(opts: {
  projectId: string
  docCode: string
  entityId?: string | null
  projectStageId?: string | null
  /** true = μόνο προεπισκόπηση, χωρίς πρωτόκολλο και χωρίς αποθήκευση */
  dryRun?: boolean
}): Promise<GeneratedDocument> {
  const { projectId, docCode, entityId = null, projectStageId = null, dryRun = true } = opts
  const tpl = docgen.TEMPLATE_BY_CODE[docCode]

  if (DEMO_MODE) {
    if (!tpl) throw new Error(`Δεν υπάρχει διαθέσιμο πρότυπο για τον κωδικό «${docCode}».`)
    const ctx = await demoContext(projectId, entityId)
    const res = docgen.generate(docCode, ctx, dryRun ? null : `${new Date().getFullYear()}/${1000 + store.state.documents.length}`)
    if (!dryRun) store.addDocument(projectId, docCode, res.template.title)
    return {
      html: res.html, missing: res.missing, title: res.template.title, docCode,
      protocolNo: null, downloadUrl: null, stored: !dryRun,
    }
  }

  const { data, error } = await sb().functions.invoke('generate-document', {
    body: {
      project_id: projectId, doc_code: docCode, entity_id: entityId,
      project_stage_id: projectStageId, dry_run: dryRun,
    },
  })
  if (error) throw new Error(error.message)
  if (data?.error) throw new Error(data.error)

  return {
    html: (data.preview_html as string) ?? '',
    missing: (data.missing_fields as string[]) ?? [],
    title: tpl?.title ?? docCode,
    docCode,
    protocolNo: (data.document?.protocol_no as string) ?? null,
    downloadUrl: (data.download_url as string) ?? null,
    stored: !dryRun,
  }
}

/** Συγκέντρωση των δεδομένων του έργου για την τοπική απόδοση (επίδειξη). */
async function demoContext(
  projectId: string,
  entityId: string | null,
): Promise<docgen.DocContext> {
  const project = store.state.projects.find(p => p.id === projectId)!
  const contract = store.state.contracts[projectId]
  const measurement =
    store.state.measurements.find(m => m.id === entityId) ??
    store.state.measurements.filter(m => m.project_id === projectId).slice(-1)[0]
  const hidden =
    store.state.hidden.find(h => h.id === entityId) ??
    store.state.hidden.filter(h => h.project_id === projectId).find(h => h.inspected_at)
  const guarantee =
    store.state.guarantees.find(g => g.id === entityId) ??
    store.state.guarantees.find(g => g.project_id === projectId && g.gtype === 'kalis_ektelesis')

  return {
    org: { name: DEMO_ORG.name, unit: DEMO_ORG.unit },
    project,
    contract,
    supervisor: { full_name: DEMO_PROFILE.full_name, specialty: DEMO_PROFILE.specialty },
    head: { full_name: 'Γεώργιος Παπαδόπουλος', specialty: 'Πολιτικός Μηχανικός' },
    entity: {
      hidden,
      measurement,
      lines: measurement ? demoLines(measurement) : [],
      guarantee,
      completion: store.state.completions[projectId],
      finalApprovedAt: store.state.finalMeasurements[projectId]?.approved_at ?? null,
      scheduleSubmittedAt: store.state.schedules[projectId]?.submitted_at ?? null,
    },
  }
}

/**
 * Ενδεικτικές γραμμές επιμέτρησης για την επίδειξη. Στην παραγωγή οι
 * γραμμές προέρχονται από τον πίνακα measurement_lines.
 */
const DEMO_ITEMS = [
  { code: 'ΟΔΟ Α-2', desc: 'Γενικές εκσκαφές σε έδαφος γαιώδες–ημιβραχώδες', unit: 'm3', price: 3.2, share: 0.11 },
  { code: 'ΟΔΟ Γ-1.2', desc: 'Υπόβαση οδοστρωσίας μεταβλητού πάχους', unit: 'm3', price: 12.5, share: 0.2 },
  { code: 'ΟΔΟ Δ-8.1', desc: 'Ασφαλτική στρώση κυκλοφορίας 5 cm', unit: 'm2', price: 8.9, share: 0.42 },
  { code: 'ΟΙΚ 38.20', desc: 'Χαλύβδινος οπλισμός σκυροδέματος B500C', unit: 'kg', price: 1.15, share: 0.11 },
  { code: 'ΟΔΟ Β-51', desc: 'Πρόχυτα κράσπεδα από σκυρόδεμα', unit: 'm', price: 11.4, share: 0.16 },
]

function demoLines(m: Measurement) {
  const total = m.contractual_amount || 0
  return DEMO_ITEMS.map((it, i) => {
    const amount = Math.round(total * it.share * 100) / 100
    const qty = Math.round((amount / it.price) * 1000) / 1000
    return {
      aa: i + 1, arthro: it.code, perigrafi: it.desc, monada: it.unit,
      timi: docgen.formatValue(it.price, 'currency'),
      posotita: docgen.formatValue(qty, 'quantity'),
      dapani: docgen.formatValue(amount, 'currency'),
    }
  })
}

export { DEMO_MODE }
export { RuleViolation } from './store'
