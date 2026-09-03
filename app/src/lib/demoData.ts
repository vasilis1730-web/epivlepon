/**
 * ΔΟΚΙΜΑΣΤΙΚΑ ΔΕΔΟΜΕΝΑ ΕΠΙΔΕΙΞΗΣ
 * Χρησιμοποιούνται μόνο όταν δεν έχουν οριστεί τα VITE_SUPABASE_* ώστε η
 * εφαρμογή να είναι άμεσα εκτελέσιμη. Τα στοιχεία είναι ΠΛΑΣΜΑΤΙΚΑ.
 */
import type {
  Ape, Completion, Contract, DiaryEntry, DocumentRow, FinalMeasurement,
  Guarantee, HiddenWorkNotice, Measurement, PaymentCertificate, Profile, Project,
} from './types'
import { addDays, addMonths, today } from './format'

export const DEMO_PROFILE: Profile = {
  id: 'demo-user',
  org_id: 'demo-org',
  full_name: 'Βασίλειος Διακολιός',
  email: 'epivlepon@example.gr',
  specialty: 'ΠΕ Μηχανολόγος Μηχανικός',
  roles: ['epivlepon', 'proistamenos_dy'],
}

export const DEMO_ORG = {
  id: 'demo-org',
  name: 'Δήμος Ρόδου',
  unit: 'Δ/νση Τεχνικών Έργων & Υποδομών',
}

const T = today()
const P1 = 'p-asfalt'
const P2 = 'p-sxoleio'
const P3 = 'p-ydrefsi'

export const DEMO_PROJECTS: Project[] = [
  {
    id: P1, code: 'ΕΡΓ-2026-004',
    title: 'Ασφαλτοστρώσεις οδών Δ.Ε. Ιαλυσού',
    category: 'odopoiia', location: 'Δ.Ε. Ιαλυσού, Ρόδος',
    funding_source: 'ΣΑΤΑ 2026', study_budget_net: 620_000, estimated_value_net: 620_000,
  },
  {
    id: P2, code: 'ΕΡΓ-2025-011',
    title: 'Ενεργειακή αναβάθμιση 3ου Δημοτικού Σχολείου Ρόδου',
    category: 'hlektromichanologika', location: 'Ρόδος, οδός Καναδά',
    funding_source: 'Πρόγραμμα «ΗΛΕΚΤΡΑ»', study_budget_net: 410_000, estimated_value_net: 410_000,
  },
  {
    id: P3, code: 'ΕΡΓ-2026-007',
    title: 'Αντικατάσταση δικτύου ύδρευσης Τ.Κ. Αρχαγγέλου',
    category: 'ydraulika', location: 'Τ.Κ. Αρχαγγέλου, Ρόδος',
    funding_source: 'Ίδιοι πόροι', study_budget_net: 1_250_000, estimated_value_net: 1_250_000,
  },
]

