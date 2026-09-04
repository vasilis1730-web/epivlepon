/**
 * ΝΟΜΙΚΟΙ ΚΑΝΟΝΕΣ — ν. 4412/2016 όπως ισχύει (ν. 4782/2021)
 *
 * Οι ίδιοι κανόνες υλοποιούνται ΚΑΙ στη βάση (triggers/constraints), η οποία
 * είναι η τελική αρχή. Εδώ αναπαράγονται ώστε το περιβάλλον χρήστη να μπορεί
 * να εξηγήσει ΕΚ ΤΩΝ ΠΡΟΤΕΡΩΝ γιατί μια ενέργεια δεν επιτρέπεται, αντί να
 * περιμένει σφάλμα από τον διακομιστή.
 */
import type {
  Ape, Blocker, Contract, DiaryEntry, FinalMeasurement, Measurement,
  PaymentCertificate, Completion, Guarantee,
} from './types'
import { daysUntil, today, workingDaysBetween } from './format'

/* ------------------------------------------------------------------ */
/* Άρθρο 151 §3 — δειγματοληπτικός έλεγχος επιμετρήσεων                */
/* ------------------------------------------------------------------ */
export function requiredAuditCount(submittedCount: number): number {
  if (submittedCount === 0) return 0
  if (submittedCount < 10) return Math.min(4, submittedCount)
  return Math.ceil(submittedCount * 0.4)
}

/* ------------------------------------------------------------------ */
/* Άρθρο 146 — ημέρες χωρίς εγγραφή ημερολογίου                        */
/* ------------------------------------------------------------------ */
export function missingDiaryDays(
  entries: DiaryEntry[],
  fromIso: string,
  toIso: string = today(),
): string[] {
  const present = new Set(entries.map(e => e.entry_date))
  return workingDaysBetween(fromIso, toIso).filter(d => !present.has(d))
}

export function diaryPenalty(missingDays: number, perDay: number): number {
  return Math.round(missingDays * perDay * 100) / 100
}

