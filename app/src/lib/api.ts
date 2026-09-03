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
  Ape, Blocker, Completion, Contract, DiaryEntry, DocumentRow, FinalMeasurement,
  Guarantee, HiddenWorkNotice, Measurement, PaymentCertificate, Profile,
  Project, ProjectFinancials, ProjectStage, ProjectStageTask,
} from './types'
import { daysUntil } from './format'
import { STAGES } from './catalogue'

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
    await sb().from('ape').select('*, ape_lines(*)').eq('project_id', projectId).order('serial_no'),
  )
  return rows.map(r => ({ ...r, lines: r.ape_lines ?? [] }))
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