export const DEMO_CONTRACTS: Record<string, Contract> = {
  [P1]: {
    project_id: P1, contractor_name: 'ΟΔΟΤΕΧΝΙΚΗ ΔΩΔΕΚΑΝΗΣΟΥ Α.Ε.', contractor_afm: '094512376',
    contract_no: '4471/2026', signed_at: addDays(T, -210),
    discount_pct: 38.5, initial_value_net: 381_300, contingency_pct: 15, contingency_amount: 49_735,
    vat_rate: 24, total_duration_days: 300,
    original_end_date: addDays(T, 90), current_end_date: addDays(T, 90),
    works_start_deadline: addDays(T, -180), maintenance_months: 15,
    supervision_mode: 'ypiresiaki', diary_mode: 'imerisio', diary_penalty_per_day: 200,
    status: 'active',
  },
  [P2]: {
    project_id: P2, contractor_name: 'ΕΝΕΡΓΕΙΑΚΗ ΚΑΤΑΣΚΕΥΑΣΤΙΚΗ Ο.Ε.', contractor_afm: '800345612',
    contract_no: '2210/2025', signed_at: addDays(T, -520),
    discount_pct: 22.0, initial_value_net: 319_800, contingency_pct: 15, contingency_amount: 41_713,
    vat_rate: 24, total_duration_days: 270,
    original_end_date: addDays(T, -250), current_end_date: addDays(T, -190),
    works_start_deadline: addDays(T, -495), maintenance_months: 15,
    supervision_mode: 'ypiresiaki', diary_mode: 'imerisio', diary_penalty_per_day: 150,
    status: 'active',
  },
  [P3]: {
    project_id: P3, contractor_name: 'ΥΔΡΟΔΟΜΗ ΤΕΧΝΙΚΗ Α.Τ.Ε.', contractor_afm: '997654321',
    contract_no: '5902/2026', signed_at: addDays(T, -18),
    discount_pct: 31.2, initial_value_net: 860_000, contingency_pct: 9, contingency_amount: 77_400,
    vat_rate: 24, total_duration_days: 420,
    original_end_date: addDays(T, 402), current_end_date: addDays(T, 402),
    works_start_deadline: addDays(T, 12), maintenance_months: 15,
    supervision_mode: 'ypiresiaki', diary_mode: 'imerisio', diary_penalty_per_day: 300,
    status: 'active',
  },
}

/** Στάδια που έχουν ολοκληρωθεί ανά έργο (τα υπόλοιπα υπολογίζονται). */
export const DEMO_COMPLETED_STAGES: Record<string, string[]> = {
  [P1]: [
    'S00_FAKELOS', 'S01_ORISMOS', 'S02_GNOSTOPOIHSH', 'S03_EGGYHSEIS', 'S04_TEXNIKOI',
    'S05_ELEGXOS_MELETHS', 'S06_XRONODIAGRAMMA', 'S07_ORGANOGRAMMA', 'S08_PPE',
    'S09_SAY_FAY', 'S10_EGKATASTASH', 'S13_YLIKA', 'S14_POIOTIKOI', 'S18_TRIMHNIAIES',
  ],
  [P2]: [
    'S00_FAKELOS', 'S01_ORISMOS', 'S02_GNOSTOPOIHSH', 'S03_EGGYHSEIS', 'S04_TEXNIKOI',
    'S05_ELEGXOS_MELETHS', 'S06_XRONODIAGRAMMA', 'S07_ORGANOGRAMMA', 'S08_PPE',
    'S09_SAY_FAY', 'S10_EGKATASTASH', 'S12_HMEROLOGIO', 'S13_YLIKA', 'S14_POIOTIKOI',
    'S15_PPAE', 'S16_EPIMETRHSEIS', 'S17_LOGARIASMOI', 'S18_TRIMHNIAIES', 'S19_APE',
    'S20_PARATASEIS', 'S24_DHLWSH_PERAIWSHS', 'S25_EKTHESI_EPIVL', 'S26_BEBAIWSH',
    'S27_TELIKH_EPIM', 'S28_MEIWSH_EGG',
  ],
  [P3]: ['S00_FAKELOS', 'S01_ORISMOS', 'S02_GNOSTOPOIHSH', 'S03_EGGYHSEIS'],
}

/** Στάδια υπό αίρεση που δεν έχουν αντικείμενο στη συγκεκριμένη σύμβαση. */
export const DEMO_NA_STAGES: Record<string, string[]> = {
  [P1]: ['S11_PROKATAVOLH', 'S21_ANWTERA_BIA', 'S22_POINIKES', 'S23_ENSTASEIS'],
  [P2]: ['S11_PROKATAVOLH', 'S21_ANWTERA_BIA', 'S22_POINIKES', 'S23_ENSTASEIS'],
  [P3]: ['S11_PROKATAVOLH', 'S21_ANWTERA_BIA', 'S22_POINIKES', 'S23_ENSTASEIS'],
}