/* ------------------------------------------------------------------ */
/* Άρθρο 156 — έλεγχος ορίων ΑΠΕ                                       */
/* ------------------------------------------------------------------ */
export function apeViolations(
  ape: Ape,
  contract: Contract,
  otherApprovedApes: Ape[] = [],
): Blocker[] {
  const out: Blocker[] = []
  const base = contract.initial_value_net

  // ΣΥΝΟΛΟ 1 της σύμβασης: εργασίες + ΓΕ & ΟΕ, ΧΩΡΙΣ απρόβλεπτα. Είναι η
  // βάση των ορίων του άρθρου 156 §3γ — όχι η συνολική συμβατική αξία.
  const contractSubtotal1 = round2(base - contract.contingency_amount)

  const t = apeTotals(
    ape.lines.map(l => ({ ...l, qty_previous: l.qty_initial })),
    {
      geOePct: contract.ge_oe_pct ?? 18,
      contractWorksPlusGeOe: contractSubtotal1,
      contingencyAmount: contract.contingency_amount,
    },
  )

  // (1) Σωρευτικό όριο 50% (άρθρο 156 §1)
  const cumulative =
    otherApprovedApes.filter(a => a.delta_amount > 0).reduce((s, a) => s + a.delta_amount, 0) +
    Math.max(0, ape.delta_amount)
  if (base > 0 && cumulative > base * 0.5) {
    out.push({
      code: 'APE_LIMIT_50',
      severity: 'hard',
      legal_ref: 'N4412/156/1',
      message: `Υπέρβαση του ανώτατου ορίου 50%: σωρευτική αύξηση ${fmt(cumulative)} έναντι ορίου ${fmt(base * 0.5)}.`,
    })
  }

  // (2) Ισοζύγιο απροβλέπτων (άρθρο 156 §3β)
  if (t.contingencyOverrun) {
    out.push({
      code: 'APE_CONTINGENCY',
      severity: 'hard',
      legal_ref: 'N4412/156/3b',
      message:
        `Η αύξηση των εργασιών (${fmt(t.contingencyUsed)}) εξαντλεί το κονδύλιο ` +
        `απροβλέπτων ${contract.contingency_pct}% (${fmt(contract.contingency_amount)}) κατά ` +
        `${fmt(-t.contingencyRemaining)}. Ο ΑΠΕ δεν είναι σε ισοζύγιο: η διαφορά πρέπει να ` +
        'περάσει από το άρθρο 132 ή από συμπληρωματική σύμβαση.',
    })
  }

  /* --- Όρια 20% ανά ομάδα εργασιών (άρθρο 156 §3γ) ----------------- */
  const byGroup = new Map<string, { savings: number; increase: number; initial: number }>()
  for (const l of ape.lines) {
    if (l.is_article_132) continue
    const g = byGroup.get(l.work_group) ?? { savings: 0, increase: 0, initial: 0 }
    if (l.delta_amount < 0) g.savings += -l.delta_amount
    else g.increase += l.delta_amount
    g.initial += l.amount_initial
    byGroup.set(l.work_group, g)
  }

  for (const [group, g] of byGroup) {
    if (g.initial <= 0) continue

    // (3) Επί έλαττον ≤ 20% της δαπάνης της ομάδας
    if (g.savings > g.initial * 0.2) {
      out.push({
        code: `APE_SAVINGS_GROUP_20:${group}`,
        severity: 'hard',
        legal_ref: 'N4412/156/3c',
        message: `Ομάδα «${group}»: οι επί έλαττον δαπάνες (${fmt(g.savings)}) υπερβαίνουν το 20% της συμβατικής δαπάνης της ομάδας (${fmt(g.initial * 0.2)}).`,
      })
    }

    // (4) Επί ΠΛΕΟΝ καθ' υπέρβαση του 20% της ομάδας. Δεν απαγορεύεται
    // αυτοτελώς: η υπέρβαση πρέπει να καλύπτεται από τα χρησιμοποιηθέντα
    // απρόβλεπτα, αλλιώς συνιστά παρέκκλιση (φύλλο ελέγχου, Πίνακας 2).
    const overFifth = round2(g.increase - g.initial * 0.2)
    if (overFifth > 0 && overFifth > Math.max(0, t.contingencyUsed)) {
      out.push({
        code: `APE_INCREASE_GROUP_20:${group}`,
        severity: 'hard',
        legal_ref: 'N4412/156/3c',
        message:
          `Ομάδα «${group}»: οι επί πλέον δαπάνες υπερβαίνουν το 20% της ομάδας κατά ` +
          `${fmt(overFifth)}, ποσό που δεν καλύπτεται από τα χρησιμοποιηθέντα απρόβλεπτα ` +
          `(${fmt(Math.max(0, t.contingencyUsed))}).`,
      })
    }
  }

  // (5) Επί έλαττον ≤ 10% — βάση το ΣΥΝΟΛΟ 1 της σύμβασης (εργασίες + ΓΕ & ΟΕ)
  if (contractSubtotal1 > 0 && t.savings > contractSubtotal1 * 0.1) {
    out.push({
      code: 'APE_SAVINGS_TOTAL_10',
      severity: 'hard',
      legal_ref: 'N4412/156/3c',
      message: `Οι επί έλαττον δαπάνες (${fmt(t.savings)}) υπερβαίνουν το 10% του συνόλου εργασιών και ΓΕ & ΟΕ της σύμβασης (${fmt(contractSubtotal1 * 0.1)}).`,
    })
  }

  // (6) Εργασίες άρθρου 132 ≤ 15% της αξίας της αρχικής σύμβασης (§2)
  if (base > 0 && t.art132Total > base * 0.15) {
    out.push({
      code: 'APE_ART132_LIMIT_15',
      severity: 'hard',
      legal_ref: 'N4412/132/2',
      message: `Οι εργασίες του άρθρου 132 (${fmt(t.art132Total)}) υπερβαίνουν το 15% της αξίας της αρχικής σύμβασης (${fmt(base * 0.15)}).`,
    })
  }

  // (7) Απαγόρευση νέων άρθρων από επί έλασσον (άρθρο 156 §3γ)
  if (ape.lines.some(l => l.is_new_item && l.funding_source === 'epi_elasson')) {
    out.push({
      code: 'APE_NEW_ITEM_FROM_SAVINGS',
      severity: 'hard',
      legal_ref: 'N4412/156/3c',
      message:
        'Δεν επιτρέπεται η κάλυψη ΝΕΩΝ άρθρων (μη περιλαμβανομένων στην αρχική σύμβαση) από επί έλασσον δαπάνες.',
    })
  }

  // (8) Γνωμοδότηση Τεχνικού Συμβουλίου.
  // Απαιτείται όταν γίνεται χρήση επί έλαττον δαπανών, όταν υπάρχει
  // υπέρβαση του οικονομικού αντικειμένου (εργασίες άρθρου 132), ή όταν
  // απαιτείται συμπληρωματική σύμβαση.
  const needsTc = ape.supplementary_needed || t.savings > 0 || t.art132Total > 0
  if (needsTc && !ape.tc_opinion_id) {
    const why = ape.supplementary_needed
      ? 'συμπληρωματική σύμβαση'
      : t.art132Total > 0
        ? 'υπέρβαση του οικονομικού αντικειμένου (εργασίες άρθρου 132)'
        : 'χρήση επί έλαττον δαπανών'
    out.push({
      code: 'APE_TC_OPINION',
      severity: 'hard',
      legal_ref: 'N4412/156/1e',
      message: `Απαιτείται γνωμοδότηση Τεχνικού Συμβουλίου: ${why}.`,
    })
  }

  // (9) Π.Κ.Τ.Μ.Ν.Ε. όταν υπάρχουν νέα άρθρα (άρθρο 156 §5)
  if (ape.lines.some(l => l.is_new_item) && ape.atype !== 'me_pktmne') {
    out.push({
      code: 'APE_PKTMNE_MISSING',
      severity: 'hard',
      legal_ref: 'N4412/156/5',
      message: 'Ο ΑΠΕ περιλαμβάνει νέες εργασίες χωρίς συνοδευτικό Π.Κ.Τ.Μ.Ν.Ε.',
    })
  }

  // (10) Υπογραφή / κοινοποίηση στον ανάδοχο (άρθρο 156 §7)
  if (!ape.contractor_signature) {
    out.push({
      code: 'APE_SIGNATURE',
      severity: 'soft',
      legal_ref: 'N4412/156/7',
      message: 'Ο ΑΠΕ δεν έχει υπογραφεί από τον ανάδοχο ούτε έχει κοινοποιηθεί κατ’ άρθρο 143.',
    })
  }

  return out
}

