/**
 * Τα μεγέθη μιας νέας σύμβασης έργου.
 *
 * Οι ίδιοι υπολογισμοί εκτελούνται και στη βάση (public.create_project_full).
 * Εδώ υπάρχουν ώστε η φόρμα να δείχνει ζωντανά τι θα καταχωριστεί — η βάση
 * παραμένει η αυθεντία, το UI απλώς προεπισκοπεί.
 */
import type { ProjectCategory } from './types'
import { addDays } from './format'

export interface NewProjectInput {
  project: {
    code: string
    title: string
    category: ProjectCategory
    location: string
    funding_source: string
    ka_budget_code: string
    cpv: string
    mis_code: string
    adam_tender: string
    award_decision_ada: string
  }
  contractor: {
    id: string | null
    name: string
    afm: string
    doy: string
    legal_form: string
    meep_mieedde: string
    legal_rep_name: string
    address: string
    email: string
    phone: string
  }
  contract: {
    contract_no: string
    signed_at: string
    ada_contract: string
    adam_contract: string
    regime: 'n4412_meta_n4782' | 'n4412_pro_n4782'
    supervision_mode: 'ypiresiaki' | 'ife' | 'mikti'
    budget_works_net: number
    discount_pct: number
    ge_oe_pct: number
    contingency_pct: 9 | 15
    revision_amount: number
    vat_rate: number
    total_duration_days: number
    schedule_submit_days: number
    maintenance_months: number
    diary_mode: 'imerisio' | 'evdomadiaio' | 'apallagi'
    diary_penalty_per_day: number
  }
  assignments: {
    epivlepon: string
    epivlepon_is_coordinator: boolean
    voithoi: string[]
    proistamenos_dy: string
    decision_no: string
    decision_date: string
    decision_ada: string
    duties: string
  }
  guarantee: {
    issuer: string
    guarantee_no: string
    issued_at: string
    original_amount: number
    valid_to: string
  }
}

export interface Derived {
  worksAfterDiscount: number
  geOe: number
  contingency: number
  initialValueNet: number
  vatAmount: number
  totalWithVat: number
  studyBudgetNet: number
  /** Εγγύηση καλής εκτέλεσης 5% επί της αρχικής αξίας (άρθρο 72 §4) */
  guaranteeExpected: number
  originalEndDate: string | null
  oriakiEndDate: string | null
  scheduleDueDate: string | null
  scheduleApprovalDue: string | null
  worksStartDue: string | null
  maintenanceUntilNote: string
}

const r2 = (n: number) => Math.round(n * 100) / 100

export function derive(c: NewProjectInput['contract']): Derived {
  const base = Number.isFinite(c.budget_works_net) ? c.budget_works_net : 0
  const worksAfterDiscount = r2(base * (1 - (c.discount_pct || 0) / 100))
  const geOe = r2(worksAfterDiscount * (c.ge_oe_pct || 0) / 100)
  const contingency = r2((worksAfterDiscount + geOe) * (c.contingency_pct || 0) / 100)
  const initialValueNet = r2(worksAfterDiscount + geOe + contingency + (c.revision_amount || 0))
  const vatAmount = r2(initialValueNet * (c.vat_rate || 0) / 100)

  const studyGeOe = r2(base * (c.ge_oe_pct || 0) / 100)
  const studyBudgetNet = r2(
    base + studyGeOe + (base + studyGeOe) * (c.contingency_pct || 0) / 100 + (c.revision_amount || 0),
  )

  const signed = /^\d{4}-\d{2}-\d{2}$/.test(c.signed_at) ? c.signed_at : null
  const days = c.total_duration_days > 0 ? c.total_duration_days : null

  const originalEndDate = signed && days ? addDays(signed, days) : null
  // Άρθρο 147 §4: οριακή προθεσμία = το ήμισυ της αρχικής, τουλάχιστον 3 μήνες.
  const oriakiEndDate =
    originalEndDate && days ? addDays(originalEndDate, Math.max(Math.floor(days / 2), 90)) : null

  // Άρθρο 145 §1: υποβολή χρονοδιαγράμματος 15-30 ημέρες από την υπογραφή.
  const scheduleDueDate = signed ? addDays(signed, c.schedule_submit_days || 15) : null
  // §2: έγκριση εντός 15 ημερών (άλλως τεκμαίρεται) και έναρξη εντός 30 ημερών.
  const scheduleApprovalDue = scheduleDueDate ? addDays(scheduleDueDate, 15) : null
  const worksStartDue = scheduleApprovalDue ? addDays(scheduleApprovalDue, 30) : null

  return {
    worksAfterDiscount, geOe, contingency, initialValueNet, vatAmount,
    totalWithVat: r2(initialValueNet + vatAmount),
    studyBudgetNet,
    guaranteeExpected: r2(initialValueNet * 0.05),
    originalEndDate, oriakiEndDate, scheduleDueDate, scheduleApprovalDue, worksStartDue,
    maintenanceUntilNote:
      `${c.maintenance_months} μήνες από την επομένη της Βεβαίωσης Περάτωσης`,
  }
}