/** Στάδια σε εξέλιξη ανά έργο. */
export const DEMO_INPROGRESS_STAGES: Record<string, string[]> = {
  [P1]: ['S12_HMEROLOGIO', 'S15_PPAE', 'S16_EPIMETRHSEIS', 'S17_LOGARIASMOI', 'S19_APE'],
  [P2]: ['S29_SYNTHRHSH'],
  [P3]: ['S04_TEXNIKOI', 'S05_ELEGXOS_MELETHS', 'S06_XRONODIAGRAMMA'],
}

/* ---------------- Χρονοδιαγράμματα ---------------- */
export const DEMO_SCHEDULES: Record<string, {
  submitted_at: string | null; approved_at: string | null;
  deemed_approved: boolean; method: 'diktyoti_analysi' | 'grammiko' | null
  approval_due: string | null
}> = {
  [P1]: { submitted_at: addDays(T, -190), approved_at: addDays(T, -180), deemed_approved: false, method: 'grammiko', approval_due: addDays(T, -175) },
  [P2]: { submitted_at: addDays(T, -500), approved_at: addDays(T, -492), deemed_approved: false, method: 'grammiko', approval_due: addDays(T, -485) },
  [P3]: { submitted_at: addDays(T, -3), approved_at: null, deemed_approved: false, method: 'grammiko', approval_due: addDays(T, 12) },
}

/* ---------------- Εγγυήσεις ---------------- */
export const DEMO_GUARANTEES: Guarantee[] = [
  {
    id: 'g1', project_id: P1, gtype: 'kalis_ektelesis', issuer: 'Τ.Μ.Ε.Δ.Ε.',
    guarantee_no: 'ΕΕ-2026-1187', issued_at: addDays(T, -215),
    original_amount: 19_065, current_amount: 19_065, pct_of_contract: 5, status: 'energi', events: [],
  },
  {
    id: 'g2', project_id: P2, gtype: 'kalis_ektelesis', issuer: 'Τράπεζα Πειραιώς',
    guarantee_no: 'ΕΕ-2025-0442', issued_at: addDays(T, -525),
    original_amount: 15_990, current_amount: 4_797, pct_of_contract: 5, status: 'meiomeni_70',
    events: [{
      id: 'ge1', event_type: 'meiosi_70', amount_before: 15_990, amount_after: 4_797,
      trigger_event: 'egkrisi_telikis_epimetrisis', decision_date: addDays(T, -60),
    }],
  },
  {
    id: 'g3', project_id: P3, gtype: 'kalis_ektelesis', issuer: 'Τ.Μ.Ε.Δ.Ε.',
    guarantee_no: 'ΕΕ-2026-2031', issued_at: addDays(T, -20),
    original_amount: 43_000, current_amount: 43_000, pct_of_contract: 5, status: 'energi', events: [],
  },
]