/* ------------------------------------------------------------------ */
/* Άρθρο 152 — προϋποθέσεις λογαριασμού                                */
/* ------------------------------------------------------------------ */
export function paymentViolations(
  cert: PaymentCertificate,
  measurement: Measurement | undefined,
  hasApprovedAcceptance: boolean,
): Blocker[] {
  const out: Blocker[] = []

  if (!cert.measurement_id) {
    out.push({
      code: 'PAY_NO_MEASUREMENT',
      severity: 'hard',
      legal_ref: 'N4412/151/2',
      message:
        'Δεν έχει συνδεθεί εγκεκριμένη επιμέτρηση. Η υποβολή επιμέτρησης αποτελεί προϋπόθεση πληρωμής.',
    })
  } else if (!measurement || !['approved', 'deemed_approved'].includes(measurement.status)) {
    out.push({
      code: 'PAY_MEASUREMENT_NOT_APPROVED',
      severity: 'hard',
      legal_ref: 'N4412/151/2',
      message: 'Η συνδεδεμένη επιμέτρηση δεν έχει εγκριθεί.',
    })
  }

  if (!cert.has_summary_table) {
    out.push({
      code: 'PAY_NO_SUMMARY',
      severity: 'hard',
      legal_ref: 'N4412/152',
      message: 'Λείπει ο ανακεφαλαιωτικός συνοπτικός πίνακας των επιμετρήσεων εργασιών.',
    })
  }

  if (cert.ptype === 'telikos' && !hasApprovedAcceptance) {
    out.push({
      code: 'PAY_FINAL_NO_ACCEPTANCE',
      severity: 'hard',
      legal_ref: 'N4412/152',
      message:
        'Ο τελικός λογαριασμός υποβάλλεται μετά την παραλαβή του έργου και την έγκριση του πρωτοκόλλου.',
    })
  }

  return out
}

/** Υπολογισμός πληρωτέου ποσού λογαριασμού (άρθρο 152 — κρατήσεις 5%). */
export function computePayment(input: {
  gross_cumulative: number
  previous_certified: number
  previous_retentions: number
  advance_amortization: number
  penalties_amount: number
  other_deductions?: number
  retentions_pct?: number
  vat_rate?: number
}) {
  const retPct = input.retentions_pct ?? 5
  const vatRate = input.vat_rate ?? 24
  const period = round2(input.gross_cumulative - input.previous_certified)
  const retentions = round2((input.gross_cumulative * retPct) / 100 - input.previous_retentions)
  const net = round2(
    period -
      input.advance_amortization -
      input.penalties_amount -
      retentions -
      (input.other_deductions ?? 0),
  )
  const vat = round2((Math.max(net, 0) * vatRate) / 100)
  return { period_amount: period, retentions_amount: retentions, net_payable: net, vat_amount: vat }
}

/* ------------------------------------------------------------------ */
/* Σύνολα ΑΠΕ (άρθρα 156 και 132)                                      */
/* ------------------------------------------------------------------ */
/**
 * Η επίσημη δομή του Ανακεφαλαιωτικού Πίνακα, όπως τη συντάσσει η Δ/νση:
 *
 *   Άθροισμα Εργασιών
 * + Γ.Ε. & Ο.Ε. (ενιαίο ποσοστό, ΕΠΑΝΥΠΟΛΟΓΙΖΕΤΑΙ στο νέο άθροισμα)
 * = ΣΥΝΟΛΟ 1
 * + Απρόβλεπτα (το ΥΠΟΛΟΙΠΟ μετά την απορρόφηση)
 * = ΣΥΝΟΛΟ 2
 *
 * Ο ΑΠΕ είναι «σε ισοζύγιο»: το ΣΥΝΟΛΟ 2 παραμένει ίσο με της σύμβασης,
 * γιατί η αύξηση των εργασιών απορροφάται από τα απρόβλεπτα, τα οποία
 * συρρικνώνονται ισόποσα. Αν η αύξηση εξαντλήσει τα απρόβλεπτα, η διαφορά
 * ΔΕΝ βαφτίζεται σιωπηρά αύξηση: πρέπει να περάσει από το άρθρο 132 ή από
 * συμπληρωματική σύμβαση.
 *
 * Οι εργασίες του άρθρου 132 τηρούνται ΧΩΡΙΣΤΑ: δεν καλύπτονται από
 * απρόβλεπτα, προσαυξάνουν τη σύμβαση και έχουν δικό τους όριο 15% (§2).
 */
export interface ApeTotalsBase {
  /** Ενιαίο ποσοστό ΓΕ & ΟΕ του έργου (π.χ. 18). */
  geOePct: number
  /** ΣΥΝΟΛΟ 1 της αρχικής σύμβασης: εργασίες + ΓΕ & ΟΕ. */
  contractWorksPlusGeOe: number
  /** Κονδύλιο απροβλέπτων της αρχικής σύμβασης. */
  contingencyAmount: number
}

export interface ApeTotalsLine {
  unit_price: number
  qty_initial: number
  qty_previous: number
  qty_new: number
  funding_source: string
  is_article_132?: boolean
}

