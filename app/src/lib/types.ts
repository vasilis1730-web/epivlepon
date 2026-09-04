/**
 * Τύποι που αντιστοιχούν στο σχήμα της βάσης (migrations 0001-0014).
 * Όταν συνδεθεί πραγματικό Supabase project, μπορείτε να παράγετε
 * αυτόματα τους τύπους με `npm run gen:types` και να τους συνδυάσετε.
 */

export type RoleType =
  | 'admin' | 'proistameni_arxi' | 'proistamenos_dy' | 'epivlepon'
  | 'voithos_epivlepon' | 'syntonistis' | 'ife' | 'anadochos'
  | 'techniko_symvoulio' | 'epitropi_paralavis' | 'epitropi_timon' | 'theatis'

export type PartyType =
  | 'anadochos' | 'epivlepon' | 'dieuthynousa_ypiresia' | 'proistameni_arxi'
  | 'techniko_symvoulio' | 'epitropi' | 'ife' | 'kyrios_ergou'

export type StagePhase =
  | 'f0_systasi' | 'f1_egkatastasi' | 'f2_ektelesi' | 'f3_peraiosi' | 'f4_paralavi'

export type StageStatus =
  | 'locked' | 'available' | 'in_progress' | 'pending_approval'
  | 'completed' | 'not_applicable' | 'overdue'

export type RecurrenceType = 'once' | 'repeating' | 'continuous' | 'conditional'

/**
 * Αφετηρία της προθεσμίας ενός σταδίου. Οι τρεις τελευταίες τιμές αφορούν
 * γεγονότα που συμβαίνουν ανά έγγραφο ή ανά πράξη: η προθεσμία τηρείται
 * στην ίδια την εγγραφή (approval_due, inspection_due, decision_due) και
 * όχι στο στάδιο, γι' αυτό το στάδιο μένει χωρίς ημερομηνία.
 */
export type DeadlineBasis =
  | 'ypografi_symvasis' | 'enarxi_ergasion' | 'lixi_prothesmias'
  | 'bebaiosi_peratosis' | 'lixi_syntirisis'
  | 'ypovoli_eggrafou' | 'koinopoiisi_praxis' | 'custom'

export type MeasurementStatus =
  | 'draft' | 'submitted' | 'sampled' | 'under_check'
  | 'returned_for_fix' | 'approved' | 'deemed_approved' | 'rejected'

export type PaymentStatus =
  | 'draft' | 'submitted' | 'under_review' | 'returned_for_fix'
  | 'approved' | 'deemed_approved' | 'paid' | 'rejected'

export type ApeStatus =
  | 'draft' | 'signed_anepifylakta' | 'signed_me_epifylaxi' | 'not_signed'
  | 'tc_opinion_pending' | 'approved' | 'rejected'

export type ApeType =
  | 'taktopoiitikos' | 'me_apravlepta' | 'me_epi_elasson'
  | 'me_pktmne' | 'symplirwmatiki_symvasi' | 'epeigousa_apravlepti'

export type GuaranteeType =
  | 'kalis_ektelesis' | 'prosthetti' | 'prokatavolis' | 'kalis_leitourgias' | 'dekaton'

export type GuaranteeStatus =
  | 'ekremmei_katathesi' | 'energi' | 'meiomeni_70' | 'apodesmevmeni' | 'katapiptousa'

export type DiaryStatus = 'draft' | 'submitted' | 'reviewed' | 'approved' | 'missing'

export type ProjectCategory =
  | 'odopoiia' | 'oikodomika' | 'ydraulika' | 'limenika' | 'hlektromichanologika'
  | 'viomichanika_energeiaka' | 'prasino' | 'katharismos_epexergasia' | 'geotrhseis' | 'loipa'

export type BlockerSeverity = 'hard' | 'soft'

/** Επιστρέφεται από την app.stage_blockers() */
export interface Blocker {
  code: string
  message: string
  severity: BlockerSeverity
  legal_ref: string
}