/* ---------------- Ημερολόγιο ---------------- */
function buildDiary(projectId: string, fromOffset: number, gaps: number[]): DiaryEntry[] {
  const out: DiaryEntry[] = []
  let n = 0
  for (let i = fromOffset; i <= 0; i++) {
    const d = addDays(T, i)
    const dow = new Date(d + 'T00:00:00').getDay()
    if (dow === 0 || dow === 6) continue
    n++
    if (gaps.includes(n)) continue
    out.push({
      id: `${projectId}-d${n}`, project_id: projectId, entry_date: d,
      weather: ['aithria', 'aithria', 'nefosi', 'vrochi'][n % 4],
      personnel: [
        { eidikotita: 'Εργοδηγός', arithmos: 1 },
        { eidikotita: 'Τεχνίτες', arithmos: 3 + (n % 3) },
        { eidikotita: 'Εργάτες', arithmos: 4 + (n % 2) },
      ],
      equipment: [
        { michanima: 'Φορτωτής JCB', ores: 6 },
        { michanima: 'Οδοστρωτήρας', ores: n % 2 ? 5 : 0 },
      ],
      works_description:
        n % 3 === 0
          ? 'Εκσκαφές και διαμόρφωση σκάφης στο τμήμα Χ.Θ. 0+120 έως 0+310.'
          : n % 3 === 1
            ? 'Διάστρωση και συμπύκνωση υπόβασης οδοστρωσίας, πάχους 10 cm.'
            : 'Κατασκευή φρεατίων υδροσυλλογής και τοποθέτηση σχαρών.',
      delay_reasons: n % 11 === 0 ? 'Διακοπή λόγω βροχόπτωσης από 11:00.' : null,
      accidents: null,
      supervisor_orders: n % 7 === 0 ? 'Εντολή επίβλεψης για δειγματοληψία αδρανών.' : null,
      status: i > -4 ? 'submitted' : 'approved',
      submitted_at: d + 'T17:30:00',
      reviewed_at: i > -4 ? null : d + 'T09:00:00',
      approved_at: i > -4 ? null : addDays(d, 1) + 'T10:00:00',
    })
  }
  return out
}

export const DEMO_DIARY: Record<string, DiaryEntry[]> = {
  [P1]: buildDiary(P1, -45, [7, 8, 19, 33]),   // 4 κενές ημέρες → ρήτρα
  [P2]: buildDiary(P2, -20, []),
  [P3]: [],
}

/* ---------------- Αφανείς εργασίες ---------------- */
export const DEMO_HIDDEN: HiddenWorkNotice[] = [
  {
    id: 'h1', project_id: P1, serial_no: 1,
    work_description: 'Εξυγιαντική στρώση θραυστού υλικού πάχους 30 cm',
    location: 'Οδός Ηρακλειδών, Χ.Θ. 0+000 – 0+180',
    declaration_at: addDays(T, -40), invitation_sent_at: addDays(T, -40),
    inspection_due: addDays(T, -37), inspected_at: addDays(T, -38),
    supervisor_report_at: addDays(T, -38), photos_count: 12, covered_at: addDays(T, -37),
    approval_due: addDays(T, -8), approved_at: addDays(T, -20), status: 'approved',
  },
  {
    id: 'h2', project_id: P1, serial_no: 2,
    work_description: 'Υπόβαση οδοστρωσίας 3Α, δύο στρώσεις 10 cm',
    location: 'Οδός Φιλερήμου, Χ.Θ. 0+180 – 0+420',
    declaration_at: addDays(T, -12), invitation_sent_at: addDays(T, -12),
    inspection_due: addDays(T, -9), inspected_at: addDays(T, -10),
    supervisor_report_at: addDays(T, -10), photos_count: 8, covered_at: addDays(T, -9),
    approval_due: addDays(T, 18), approved_at: null, status: 'measured',
  },
  {
    id: 'h3', project_id: P1, serial_no: 3,
    work_description: 'Σωληνώσεις αποστράγγισης Φ200 σε τάφρο',
    location: 'Οδός Ιαλυσού, Χ.Θ. 0+420 – 0+540',
    declaration_at: addDays(T, -6), invitation_sent_at: addDays(T, -6),
    inspection_due: addDays(T, -3), inspected_at: null,
    supervisor_report_at: null, photos_count: 0, covered_at: null,
    approval_due: null, approved_at: null, status: 'declared',
  },
]