export function apeTotals(lines: ApeTotalsLine[], base: ApeTotalsBase) {
  const sum = (ls: ApeTotalsLine[], k: 'qty_initial' | 'qty_previous' | 'qty_new') =>
    round2(ls.reduce((s, l) => s + l.unit_price * l[k], 0))

  const main = lines.filter(l => !l.is_article_132)
  const art132 = lines.filter(l => l.is_article_132)

  /* --- Κυρίως ΑΠΕ ------------------------------------------------- */
  const worksInitial = sum(main, 'qty_initial')
  const worksPrevious = sum(main, 'qty_previous')
  const worksNew = sum(main, 'qty_new')

  const geOe = round2((worksNew * base.geOePct) / 100)
  const subtotal1 = round2(worksNew + geOe)

  // Τα απρόβλεπτα απορροφούν τη μεταβολή του ΣΥΝΟΛΟΥ 1.
  const contingencyUsed = round2(subtotal1 - base.contractWorksPlusGeOe)
  const contingencyRemaining = round2(base.contingencyAmount - contingencyUsed)
  const subtotal2 = round2(subtotal1 + contingencyRemaining)

  const contractSubtotal2 = round2(base.contractWorksPlusGeOe + base.contingencyAmount)

  /** Η αύξηση ξεπέρασε τα διαθέσιμα απρόβλεπτα. */
  const contingencyOverrun = contingencyRemaining < -0.005

  // ΠΡΟΣΟΧΗ: με εξαντλημένα απρόβλεπτα το ΣΥΝΟΛΟ 2 «κλείνει» αριθμητικά,
  // επειδή προστίθεται αρνητικό υπόλοιπο — κρύβοντας την υπέρβαση. Ισοζύγιο
  // υπάρχει ΜΟΝΟ όταν τα απρόβλεπτα επαρκούν.
  const balanced =
    !contingencyOverrun && Math.abs(subtotal2 - contractSubtotal2) < 0.015

  /* --- Εργασίες άρθρου 132 ---------------------------------------- */
  const art132Works = sum(art132, 'qty_new')
  const art132GeOe = round2((art132Works * base.geOePct) / 100)
  const art132Total = round2(art132Works + art132GeOe)

  /* --- Δαπάνη έργου (ΑΠΕ + άρθρο 132) ----------------------------- */
  const projectWorks = round2(worksNew + art132Works)
  const projectGeOe = round2(geOe + art132GeOe)
  const projectSubtotal1 = round2(subtotal1 + art132Total)
  const projectSubtotal2 = round2(projectSubtotal1 + contingencyRemaining)

  /* --- Μεταβολές --------------------------------------------------- */
  const savings = round2(
    main.reduce((s, l) => s + Math.max(0, (l.qty_initial - l.qty_new) * l.unit_price), 0))
  const increases = round2(
    main.reduce((s, l) => s + Math.max(0, (l.qty_new - l.qty_initial) * l.unit_price), 0))

  return {
    worksInitial, worksPrevious, worksNew,
    geOe, subtotal1,
    contingencyUsed, contingencyRemaining, subtotal2,
    contractSubtotal2, balanced, contingencyOverrun,
    art132Works, art132GeOe, art132Total,
    projectWorks, projectGeOe, projectSubtotal1, projectSubtotal2,
    savings, increases,
    /** Καθαρή μεταβολή έναντι της σύμβασης (= δαπάνη άρθρου 132). */
    delta: art132Total,
  }
}

/* ------------------------------------------------------------------ */
/* ΦΥΛΛΟ ΕΛΕΓΧΟΥ ΕΠΙ ΕΛΑΤΤΟΝ ΔΑΠΑΝΩΝ                                   */
/* ------------------------------------------------------------------ */
/**
 * Αναπαράγει το επίσημο φύλλο ελέγχου που συνοδεύει κάθε ΑΠΕ, κατά τις
 * εγκυκλίους 20/2006 και 30/2007 και το άρθρο 156 §3γ.
 *
 * Η αρίθμηση των στηλών ακολουθεί ΑΥΤΟΥΣΙΑ το έντυπο της Δ/νσης, ώστε ο
 * μηχανικός να μπορεί να αντιπαραβάλλει γραμμή προς γραμμή:
 *
 *   [3]  Πρ/σμός ομάδας αρχικής σύμβασης
 *   [4]  Πρ/σμός ομάδας με βάση τον ΑΠΕ
 *   [5]  Δαπάνες νέων εργασιών
 *   [6]  = [4]-[3] > 0            επί πλέον
 *   [7]  = [6]/[3]
 *   [8]  = [4]-[3] < 0            επί έλαττον
 *   [9]  = [8]/[3]
 *   [10] = [8]-0,2*[3] > 0        υπέρβαση ορίου 20% (επί έλαττον)
 *   [11] = [10]/[3]
 *   [12] = [8]-[10]               αποδεκτά επί έλαττον
 *   [13] = [12]/[3]
 *   [14] = [6]-0,2*[3] > 0        υπέρβαση ορίου 20% (επί ΠΛΕΟΝ)
 *   [15] = [14]/[3]
 *
 * Τα αθροίσματα προσαυξάνονται με ΓΕ & ΟΕ, όπως στο έντυπο.
 */