export interface Profile {
  id: string
  org_id: string
  full_name: string
  email: string
  specialty: string | null
  roles: RoleType[]
}

export interface Project {
  id: string
  code: string
  title: string
  category: ProjectCategory
  location: string | null
  funding_source: string | null
  study_budget_net: number
  estimated_value_net: number
}

export interface Contract {
  project_id: string
  contractor_name: string
  contractor_afm: string
  contract_no: string
  signed_at: string
  discount_pct: number
  initial_value_net: number
  contingency_pct: number
  contingency_amount: number
  vat_rate: number
  total_duration_days: number
  original_end_date: string
  current_end_date: string
  works_start_deadline: string | null
  maintenance_months: number
  supervision_mode: 'ypiresiaki' | 'ife' | 'mikti'
  diary_mode: 'imerisio' | 'evdomadiaio' | 'apallagi'
  diary_penalty_per_day: number
  status: string
}

/** Γραμμή της όψης v_project_financials */
export interface ProjectFinancials {
  project_id: string
  initial_value_net: number
  contingency_amount: number
  contingency_pct: number
  ape_delta: number
  current_value_net: number
  ape_delta_pct: number | null
  limit_50pct: number
  limit_savings_10pct: number
  certified_total: number
  paid_total: number
  financial_progress_pct: number | null
  advance_total: number
  advance_outstanding: number
  penalties_total: number
  guarantees_active: number
  original_end_date: string
  current_end_date: string
  days_to_deadline: number
}

/** Κατάλογος σταδίων (workflow_stages) */
export interface WorkflowStage {
  code: string
  phase: StagePhase
  ordinal: number
  title: string
  purpose: string
  responsible: PartyType
  approver: PartyType | null
  recurrence: RecurrenceType
  legal_ref_id: string | null
  deadline_days: number | null
  deadline_months: number | null
  /** Από ποιο γεγονός αρχίζει να τρέχει η προθεσμία του σταδίου. */
  deadline_basis: DeadlineBasis | null
  tacit_approval: boolean
  tacit_effect: string | null
  guard_fn: string | null
  risk_note: string | null
  prerequisites: string[]
}

export interface StageTask {
  id: number
  stage_code: string
  ordinal: number
  party: PartyType
  title: string
  detail: string | null
  legal_ref_id: string | null
  is_mandatory: boolean
  needs_evidence: boolean
}

export interface StageDocument {
  stage_code: string
  doc_code: string
  title: string
  produced_by: PartyType
  is_mandatory: boolean
  legal_ref_id: string | null
}

/** Γραμμή της όψης v_stage_board, εμπλουτισμένη */
export interface ProjectStage {
  id: string
  project_id: string
  stage_code: string
  cycle_no: number
  status: StageStatus
  due_date: string | null
  completed_at: string | null
  override_reason: string | null
  na_reason: string | null
  hard_blockers: number
  soft_blockers: number
  tasks_total: number
  tasks_done: number
}

export interface ProjectStageTask {
  id: string
  project_stage_id: string
  stage_task_id: number
  is_done: boolean
  done_at: string | null
  waived: boolean
  waive_reason: string | null
  evidence_doc_id: string | null
}

export interface DiaryEntry {
  id: string
  project_id: string
  entry_date: string
  weather: string | null
  personnel: { eidikotita: string; arithmos: number }[]
  equipment: { michanima: string; ores: number }[]
  works_description: string
  delay_reasons: string | null
  accidents: string | null
  supervisor_orders: string | null
  status: DiaryStatus
  submitted_at: string | null
  reviewed_at: string | null
  approved_at: string | null
}

export interface HiddenWorkNotice {
  id: string
  project_id: string
  serial_no: number
  work_description: string
  location: string
  declaration_at: string
  invitation_sent_at: string
  inspection_due: string
  inspected_at: string | null
  supervisor_report_at: string | null
  photos_count: number
  covered_at: string | null
  approval_due: string | null
  approved_at: string | null
  status: string
}