/* ---------------- Επιμετρήσεις ---------------- */
export const DEMO_MEASUREMENTS: Measurement[] = [
  ...Array.from({ length: 6 }, (_, i) => ({
    id: `m${i + 1}`, project_id: P1, mtype: 'tmimatiki' as const, serial_no: i + 1,
    period_from: addDays(T, -180 + i * 28), period_to: addDays(T, -153 + i * 28),
    work_section: ['Χωματουργικά', 'Τεχνικά έργα', 'Οδοστρωσία'][i % 3],
    submitted_at: addDays(T, -150 + i * 28), truth_declaration: true,
    status: (i < 5 ? 'approved' : 'submitted') as Measurement['status'],
    selected_for_audit: i < 3, audited: i < 3,
    approval_due: addDays(T, -120 + i * 28),
    approved_at: i < 5 ? addDays(T, -140 + i * 28) : null,
    contractual_amount: 38_000 + i * 4_200, extra_amount: i === 4 ? 3_100 : 0,
    total_amount: 38_000 + i * 4_200 + (i === 4 ? 3_100 : 0),
  })),
  {
    id: 'm-p2-final', project_id: P2, mtype: 'teliki', serial_no: 1,
    period_from: null, period_to: null, work_section: null,
    submitted_at: addDays(T, -150), truth_declaration: true, status: 'approved',
    selected_for_audit: true, audited: true,
    approval_due: addDays(T, -90), approved_at: addDays(T, -95),
    contractual_amount: 331_400, extra_amount: 0, total_amount: 331_400,
  },
]

/* ---------------- Λογαριασμοί ---------------- */
export const DEMO_PAYMENTS: PaymentCertificate[] = [
  ...Array.from({ length: 4 }, (_, i) => {
    const gross = 46_000 + i * 41_000
    const prev = i === 0 ? 0 : 46_000 + (i - 1) * 41_000
    const retentions = Math.round((gross * 0.05 - (i === 0 ? 0 : prev * 0.05)) * 100) / 100
    const period = gross - prev
    const net = Math.round((period - retentions) * 100) / 100
    return {
      id: `pc${i + 1}`, project_id: P1, ptype: 'tmimatikos' as const, serial_no: i + 1,
      period_from: addDays(T, -180 + i * 40), period_to: addDays(T, -145 + i * 40),
      measurement_id: `m${i + 1}`,
      submitted_at: addDays(T, -140 + i * 40),
      approval_due: addMonths(addDays(T, -140 + i * 40), 1),
      approved_at: i < 3 ? addDays(T, -125 + i * 40) : null,
      status: (i < 3 ? 'approved' : 'submitted') as PaymentCertificate['status'],
      gross_cumulative: gross, previous_certified: prev, period_amount: period,
      advance_amortization: 0, penalties_amount: 0, retentions_amount: retentions,
      net_payable: net, vat_amount: Math.round(net * 0.24 * 100) / 100,
      has_summary_table: true, has_revision_calc: i > 0,
      paid_at: i < 3 ? addDays(T, -110 + i * 40) : null,
    }
  }),
]

/* Λογαριασμοί έργου Π2 — πιστοποιήθηκε το σύνολο, ο τελικός εκκρεμεί */
DEMO_PAYMENTS.push(
  ...Array.from({ length: 5 }, (_, i) => {
    const gross = Math.round((341_600 / 5) * (i + 1))
    const prev = i === 0 ? 0 : Math.round((341_600 / 5) * i)
    const retentions = Math.round((gross * 0.05 - prev * 0.05) * 100) / 100
    const period = gross - prev
    const net = Math.round((period - retentions) * 100) / 100
    return {
      id: `pc-p2-${i + 1}`, project_id: P2, ptype: 'tmimatikos' as const, serial_no: i + 1,
      period_from: addDays(T, -480 + i * 60), period_to: addDays(T, -425 + i * 60),
      measurement_id: null,
      submitted_at: addDays(T, -420 + i * 60),
      approval_due: addMonths(addDays(T, -420 + i * 60), 1),
      approved_at: addDays(T, -405 + i * 60),
      status: 'paid' as const,
      gross_cumulative: gross, previous_certified: prev, period_amount: period,
      advance_amortization: 0, penalties_amount: 0, retentions_amount: retentions,
      net_payable: net, vat_amount: Math.round(net * 0.24 * 100) / 100,
      has_summary_table: true, has_revision_calc: true,
      paid_at: addDays(T, -390 + i * 60),
    }
  }),
)