export interface CheckSheetGroup {
  group: string
  contractAmount: number   // [3]
  apeAmount: number        // [4]
  newWorks: number         // [5]
  over: number             // [6]
  overPct: number          // [7]
  under: number            // [8]
  underPct: number         // [9]
  underExcess: number      // [10]
  underExcessPct: number   // [11]
  underAccepted: number    // [12]
  underAcceptedPct: number // [13]
  overExcess: number       // [14]
  overExcessPct: number    // [15]
}

export function apeCheckSheet(
  lines: Array<{
    work_group: string
    unit_price: number
    qty_initial: number
    qty_new: number
    is_new_item?: boolean
    is_article_132?: boolean
  }>,
  base: ApeTotalsBase,
) {
  const pct = (n: number, d: number) => (d > 0 ? round2((n / d) * 100) : 0)

  const acc = new Map<string, { contract: number; ape: number; neo: number }>()
  for (const l of lines) {
    if (l.is_article_132) continue
    const g = acc.get(l.work_group) ?? { contract: 0, ape: 0, neo: 0 }
    g.contract += l.unit_price * l.qty_initial
    g.ape += l.unit_price * l.qty_new
    if (l.is_new_item) g.neo += l.unit_price * l.qty_new
    acc.set(l.work_group, g)
  }

  const groups: CheckSheetGroup[] = [...acc].map(([group, g]) => {
    const c = round2(g.contract)
    const a = round2(g.ape)
    const diff = round2(a - c)
    const over = diff > 0 ? diff : 0
    const under = diff < 0 ? -diff : 0
    const limit = round2(c * 0.2)
    const underExcess = under > limit ? round2(under - limit) : 0
    const overExcess = over > limit ? round2(over - limit) : 0
    const underAccepted = round2(under - underExcess)
    return {
      group,
      contractAmount: c, apeAmount: a, newWorks: round2(g.neo),
      over, overPct: pct(over, c),
      under, underPct: pct(under, c),
      underExcess, underExcessPct: pct(underExcess, c),
      underAccepted, underAcceptedPct: pct(underAccepted, c),
      overExcess, overExcessPct: pct(overExcess, c),
    }
  })

  const sum = (k: keyof CheckSheetGroup) =>
    round2(groups.reduce((s, g) => s + (g[k] as number), 0))

  const geOe = (n: number) => round2((n * base.geOePct) / 100)

  /* Αθροίσματα με ΓΕ & ΟΕ, όπως τα εμφανίζει το έντυπο στη γραμμή Σ2. */
  const worksContract = sum('contractAmount')
  const worksApe = sum('apeAmount')
  const totalOver = sum('over')
  const totalUnder = sum('under')
  const totalOverExcess = sum('overExcess')
  const totalUnderExcess = sum('underExcess')

  const s2Contract = round2(worksContract + geOe(worksContract))
  const s2Ape = round2(worksApe + geOe(worksApe))
  const s2Over = round2(totalOver + geOe(totalOver))            // Σ2(6)
  const s2Under = round2(totalUnder + geOe(totalUnder))         // Σ2(8)
  const s2OverExcess = round2(totalOverExcess + geOe(totalOverExcess))   // Σ2(14)
  const s2UnderExcess = round2(totalUnderExcess + geOe(totalUnderExcess)) // Σ2(10)

  // Απορρόφηση που ΑΠΑΙΤΕΙΤΑΙ για να κλείσει το ισοζύγιο.
  const contingencyUsed = round2(s2Ape - s2Contract)
  // Απορρόφηση που ΕΠΙΤΡΕΠΕΤΑΙ: δεν μπορεί να ξεπεράσει το κονδύλιο. Ό,τι
  // απαιτείται πέραν αυτού δεν είναι «χρήση απροβλέπτων» — είναι υπέρβαση
  // της σύμβασης και το πιάνει το apeTotals (contingencyOverrun).
  const contingencyApplied = round2(
    Math.min(Math.max(0, contingencyUsed), base.contingencyAmount))

  /* ---- ΠΙΝΑΚΑΣ 1: έλεγχος με βάση τα ΕΠΙ ΕΛΑΤΤΟΝ ------------------ */
  const t1_1 = round2(s2Contract * 0.1)   // [1.1] μέγιστο ποσό χρήσης επί έλαττον
  // [1.4] = Σ2(10) + Σ2(16): αφορά ΜΟΝΟ τα επί έλαττον. Η υπέρβαση των επί
  // πλέον ελέγχεται χωριστά, στον Πίνακα 2.
  const t1_4 = s2UnderExcess
  const t1_6 = s2Under
  const t1_7 = round2(t1_6 - t1_4)
  const t1_8 = t1_7 > t1_1 ? round2(t1_7 - t1_1) : 0  // απόκλιση από το 10%

  /* ---- ΠΙΝΑΚΑΣ 2: έλεγχος με βάση τα επί πλέον -------------------- */
  const t2_2 = s2OverExcess
  // Η υπέρβαση του 20% επιτρέπεται εφόσον καλύπτεται από τα
  // χρησιμοποιηθέντα απρόβλεπτα· ό,τι περισσεύει είναι παρέκκλιση.
  const t2_5 = round2(t2_2 - contingencyApplied)
  const overrunBeyondContingency = t2_5 > 0 ? t2_5 : 0

  /* ---- ΠΙΝΑΚΑΣ 3: ανακεφαλαίωση ----------------------------------- */
  const t3_1 = round2(t1_4 + t1_8)
  const t3_2 = overrunBeyondContingency
  const t3_3 = Math.max(t3_1, t3_2)

  return {
    groups,
    worksContract, worksApe,
    geOeContract: geOe(worksContract), geOeApe: geOe(worksApe),
    s2Contract, s2Ape,
    totalOver, totalUnder, totalOverExcess, totalUnderExcess,
    s2Over, s2Under, s2OverExcess, s2UnderExcess,
    contingencyAmount: base.contingencyAmount,
    contingencyUsed,
    contingencyApplied,
    contingencyRemaining: round2(base.contingencyAmount - contingencyUsed),
    /** [1.1] Μέγιστο επιτρεπτό ποσό χρήσης επί έλαττον (10% του Σ2). */
    maxSavings: t1_1,
    /** [1.4] Παράβαση του κανόνα του 20%. */
    rule20Breach: t1_4,
    /** [1.8] Απόκλιση από το όριο του 10%. */
    rule10Breach: t1_8,
    /** [2.5] Επί πλέον καθ' υπέρβαση, ΜΗ καλυπτόμενο από απρόβλεπτα. */
    overBeyondContingency: overrunBeyondContingency,
    /** [3.3] Σφάλμα παράβασης του κανόνα — το μεγαλύτερο των δύο. */
    ruleBreach: t3_3,
    /** Το φύλλο «περνά» όταν δεν υπάρχει καμία παράβαση. */
    passes: t3_3 <= 0.005,
  }
}