/** Έλεγχοι που πρέπει να περάσουν πριν σταλεί η φόρμα. */
export function validate(v: NewProjectInput): string[] {
  const e: string[] = []
  const t = (s: string) => s.trim().length > 0

  if (!t(v.project.code)) e.push('Ο κωδικός του έργου είναι υποχρεωτικός.')
  if (!t(v.project.title)) e.push('Ο τίτλος του έργου είναι υποχρεωτικός.')

  if (!v.contractor.id) {
    if (!t(v.contractor.name)) e.push('Η επωνυμία του αναδόχου είναι υποχρεωτική.')
    if (!/^\d{9}$/.test(v.contractor.afm.trim()))
      e.push('Το ΑΦΜ του αναδόχου πρέπει να έχει ακριβώς 9 ψηφία.')
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.contractor.email.trim()))
      e.push('Απαιτείται έγκυρη διεύθυνση ηλεκτρονικού ταχυδρομείου του αναδόχου για τις κοινοποιήσεις (άρθρο 143).')
  }

  if (!t(v.contract.contract_no)) e.push('Ο αριθμός της σύμβασης είναι υποχρεωτικός.')
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v.contract.signed_at))
    e.push('Απαιτείται η ημερομηνία υπογραφής της σύμβασης.')
  if (!(v.contract.budget_works_net > 0))
    e.push('Η δαπάνη εργασιών του προϋπολογισμού μελέτης πρέπει να είναι θετική.')
  if (v.contract.discount_pct < 0 || v.contract.discount_pct >= 100)
    e.push('Η έκπτωση πρέπει να είναι από 0 έως και κάτω του 100%.')
  if (![9, 15].includes(v.contract.contingency_pct))
    e.push('Τα απρόβλεπτα ορίζονται σε 9% ή 15% (άρθρο 156 §3β).')
  if (!(v.contract.total_duration_days > 0))
    e.push('Η συνολική προθεσμία πρέπει να είναι θετικός αριθμός ημερών (άρθρο 147 §1).')
  if (v.contract.schedule_submit_days < 15 || v.contract.schedule_submit_days > 30)
    e.push('Η προθεσμία υποβολής χρονοδιαγράμματος ορίζεται από 15 έως 30 ημέρες (άρθρο 145 §1).')
  if (v.contract.diary_mode !== 'apallagi' &&
      (v.contract.diary_penalty_per_day < 100 || v.contract.diary_penalty_per_day > 500))
    e.push('Η ειδική ποινική ρήτρα ημερολογίου ορίζεται από 100 έως 500 € ανά ημέρα (άρθρο 146).')
  if (v.contract.supervision_mode === 'ife')
    e.push('Η επίβλεψη από Ιδιωτικό Φορέα Επίβλεψης απαιτεί καταχώριση του πιστοποιημένου φορέα· '
         + 'δημιουργήστε το έργο με υπηρεσιακή επίβλεψη και μεταβάλετέ το κατόπιν (άρθρο 136 §3).')

  if (!t(v.assignments.epivlepon))
    e.push('Πρέπει να οριστεί επιβλέπων μηχανικός (άρθρο 136 §2).')

  const g = v.guarantee
  if (t(g.guarantee_no) || t(g.issuer) || g.original_amount > 0) {
    if (!t(g.guarantee_no)) e.push('Συμπληρώστε τον αριθμό της εγγυητικής επιστολής.')
    if (!t(g.issuer)) e.push('Συμπληρώστε τον εκδότη της εγγυητικής επιστολής.')
    if (!(g.original_amount > 0)) e.push('Συμπληρώστε το ποσό της εγγυητικής επιστολής.')
  }
  return e
}

export function emptyInput(): NewProjectInput {
  const t = new Date().toISOString().slice(0, 10)
  return {
    project: {
      code: '', title: '', category: 'odopoiia', location: '', funding_source: '',
      ka_budget_code: '', cpv: '', mis_code: '', adam_tender: '', award_decision_ada: '',
    },
    contractor: {
      id: null, name: '', afm: '', doy: '', legal_form: '', meep_mieedde: '',
      legal_rep_name: '', address: '', email: '', phone: '',
    },
    contract: {
      contract_no: '', signed_at: t, ada_contract: '', adam_contract: '',
      regime: 'n4412_meta_n4782', supervision_mode: 'ypiresiaki',
      budget_works_net: 0, discount_pct: 0, ge_oe_pct: 18, contingency_pct: 15,
      revision_amount: 0, vat_rate: 24, total_duration_days: 365,
      schedule_submit_days: 15, maintenance_months: 15,
      diary_mode: 'imerisio', diary_penalty_per_day: 100,
    },
    assignments: {
      epivlepon: '', epivlepon_is_coordinator: false, voithoi: [],
      proistamenos_dy: '', decision_no: '', decision_date: '', decision_ada: '', duties: '',
    },
    guarantee: { issuer: '', guarantee_no: '', issued_at: '', original_amount: 0, valid_to: '' },
  }
}