/* ---------------- ΑΠΕ ---------------- */
export const DEMO_APES: Ape[] = [
  {
    id: 'ape1', project_id: P1, serial_no: 1, atype: 'me_epi_elasson',
    reason:
      'Μείωση ποσοτήτων χωματουργικών λόγω ευνοϊκότερων εδαφικών συνθηκών και ενίσχυση ασφαλτικών στρώσεων.',
    drafted_at: addDays(T, -15),
    initial_contract_value: 381_300, new_total_value: 381_300, delta_amount: 0,
    contingency_used: 0, savings_used: 62_000, supplementary_needed: false,
    tc_opinion_id: null, contractor_signature: null, status: 'draft', approved_at: null,
    lines: [
      {
        id: 'al1', work_group: 'Χωματουργικά - Καθαιρέσεις', item_code: 'ΝΕΤ ΟΔΟ Α-2',
        description: 'Γενικές εκσκαφές σε έδαφος γαιώδες', unit: 'm³',
        unit_price: 4.2, qty_initial: 22_000, qty_new: 7_240,
        amount_initial: 92_400, amount_new: 30_408, delta_amount: -61_992,
        funding_source: 'epi_elasson', is_new_item: false,
      },
      {
        id: 'al2', work_group: 'Ασφαλτικά', item_code: 'ΝΕΤ ΟΔΟ Δ-8',
        description: 'Ασφαλτική στρώση κυκλοφορίας 5 cm', unit: 'm²',
        unit_price: 8.9, qty_initial: 14_000, qty_new: 20_965,
        amount_initial: 124_600, amount_new: 186_589, delta_amount: 61_989,
        funding_source: 'epi_elasson', is_new_item: false,
      },
    ],
  },
  {
    id: 'ape-p2-1', project_id: P2, serial_no: 1, atype: 'me_apravlepta',
    reason: 'Απρόβλεπτη αντικατάσταση φθαρμένων ηλεκτρολογικών πινάκων.',
    drafted_at: addDays(T, -330),
    initial_contract_value: 319_800, new_total_value: 341_600, delta_amount: 21_800,
    contingency_used: 21_800, savings_used: 0, supplementary_needed: false,
    tc_opinion_id: 'tc-1', contractor_signature: 'anepifylakta',
    status: 'approved', approved_at: addDays(T, -310),
    lines: [
      {
        id: 'al3', work_group: 'Ηλεκτρικές εγκαταστάσεις ισχυρών ρευμάτων',
        item_code: 'ΑΤΗΕ 8840.2', description: 'Ηλεκτρικός πίνακας διανομής',
        unit: 'τεμ.', unit_price: 2_180, qty_initial: 0, qty_new: 10,
        amount_initial: 0, amount_new: 21_800, delta_amount: 21_800,
        funding_source: 'apravlepta', is_new_item: false,
      },
    ],
  },
]

/* ---------------- Περαίωση & τελική επιμέτρηση ---------------- */
export const DEMO_COMPLETIONS: Record<string, Completion> = {
  [P2]: {
    project_id: P2, approved_completion_date: addDays(T, -190),
    contractor_declared_at: addDays(T, -195),
    supervisor_report_due: addDays(T, -160), supervisor_report_at: addDays(T, -178),
    certificate_due: addDays(T, -168), certificate_issued_at: addDays(T, -172),
    actual_completion_date: addDays(T, -192), tests_completed: true,
    defects_found: false, defects_severity: null, deemed_issued: false,
  },
}