/* ------------------------------------------------------------------ */
/* Σύνολα λογαριασμού (άρθρο 152)                                      */
/* ------------------------------------------------------------------ */
export function paymentTotals(
  input: {
    works_cumulative: number
    ge_oe_amount: number
    apologistika_amount: number
    revision_amount: number
    compensations: number
    advance_amortization: number
    penalties_amount: number
    other_deductions: number
    retentions_pct: number
    vat_rate: number
  },
  priorCertificates: Array<{ gross_cumulative: number; retentions_amount: number }>,
) {
  const gross = round2(
    input.works_cumulative + input.ge_oe_amount + input.apologistika_amount +
    input.revision_amount + input.compensations,
  )
  // Σωρευτική λογική: αφαιρείται ό,τι έχει ήδη πιστοποιηθεί και κρατηθεί.
  const previousCertified = priorCertificates.reduce(
    (m, p) => Math.max(m, p.gross_cumulative), 0)
  const previousRetentions = round2(
    priorCertificates.reduce((s, p) => s + p.retentions_amount, 0))

  const c = computePayment({
    gross_cumulative: gross,
    previous_certified: previousCertified,
    previous_retentions: previousRetentions,
    advance_amortization: input.advance_amortization,
    penalties_amount: input.penalties_amount,
    other_deductions: input.other_deductions,
    retentions_pct: input.retentions_pct,
    vat_rate: input.vat_rate,
  })

  return {
    gross,
    previousCertified,
    previousRetentions,
    period: c.period_amount,
    retentions: c.retentions_amount,
    net: c.net_payable,
    vat: c.vat_amount,
  }
}

/* ------------------------------------------------------------------ */
/* Άρθρο 72 §14β — μειώσεις εγγυήσεων                                  */
/* ------------------------------------------------------------------ */
export function guaranteeReduction70Blockers(fm: FinalMeasurement | undefined): Blocker[] {
  if (fm?.approved_at) return []
  return [
    {
      code: 'GUAR_RED_NO_FINAL',
      severity: 'hard',
      legal_ref: 'N4412/72/14b',
      message:
        'Η μείωση της εγγύησης κατά 70% προϋποθέτει ΕΓΚΕΚΡΙΜΕΝΗ ΤΕΛΙΚΗ ΕΠΙΜΕΤΡΗΣΗ (άρθρο 72 §14 περ. β΄ σε συνδυασμό με άρθρο 151 §9).',
    },
  ]
}

export function guaranteeReleaseBlockers(opts: {
  acceptanceApproved: boolean
  finalPaymentApproved: boolean
}): Blocker[] {
  const out: Blocker[] = []
  if (!opts.acceptanceApproved) {
    out.push({
      code: 'GUAR_REL_NO_ACCEPTANCE',
      severity: 'hard',
      legal_ref: 'N4412/172',
      message: 'Δεν έχει εγκριθεί το πρωτόκολλο παραλαβής.',
    })
  }
  if (!opts.finalPaymentApproved) {
    out.push({
      code: 'GUAR_REL_NO_FINAL_PAYMENT',
      severity: 'hard',
      legal_ref: 'N4412/152',
      message: 'Δεν έχει εγκριθεί ο τελικός λογαριασμός.',
    })
  }
  return out
}