export interface Measurement {
  id: string
  project_id: string
  mtype: 'tmimatiki' | 'afanon' | 'zygisis' | 'teliki'
  serial_no: number
  period_from: string | null
  period_to: string | null
  work_section: string | null
  submitted_at: string | null
  truth_declaration: boolean
  status: MeasurementStatus
  selected_for_audit: boolean
  audited: boolean
  approval_due: string | null
  approved_at: string | null
  contractual_amount: number
  extra_amount: number
  total_amount: number
}

export interface PaymentCertificate {
  id: string
  project_id: string
  ptype: 'tmimatikos' | 'telikos' | 'prokatavoli'
  serial_no: number
  period_from: string | null
  period_to: string | null
  measurement_id: string | null
  submitted_at: string | null
  approval_due: string | null
  approved_at: string | null
  status: PaymentStatus
  gross_cumulative: number
  previous_certified: number
  period_amount: number
  advance_amortization: number
  penalties_amount: number
  retentions_amount: number
  net_payable: number
  vat_amount: number
  has_summary_table: boolean
  has_revision_calc: boolean
  paid_at: string | null
}

export interface ApeLine {
  id: string
  work_group: string
  item_code: string
  description: string
  unit: string
  unit_price: number
  qty_initial: number
  qty_new: number
  amount_initial: number
  amount_new: number
  delta_amount: number
  funding_source: 'symvatiko' | 'apravlepta' | 'epi_elasson' | 'symplirwmatiki' | 'apologistika'
  is_new_item: boolean
}

export interface Ape {
  id: string
  project_id: string
  serial_no: number
  atype: ApeType
  reason: string
  drafted_at: string
  initial_contract_value: number
  new_total_value: number
  delta_amount: number
  contingency_used: number
  savings_used: number
  supplementary_needed: boolean
  tc_opinion_id: string | null
  contractor_signature: string | null
  status: ApeStatus
  approved_at: string | null
  lines: ApeLine[]
}

export interface Guarantee {
  id: string
  project_id: string
  gtype: GuaranteeType
  issuer: string
  guarantee_no: string
  issued_at: string
  original_amount: number
  current_amount: number
  pct_of_contract: number | null
  status: GuaranteeStatus
  events: GuaranteeEvent[]
}

export interface GuaranteeEvent {
  id: string
  event_type: 'meiosi_70' | 'apodesmevsi' | 'merikia_apodesmevsi' | 'katapt' | 'ananeosi' | 'avxisi'
  amount_before: number
  amount_after: number
  trigger_event: string
  decision_date: string
}

export interface FinalMeasurement {
  project_id: string
  completion_date: string
  contractor_due: string | null
  submitted_at: string | null
  supervisor_report_due: string | null
  supervisor_report_at: string | null
  approval_due: string | null
  approved_at: string | null
  penalty_months: number
  penalty_amount: number
}

export interface Completion {
  project_id: string
  approved_completion_date: string
  contractor_declared_at: string | null
  supervisor_report_due: string
  supervisor_report_at: string | null
  certificate_due: string | null
  certificate_issued_at: string | null
  actual_completion_date: string | null
  tests_completed: boolean
  defects_found: boolean
  defects_severity: 'epousiodes' | 'ousiodes' | null
  deemed_issued: boolean
}

export interface DeadlineWatchRow {
  project_id: string
  project_code: string
  project_title: string
  stage_code: string
  stage_title: string
  responsible: string
  status: StageStatus
  due_date: string | null
  days_left: number | null
  alert_level: 'ok' | 'no_deadline' | 'overdue' | 'critical' | 'warning'
  legal_ref_id: string | null
  tacit_approval: boolean
  tacit_effect: string | null
}

export interface LegalRef {
  id: string
  law: string
  article: string
  paragraph: string | null
  title: string
}

export interface DocumentRow {
  id: string
  project_id: string
  doc_code: string
  title: string
  protocol_no: string | null
  protocol_date: string | null
  ada: string | null
  status: string
  created_at: string
}