export const DEMO_FINAL_MEASUREMENTS: Record<string, FinalMeasurement> = {
  [P2]: {
    project_id: P2, completion_date: addDays(T, -192),
    contractor_due: addMonths(addDays(T, -192), 2), submitted_at: addDays(T, -150),
    supervisor_report_due: addMonths(addDays(T, -150), 2), supervisor_report_at: addDays(T, -120),
    approval_due: addMonths(addDays(T, -120), 2), approved_at: addDays(T, -95),
    penalty_months: 0, penalty_amount: 0,
  },
}

export const DEMO_ACCEPTANCE: Record<string, {
  maintenance_end: string; deadline_3m: string; committee_size: number
  protocol_date: string | null; approved_at: string | null
}> = {
  [P2]: {
    maintenance_end: addMonths(addDays(T, -172), 15),
    deadline_3m: addMonths(addMonths(addDays(T, -172), 15), 3),
    committee_size: 0, protocol_date: null, approved_at: null,
  },
}

/* ---------------- Έγγραφα ---------------- */
export const DEMO_DOCUMENTS: DocumentRow[] = [
  { id: 'doc1', project_id: P1, doc_code: 'APOFASI_ORISMOU', title: 'Απόφαση ορισμού επιβλέποντος', protocol_no: '4512', protocol_date: addDays(T, -208), ada: 'ΨΞ4Ρ7ΛΞ-9ΒΔ', status: 'approved', created_at: addDays(T, -208) },
  { id: 'doc2', project_id: P1, doc_code: 'XRONODIAGRAMMA', title: 'Χρονοδιάγραμμα κατασκευής', protocol_no: '4780', protocol_date: addDays(T, -190), ada: null, status: 'approved', created_at: addDays(T, -190) },
  { id: 'doc3', project_id: P1, doc_code: 'EGKRISI_XRONOD', title: 'Απόφαση έγκρισης χρονοδιαγράμματος', protocol_no: '4881', protocol_date: addDays(T, -180), ada: 'ΩΒ5Φ7ΛΞ-2ΚΩ', status: 'approved', created_at: addDays(T, -180) },
  { id: 'doc4', project_id: P1, doc_code: 'PPAE', title: 'Έκθεση παραλαβής αφανών εργασιών Νο 1', protocol_no: '6120', protocol_date: addDays(T, -38), ada: null, status: 'approved', created_at: addDays(T, -38) },
  { id: 'doc5', project_id: P1, doc_code: 'LOGARIASMOS', title: '3ος Λογαριασμός', protocol_no: '6440', protocol_date: addDays(T, -60), ada: null, status: 'approved', created_at: addDays(T, -60) },
  { id: 'doc6', project_id: P2, doc_code: 'BEBAIOSI_PERATOSIS', title: 'Βεβαίωση Περάτωσης Εργασιών', protocol_no: '1180', protocol_date: addDays(T, -172), ada: 'Ρ7Ξ2ΩΛΞ-Θ5Μ', status: 'approved', created_at: addDays(T, -172) },
  { id: 'doc7', project_id: P2, doc_code: 'EGKRISI_TELIKHS_EPIM', title: 'Πράξη έγκρισης τελικής επιμέτρησης', protocol_no: '1355', protocol_date: addDays(T, -95), ada: 'ΩΔ3Ν8ΛΞ-Π1Χ', status: 'approved', created_at: addDays(T, -95) },
  { id: 'doc8', project_id: P2, doc_code: 'PRAXH_MEIWSHS_EGG', title: 'Πράξη μείωσης εγγύησης καλής εκτέλεσης κατά 70%', protocol_no: '1402', protocol_date: addDays(T, -60), ada: 'ΨΛ9Κ4ΛΞ-Ζ7Τ', status: 'approved', created_at: addDays(T, -60) },
  { id: 'doc9', project_id: P3, doc_code: 'APOFASI_ORISMOU', title: 'Απόφαση ορισμού επιβλέποντος', protocol_no: '7701', protocol_date: addDays(T, -15), ada: 'ΨΥ2Β6ΛΞ-Ν4Ρ', status: 'approved', created_at: addDays(T, -15) },
]