/* ------------------------------------------------------------------ */
/* Άρθρο 151 §7 — αφανείς εργασίες                                     */
/* ------------------------------------------------------------------ */
export function hiddenWorkAlert(n: {
  inspected_at: string | null
  inspection_due: string
  photos_count: number
  approved_at: string | null
  approval_due: string | null
  covered_at: string | null
}): { level: 'ok' | 'warn' | 'error'; text: string } {
  if (!n.inspected_at && n.covered_at) {
    return { level: 'error', text: 'Επικαλύφθηκε χωρίς έλεγχο επιβλέποντος' }
  }
  if (!n.inspected_at && (daysUntil(n.inspection_due) ?? 0) < 0) {
    return { level: 'error', text: 'Υπερημερία κυρίου του έργου (άρθρο 151 §7)' }
  }
  if (!n.inspected_at) return { level: 'warn', text: 'Εκκρεμεί έλεγχος εντός 3ημέρου' }
  if (n.photos_count === 0) return { level: 'error', text: 'Λείπει φωτογραφική τεκμηρίωση' }
  if (!n.approved_at && n.approval_due && (daysUntil(n.approval_due) ?? 0) < 0) {
    return { level: 'error', text: 'Εκπρόθεσμη εγκριτική πράξη (30 ημέρες)' }
  }
  if (!n.approved_at) return { level: 'warn', text: 'Εκκρεμεί εγκριτική πράξη' }
  return { level: 'ok', text: 'Ολοκληρωμένο' }
}

/* ------------------------------------------------------------------ */
/* Ειδικοί κανόνες σταδίων (αντιστοιχούν στα guard_fn της βάσης)       */
/* ------------------------------------------------------------------ */
export interface GuardContext {
  contract: Contract
  guarantees: Guarantee[]
  scheduleSubmittedAt: string | null
  scheduleApprovedAt: string | null
  scheduleDeemedApproved: boolean
  scheduleMethod: 'diktyoti_analysi' | 'grammiko' | null
  diaryMissingDays: number
  diaryUnreviewed: number
  hiddenOverdue: number
  hiddenCoveredUnchecked: number
  measurementsSubmitted: number
  measurementsAudited: number
  apes: Ape[]
  completion: Completion | undefined
  finalMeasurement: FinalMeasurement | undefined
  acceptanceApproved: boolean
  acceptanceCommitteeSize: number
  guaranteeReduced70: boolean
  openDefects: number
}

export function guardBlockers(guardFn: string | null, ctx: GuardContext): Blocker[] {
  switch (guardFn) {
    case 'app.guard_guarantees': {
      const active = ctx.guarantees
        .filter(g => ['kalis_ektelesis', 'prosthetti'].includes(g.gtype))
        .filter(g => ['energi', 'meiomeni_70'].includes(g.status))
        .reduce((s, g) => s + g.current_amount, 0)
      if (active === 0) {
        return [{
          code: 'GUAR_MISSING', severity: 'hard', legal_ref: 'N4412/72/4',
          message: 'Δεν έχει καταχωρηθεί ενεργή εγγυητική επιστολή καλής εκτέλεσης.',
        }]
      }
      const required = ctx.contract.initial_value_net * 0.05
      if (active < required - 0.01) {
        return [{
          code: 'GUAR_UNDER_5PCT', severity: 'hard', legal_ref: 'N4412/72/4',
          message: `Η κατατεθειμένη εγγύηση (${fmt(active)}) υπολείπεται του 5% της εκτιμώμενης αξίας (${fmt(required)}).`,
        }]
      }
      return []
    }

    case 'app.guard_schedule': {
      const out: Blocker[] = []
      if (!ctx.scheduleSubmittedAt) {
        out.push({
          code: 'SCHED_NOT_SUBMITTED', severity: 'hard', legal_ref: 'N4412/145/1',
          message: 'Το χρονοδιάγραμμα δεν έχει υποβληθεί από τον ανάδοχο.',
        })
      }
      if (!ctx.scheduleApprovedAt && !ctx.scheduleDeemedApproved) {
        out.push({
          code: 'SCHED_PENDING', severity: 'hard', legal_ref: 'N4412/145/2',
          message: 'Εκκρεμεί η έγκριση του χρονοδιαγράμματος από τη Διευθύνουσα Υπηρεσία (προθεσμία 15 ημερών).',
        })
      }
      if (ctx.contract.initial_value_net > 1_000_000 && ctx.scheduleMethod !== 'diktyoti_analysi') {
        out.push({
          code: 'SCHED_METHOD', severity: 'hard', legal_ref: 'N4412/145/3',
          message: 'Για έργα άνω του 1.000.000 € η μέθοδος δικτυωτής ανάλυσης είναι ΥΠΟΧΡΕΩΤΙΚΗ.',
        })
      }
      return out
    }

    case 'app.guard_diary': {
      const out: Blocker[] = []
      if (ctx.diaryMissingDays > 0) {
        out.push({
          code: 'DIARY_MISSING', severity: 'hard', legal_ref: 'N4412/146',
          message: `Λείπουν ${ctx.diaryMissingDays} ημέρες ημερολογίου. Η παράλειψη επισύρει ειδική ποινική ρήτρα ${ctx.contract.diary_penalty_per_day} € ανά ημέρα.`,
        })
      }
      if (ctx.diaryUnreviewed > 0) {
        out.push({
          code: 'DIARY_UNREVIEWED', severity: 'soft', legal_ref: 'N4412/146',
          message: `${ctx.diaryUnreviewed} εγγραφές δεν ελέγχθηκαν από τον επιβλέποντα εντός δύο (2) εργασίμων ημερών.`,
        })
      }
      return out
    }

    case 'app.guard_hidden_works': {
      const out: Blocker[] = []
      if (ctx.hiddenOverdue > 0) {
        out.push({
          code: 'HW_OVERDUE', severity: 'hard', legal_ref: 'N4412/151/7',
          message: `${ctx.hiddenOverdue} δηλώσεις αφανών εργασιών δεν ελέγχθηκαν εντός της 3ήμερης προθεσμίας — ΥΠΕΡΗΜΕΡΙΑ ΚΥΡΙΟΥ ΤΟΥ ΕΡΓΟΥ.`,
        })
      }
      if (ctx.hiddenCoveredUnchecked > 0) {
        out.push({
          code: 'HW_COVERED_UNCHECKED', severity: 'hard', legal_ref: 'N4412/151/7',
          message: `${ctx.hiddenCoveredUnchecked} αφανείς εργασίες επικαλύφθηκαν χωρίς προηγούμενο έλεγχο του επιβλέποντος.`,
        })
      }
      return out
    }

    case 'app.guard_measurements': {
      const required = requiredAuditCount(ctx.measurementsSubmitted)
      if (ctx.measurementsAudited < required) {
        return [{
          code: 'MEAS_AUDIT_SHORTFALL', severity: 'hard', legal_ref: 'N4412/151/3',
          message: `Ο υποχρεωτικός δειγματοληπτικός έλεγχος δεν καλύφθηκε: απαιτούνται ${required}, διενεργήθηκαν ${ctx.measurementsAudited}.`,
        }]
      }
      return []
    }

    case 'app.guard_ape_stage': {
      const out: Blocker[] = []
      const approved = ctx.apes.filter(a => a.status === 'approved')
      for (const a of ctx.apes.filter(a => a.status !== 'approved')) {
        for (const b of apeViolations(a, ctx.contract, approved).filter(b => b.severity === 'hard')) {
          out.push({ ...b, code: `APE${a.serial_no}_${b.code}`, message: `${a.serial_no}ος ΑΠΕ: ${b.message}` })
        }
      }
      return out
    }

    case 'app.guard_completion': {
      const out: Blocker[] = []
      const c = ctx.completion
      if (!c || !c.supervisor_report_at) {
        return [{
          code: 'COMP_NO_REPORT', severity: 'hard', legal_ref: 'N4412/168/1',
          message: 'Δεν έχει συνταχθεί η έγγραφη αναφορά του επιβλέποντος περί περαίωσης (προθεσμία 30 ημερών από τη λήξη του εγκεκριμένου χρόνου).',
        }]
      }
      if (!c.tests_completed) {
        out.push({
          code: 'COMP_NO_TESTS', severity: 'hard', legal_ref: 'N4412/168/1',
          message: 'Δεν βεβαιώνεται η ολοκλήρωση των προβλεπόμενων από τη σύμβαση δοκιμών.',
        })
      }
      if (ctx.openDefects > 0) {
        out.push(
          c.defects_severity === 'ousiodes'
            ? {
                code: 'COMP_MAJOR_DEFECTS', severity: 'hard', legal_ref: 'N4412/168/4',
                message: 'Υφίστανται ΟΥΣΙΩΔΗ ελαττώματα: εφαρμόζονται τα άρθρα 159 και 160 και δεν εκδίδεται Βεβαίωση Περάτωσης.',
              }
            : {
                code: 'COMP_MINOR_DEFECTS', severity: 'hard', legal_ref: 'N4412/168/3',
                message: `Εκκρεμεί η αποκατάσταση ${ctx.openDefects} επουσιωδών ελαττωμάτων εντός της ταχθείσας προθεσμίας.`,
              },
        )
      }
      return out
    }

    case 'app.guard_guarantee_reduction': {
      const out = guaranteeReduction70Blockers(ctx.finalMeasurement)
      if (out.length === 0 && !ctx.guaranteeReduced70) {
        out.push({
          code: 'GUAR_RED_NOT_DONE', severity: 'hard', legal_ref: 'N4412/72/14b',
          message: 'Δεν έχει καταχωρηθεί η πράξη μείωσης της εγγύησης καλής εκτέλεσης κατά 70%.',
        })
      }
      return out
    }

    case 'app.guard_acceptance': {
      const out: Blocker[] = []
      if (ctx.acceptanceCommitteeSize === 0) {
        out.push({
          code: 'ACC_NO_COMMITTEE', severity: 'hard', legal_ref: 'N4412/172',
          message: 'Δεν έχει οριστεί επιτροπή παραλαβής (ορίζεται τουλάχιστον 3 μήνες πριν τη λήξη της συντήρησης).',
        })
      } else if (ctx.acceptanceCommitteeSize < 5) {
        out.push({
          code: 'ACC_COMMITTEE_SIZE', severity: 'hard', legal_ref: 'N4412/172',
          message: `Η επιτροπή παραλαβής έχει ${ctx.acceptanceCommitteeSize} μέλη — απαιτείται πενταμελής σύνθεση με δύο εκπροσώπους ΤΕΕ/ΓΕΩΤΕΕ.`,
        })
      }
      if (!ctx.acceptanceApproved) {
        out.push({
          code: 'ACC_NOT_APPROVED', severity: 'hard', legal_ref: 'N4412/172',
          message: 'Δεν έχει εγκριθεί το πρωτόκολλο παραλαβής.',
        })
      }
      return out
    }

    default:
      return []
  }
}

/* ------------------------------------------------------------------ */
const NF = new Intl.NumberFormat('el-GR', { style: 'currency', currency: 'EUR' })
const fmt = (n: number) => NF.format(n)
const round2 = (n: number) => Math.round(n * 100) / 100
