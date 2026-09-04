/**
 * Έγγραφα που συνοδεύουν τον Ανακεφαλαιωτικό Πίνακα Εργασιών.
 *
 * Σε αντίθεση με τα πρότυπα του `templates.json`, που είναι έντυπα
 * συμπλήρωσης κενών, τα έγγραφα του ΑΠΕ είναι ΥΠΟΛΟΓΙΖΟΜΕΝΟΙ πίνακες: η
 * αιτιολογική έκθεση και το φύλλο ελέγχου παράγονται εξ ολοκλήρου από τα
 * στοιχεία του ΑΠΕ και της σύμβασης. Γι' αυτό συντίθενται εδώ, με τον ίδιο
 * όμως περιτυλιγμό (`wrapDocument`) ώστε η εμφάνιση και η εκτύπωση να
 * παραμένουν ενιαίες με τα υπόλοιπα έγγραφα.
 *
 * Η δομή αντιγράφει τα εγκεκριμένα έγγραφα της Δ/νσης:
 *   Α. ΙΣΤΟΡΙΚΟ — Β. ΑΝΑΚΕΦΑΛΑΙΩΤΙΚΟΣ ΠΙΝΑΚΑΣ — Γ. ΔΑΠΑΝΗ
 */
import { grUpper, wrapDocument, type DocContext } from './docgen'
import { apeCheckSheet, apeTotals } from './rules'
import { AWARD_BODY } from './labels'
import type { Ape, Contract, Project } from './types'

/* ------------------------------------------------------------------ */
/* Μορφοποίηση                                                         */
/* ------------------------------------------------------------------ */
const EUR = new Intl.NumberFormat('el-GR', {
  style: 'currency', currency: 'EUR', minimumFractionDigits: 2, maximumFractionDigits: 2,
})
const PCT = new Intl.NumberFormat('el-GR', {
  minimumFractionDigits: 2, maximumFractionDigits: 2,
})

const eur = (n: number) => EUR.format(n)
const pct = (n: number) => `${PCT.format(n)}%`
const esc = (s: string) =>
  s.replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]!))

const gr = (iso: string | null | undefined) => {
  if (!iso) return '—'
  const [y, m, d] = iso.split('-')
  return `${d}-${m}-${y}`
}

/** «960/22-12-2025» — όπως γράφεται στο ιστορικό. */
const refOf = (no: string | null | undefined, date: string | null | undefined) =>
  no ? `${no}/${gr(date)}` : '—'

/** Ελληνικό τακτικό αριθμητικό με πτώση — «ο 1ος», «του 1ου», «τον 1ο». */
const ord = {
  nom: (n: number) => `${n}ος`,
  gen: (n: number) => `${n}ου`,
  acc: (n: number) => `${n}ο`,
}

/* ------------------------------------------------------------------ */
/* Κοινό περιβάλλον                                                    */
/* ------------------------------------------------------------------ */
export interface ApeDocContext {
  org: DocContext['org']
  project: Project
  contract: Contract
  ape: Ape
  /** Ο συντάκτης — επιβλέπων μηχανικός. */
  author?: { full_name: string; specialty: string | null } | null
  head?: { full_name: string; specialty: string | null } | null
  /** Απόφαση έγκρισης του προηγούμενου ΑΠΕ, αν υπάρχει. */
  previousApeApproval?: string | null
}

function totalsOf(c: ApeDocContext) {
  const contractSubtotal1 =
    Math.round((c.contract.initial_value_net - c.contract.contingency_amount) * 100) / 100
  const base = {
    geOePct: c.contract.ge_oe_pct ?? 18,
    contractWorksPlusGeOe: contractSubtotal1,
    contingencyAmount: c.contract.contingency_amount,
  }
  const lines = c.ape.lines.map(l => ({
    ...l,
    qty_previous: l.qty_initial,
  }))
  return {
    base,
    contractSubtotal1,
    t: apeTotals(lines, base),
    cs: apeCheckSheet(c.ape.lines, base),
  }
}

/* ================================================================== */
/* 1. ΑΙΤΙΟΛΟΓΙΚΗ ΕΚΘΕΣΗ                                              */
/* ================================================================== */
export function aitiologikiEkthesi(c: ApeDocContext): string {
  const { ape, contract: k, project: p } = c
  const { t, contractSubtotal1 } = totalsOf(c)
  const no = ape.serial_no
  const has132 = t.art132Total > 0

  const geOePct = k.ge_oe_pct ?? 18
  const contractWorks = Math.round((contractSubtotal1 / (1 + geOePct / 100)) * 100) / 100
  const contractGeOe = Math.round((contractSubtotal1 - contractWorks) * 100) / 100

  const vat = (x: number) => Math.round((x * k.vat_rate) / 100 * 100) / 100
  const withVat = (x: number) => Math.round((x + vat(x)) * 100) / 100

  const months = Math.round(k.total_duration_days / 30)
  const body = k.award_decision_no
    ? `Με την ${esc(refOf(k.award_decision_no, k.award_decision_date))} απόφαση της
       ${esc(AWARD_BODY[k.award_body ?? 'dimotiki_epitropi'])}${
        k.legalization_doc_no
          ? `, που νομιμοποιήθηκε με το αρ. ${esc(refOf(k.legalization_doc_no, k.legalization_doc_date))}
             έγγραφο της ${esc(k.legalization_authority ?? 'Αποκεντρωμένης Διοίκησης')}`
          : ''
      }, εγκρίθηκε η ανάθεση του έργου «${esc(p.title)}» στην εργοληπτική
       επιχείρηση «${esc(k.contractor_name)}», με μέση έκπτωση προσφοράς
       ${pct(k.discount_pct)} επί των τιμών του τιμολογίου της μελέτης και ποσό
       προσφοράς ${eur(k.initial_value_net)} χωρίς Φ.Π.Α. ή
       ${eur(withVat(k.initial_value_net))} με Φ.Π.Α.`
    : `Το έργο «${esc(p.title)}» ανατέθηκε στην εργοληπτική επιχείρηση
       «${esc(k.contractor_name)}», με μέση έκπτωση προσφοράς ${pct(k.discount_pct)}
       και ποσό προσφοράς ${eur(k.initial_value_net)} χωρίς Φ.Π.Α.`

  /* --- Γ. ΔΑΠΑΝΗ: ο πίνακας του εγγράφου ------------------------- */
  const col = (label: string, a: number, b: number, cc: number, d: number, strong = false) => `
    <tr${strong ? ' class="strong"' : ''}>
      <td>${esc(label)}</td>
      <td class="num">${eur(a)}</td>
      <td class="num">${eur(b)}</td>
      ${has132 ? `<td class="num">${eur(cc)}</td><td class="num">${eur(d)}</td>` : ''}
    </tr>`

  const err = ape.accounting_error ?? 0
  const rev = ape.revision_amount ?? 0
  const s3c = Math.round((t.contractSubtotal2 + err) * 100) / 100
  const s3a = Math.round((t.subtotal2 + err) * 100) / 100
  const s3p = Math.round((t.projectSubtotal2 + err) * 100) / 100
  const netC = Math.round((s3c + rev) * 100) / 100
  const netA = Math.round((s3a + rev) * 100) / 100
  const netP = Math.round((s3p + rev) * 100) / 100

  const table = `
  <table class="cost">
    <thead><tr>
      <th></th><th class="num">Κύρια Σύμβαση</th><th class="num">${esc(ord.nom(no))} ΑΠΕ</th>
      ${has132 ? '<th class="num">Άρθρο 132</th><th class="num">Δαπάνη έργου</th>' : ''}
    </tr></thead>
    <tbody>
      ${col('Άθροισμα Εργασιών', contractWorks, t.worksNew, t.art132Works, t.projectWorks)}
      ${col(`Γ.Ε. + Ο.Ε. ${PCT.format(geOePct)}%`, contractGeOe, t.geOe, t.art132GeOe, t.projectGeOe)}
      ${col('ΣΥΝΟΛΟ 1', contractSubtotal1, t.subtotal1, t.art132Total, t.projectSubtotal1, true)}
      ${col('ΑΠΡΟΒΛΕΠΤΑ', k.contingency_amount, t.contingencyRemaining, 0, t.contingencyRemaining)}
      ${col('ΣΥΝΟΛΟ 2', t.contractSubtotal2, t.subtotal2, t.art132Total, t.projectSubtotal2, true)}
      ${err !== 0 ? col('ΛΟΓΙΣΤΙΚΟ ΛΑΘΟΣ', err, err, 0, err) : ''}
      ${err !== 0 ? col('ΣΥΝΟΛΟ 3', s3c, s3a, t.art132Total, s3p, true) : ''}
      ${rev !== 0 ? col('ΑΝΑΘΕΩΡΗΣΗ', rev, rev, 0, rev) : ''}
      ${col('ΔΑΠΑΝΗ ΕΡΓΟΥ ΧΩΡΙΣ Φ.Π.Α.', netC, netA, t.art132Total, netP, true)}
      ${col(`Φ.Π.Α. ${PCT.format(k.vat_rate)}%`, vat(netC), vat(netA), vat(t.art132Total), vat(netP))}
      ${col('ΣΥΝΟΛΙΚΗ ΔΑΠΑΝΗ ΕΡΓΟΥ', withVat(netC), withVat(netA),
            withVat(t.art132Total), withVat(netP), true)}
    </tbody>
  </table>`

  const tcNeeded = ape.supplementary_needed || t.savings > 0 || has132

  const html = `
${DOC_STYLE}
<h2>Α. ΙΣΤΟΡΙΚΟ</h2>
<ol class="hist">
  <li>${body}</li>
  <li>Η σύμβαση του έργου ύψους ${eur(withVat(k.initial_value_net))} (με Φ.Π.Α.)
      υπεγράφη στις ${esc(gr(k.signed_at))} και προβλέπει προθεσμία αποπεράτωσης
      των εργασιών ${months} ${months === 1 ? 'μήνα' : 'μήνες'}, ήτοι έως τις
      ${esc(gr(k.original_end_date))}.</li>
  <li>Η Υπηρεσία συνέταξε τον ${esc(ord.acc(no))} Α.Π.Ε., ο οποίος κρίθηκε απαραίτητος για τη
      συνέχιση των εργασιών της εργολαβίας, προκειμένου να συμπεριληφθούν σε αυτόν
      αυξομειώσεις ποσοτήτων όπως παρουσιάστηκαν κατά την πορεία υλοποίησης της
      σύμβασης${has132 ? ', καθώς και υπερσυμβατικές εργασίες σύμφωνα με το άρθρο 132 του ν. 4412/2016' : ''}.</li>
  ${c.previousApeApproval ? `<li>${esc(c.previousApeApproval)}</li>` : ''}
</ol>

<h2>Β. ${esc(grUpper(ord.nom(no)))} ΑΝΑΚΕΦΑΛΑΙΩΤΙΚΟΣ ΠΙΝΑΚΑΣ${has132 ? ' ΚΑΙ ΕΡΓΑΣΙΕΣ ΣΥΜΦΩΝΑ ΜΕ ΤΟ ΑΡΘΡΟ 132' : ''}</h2>
<p>Ο ${esc(ord.nom(no))} Ανακεφαλαιωτικός Πίνακας συντάχθηκε προκειμένου να συμπεριλάβει
   αυξομειώσεις ποσοτήτων όπως παρουσιάζονται κατά την πορεία υλοποίησης της
   σύμβασης, σύμφωνα με τις διατάξεις του ν. 4412/2016, όπως τροποποιήθηκαν και
   ισχύουν με τον ν. 4782/2021.</p>

<p>${esc(ape.reason)}</p>

<p>Οι μεταβολές στις δαπάνες των εργασιών του ${esc(ord.gen(no))} Α.Π.Ε.
   ${t.contingencyOverrun
      ? 'ΥΠΕΡΒΑΙΝΟΥΝ τη δαπάνη των απροβλέπτων'
      : 'αντιμετωπίζονται από τη δαπάνη των απροβλέπτων'}
   και ${t.savings > 0
      ? `γίνεται χρήση των επί «έλαττον» δαπανών ύψους ${eur(t.savings)}`
      : 'δεν γίνεται χρήση των επί «έλαττον» δαπανών'}.
   ${tcNeeded
      ? 'Απαιτείται γνωμοδότηση του οικείου Τεχνικού Συμβουλίου Δημοσίων Έργων.'
      : 'Ως εκ τούτου δεν απαιτείται η σύμφωνη γνώμη του Τεχνικού Συμβουλίου.'}</p>

<p>Με τον παρόντα ${esc(ord.acc(no))} Α.Π.Ε. ισχύουν τα παρακάτω:</p>
<ol class="terms">
  <li>Δεν μεταβάλλεται το φυσικό αντικείμενο και δεν προκαλείται αλλαγή του
      «βασικού σχεδίου» της αρχικής σύμβασης, όπως αυτό περιγράφεται στα
      συμβατικά τεύχη.</li>
  <li>Δεν θίγεται η πληρότητα, η ποιότητα και η λειτουργικότητα του έργου, ούτε
      τροποποιούνται οι προδιαγραφές εκτέλεσής του.</li>
  <li>Δεν καταργείται καμία ομάδα εργασιών της αρχικής σύμβασης.</li>
  <li>Γίνεται χρήση της δαπάνης των απροβλέπτων και πληρούνται όλες οι
      προϋποθέσεις της παρ. 3 του άρθρου 156 του ν. 4412/2016, καθώς και των
      εγκυκλίων 20/2006 και 30/2007, σύμφωνα με το συνημμένο φύλλο ελέγχου.</li>
</ol>

${has132 ? `<p>Οι απαιτούμενες δαπάνες για την εκτέλεση των εν λόγω εργασιών
   αντιμετωπίζονται σύμφωνα με το άρθρο 132 του ν. 4412/2016 και ειδικότερα την
   παράγραφο 2, στην οποία αναφέρεται ότι συμβάσεις μπορούν να τροποποιούνται
   χωρίς νέα διαδικασία σύναψης σύμβασης, δεδομένου ότι η δαπάνη δεν υπερβαίνει
   το 15% της αξίας της αρχικής σύμβασης.</p>` : ''}

<h2>Γ. ΔΑΠΑΝΗ ${esc(grUpper(ord.gen(no)))} ΑΠΕ${has132 ? ' ΚΑΙ ΕΡΓΑΣΙΩΝ ΤΟΥ ΑΡΘΡΟΥ 132' : ''}</h2>
<p>Η δαπάνη του έργου με τον ${esc(ord.acc(no))} Α.Π.Ε.${has132
    ? ', συμπεριλαμβανομένης της δαπάνης για τις εργασίες που εκτελούνται σύμφωνα με το άρθρο 132 του ν. 4412/2016,'
    : ''} ανέρχεται στο ποσό των ${eur(withVat(has132 ? netP : netA))},
   συμπεριλαμβανομένου του Φ.Π.Α., και αναλύεται ως εξής:</p>
${table}

<p class="closing">Ο ${esc(ord.nom(no))} Ανακεφαλαιωτικός Πίνακας
  ${t.balanced && !has132
    ? 'βρίσκεται σε ισοζύγιο έναντι της αρχικής σύμβασης.'
    : has132
      ? `παρουσιάζει αύξηση δαπάνης κατά ${eur(t.art132Total)} (χωρίς Φ.Π.Α.), ήτοι
         ποσοστό ${pct((t.art132Total / k.initial_value_net) * 100)} έναντι της σύμβασης.`
      : 'ΔΕΝ βρίσκεται σε ισοζύγιο έναντι της σύμβασης.'}</p>`

  return wrapDocument({
    org: c.org,
    title: 'Αιτιολογική Έκθεση',
    subject: `Αιτιολογική έκθεση που συνοδεύει τον ${ord.acc(no)} Α.Π.Ε. του έργου «${p.title}»`,
    protocolNo: null,
    protocolDate: gr(ape.drafted_at),
    legalRef: 'άρθρο 156 §2 ν. 4412/2016',
    bodyHtml: html,
    signatories: [
      {
        label: 'Ο Συντάξας',
        name: c.author?.full_name ?? '',
        capacity: c.author?.specialty ?? undefined,
      },
    ],
    recipients: [],
  })
}

/* ================================================================== */
/* 2. ΦΥΛΛΟ ΕΛΕΓΧΟΥ ΕΠΙ ΕΛΑΤΤΟΝ ΔΑΠΑΝΩΝ                               */
/* ================================================================== */
export function fylloElegchou(c: ApeDocContext): string {
  const { ape, contract: k, project: p } = c
  const { cs } = totalsOf(c)
  const no = ape.serial_no

  const rows = cs.groups.map((g, i) => `
    <tr>
      <td class="c">${i + 1}</td>
      <td>${esc(g.group)}</td>
      <td class="num">${eur(g.contractAmount)}</td>
      <td class="num">${eur(g.apeAmount)}</td>
      <td class="num">${g.newWorks ? eur(g.newWorks) : ''}</td>
      <td class="num">${g.over ? eur(g.over) : ''}</td>
      <td class="num">${g.over ? PCT.format(g.overPct) : ''}</td>
      <td class="num">${g.under ? eur(g.under) : ''}</td>
      <td class="num">${g.under ? PCT.format(g.underPct) : ''}</td>
      <td class="num warn">${g.underExcess ? eur(g.underExcess) : ''}</td>
      <td class="num warn">${g.overExcess ? eur(g.overExcess) : ''}</td>
      <td class="num warn">${g.overExcess ? PCT.format(g.overExcessPct) : ''}</td>
    </tr>`).join('')

  const html = `
${DOC_STYLE}
<p class="lead">Έλεγχος των επί έλαττον δαπανών του ${esc(ord.gen(no))} Α.Π.Ε., κατά το άρθρο
   156 §3γ του ν. 4412/2016 και τις εγκυκλίους 20/2006 και 30/2007.</p>

<table class="check">
  <thead>
    <tr>
      <th rowspan="2" class="c">Α/Α</th>
      <th rowspan="2">Ένδειξη εργασιών</th>
      <th class="num">Πρ/σμός ομάδας<br>αρχικής σύμβασης</th>
      <th class="num">Πρ/σμός ομάδας<br>με βάση τον ΑΠΕ</th>
      <th class="num">Δαπάνες νέων<br>εργασιών</th>
      <th colspan="2" class="num">Επί πλέον</th>
      <th colspan="2" class="num">Επί έλαττον</th>
      <th class="num">Υπέρβ. 20%<br>επί έλαττον</th>
      <th colspan="2" class="num">Υπέρβ. 20% επί πλέον</th>
    </tr>
    <tr>
      <th class="num idx">[3]</th><th class="num idx">[4]</th><th class="num idx">[5]</th>
      <th class="num idx">[6]</th><th class="num idx">[7] %</th>
      <th class="num idx">[8]</th><th class="num idx">[9] %</th>
      <th class="num idx">[10]</th>
      <th class="num idx">[14]</th><th class="num idx">[15] %</th>
    </tr>
  </thead>
  <tbody>
    ${rows}
    <tr class="strong">
      <td colspan="2">Άθροισμα Εργασιών Σ1</td>
      <td class="num">${eur(cs.worksContract)}</td>
      <td class="num">${eur(cs.worksApe)}</td>
      <td class="num"></td>
      <td class="num">${eur(cs.totalOver)}</td><td class="num"></td>
      <td class="num">${eur(cs.totalUnder)}</td><td class="num"></td>
      <td class="num">${eur(cs.totalUnderExcess)}</td>
      <td class="num">${eur(cs.totalOverExcess)}</td><td class="num"></td>
    </tr>
    <tr>
      <td colspan="2">Προστίθεται Γ.Ε. &amp; Ο.Ε.</td>
      <td class="num">${eur(cs.geOeContract)}</td>
      <td class="num">${eur(cs.geOeApe)}</td>
      <td class="num"></td>
      <td class="num">${eur(Math.round((cs.s2Over - cs.totalOver) * 100) / 100)}</td><td class="num"></td>
      <td class="num">${eur(Math.round((cs.s2Under - cs.totalUnder) * 100) / 100)}</td><td class="num"></td>
      <td class="num">${eur(Math.round((cs.s2UnderExcess - cs.totalUnderExcess) * 100) / 100)}</td>
      <td class="num">${eur(Math.round((cs.s2OverExcess - cs.totalOverExcess) * 100) / 100)}</td><td class="num"></td>
    </tr>
    <tr class="strong">
      <td colspan="2">Σύνολο Σ2 <span class="小">(χωρίς ΦΠΑ και αναθεωρήσεις)</span></td>
      <td class="num">${eur(cs.s2Contract)}</td>
      <td class="num">${eur(cs.s2Ape)}</td>
      <td class="num"></td>
      <td class="num">${eur(cs.s2Over)}</td><td class="num"></td>
      <td class="num">${eur(cs.s2Under)}</td><td class="num"></td>
      <td class="num">${eur(cs.s2UnderExcess)}</td>
      <td class="num">${eur(cs.s2OverExcess)}</td><td class="num"></td>
    </tr>
  </tbody>
</table>

<div class="two">
  <div>
    <h3>ΠΙΝΑΚΑΣ 1 · Έλεγχος με βάση τα επί έλαττον</h3>
    <table class="mini">
      <tr><td>[1.1]</td><td>Μέγιστο ποσό χρήσης επί έλαττον (10% × Σ2)</td>
          <td class="num">${eur(cs.maxSavings)}</td></tr>
      <tr><td>[1.4]</td><td>Παράβαση του κανόνα του 20% των επί έλαττον</td>
          <td class="num">${cs.rule20Breach ? eur(cs.rule20Breach) : '—'}</td></tr>
      <tr><td>[1.6]</td><td>Επί έλαττον</td><td class="num">${eur(cs.s2Under)}</td></tr>
      <tr><td>[1.8]</td><td>Απόκλιση από το όριο του 10%</td>
          <td class="num">${cs.rule10Breach ? eur(cs.rule10Breach) : '—'}</td></tr>
    </table>
  </div>
  <div>
    <h3>ΠΙΝΑΚΑΣ 2 · Έλεγχος με βάση τα επί πλέον</h3>
    <table class="mini">
      <tr><td>[2.2]</td><td>Επί πλέον καθ' υπέρβαση του 20%</td>
          <td class="num">${eur(cs.s2OverExcess)}</td></tr>
      <tr><td></td><td>Μείον: χρησιμοποιηθέντα απρόβλεπτα</td>
          <td class="num">${cs.contingencyApplied > 0 ? '−' + eur(cs.contingencyApplied) : '—'}</td></tr>
      <tr><td>[2.5]</td><td>Κατά παρέκκλιση επί πλέον</td>
          <td class="num">${cs.overBeyondContingency ? eur(cs.overBeyondContingency) : '—'}</td></tr>
    </table>
  </div>
</div>

<h3>ΠΙΝΑΚΑΣ 3 · Ανακεφαλαίωση</h3>
<table class="mini wide">
  <tr><td>[3.3]</td><td>Σφάλμα παράβασης του κανόνα</td>
      <td class="num">${cs.ruleBreach ? eur(cs.ruleBreach) : '—'}</td></tr>
</table>

<p class="verdict ${cs.passes ? 'ok' : 'bad'}">
  ${cs.passes
    ? 'Ο έλεγχος δεν εντοπίζει παράβαση των ορίων του άρθρου 156 §3γ.'
    : `Ο έλεγχος εντοπίζει παράβαση ύψους ${eur(cs.ruleBreach)}. Ο ΑΠΕ δεν μπορεί να εγκριθεί ως έχει.`}
</p>`

  return wrapDocument({
    org: c.org,
    title: 'Φύλλο ελέγχου επί έλαττον δαπανών',
    subject: `Έλεγχος των επί έλαττον δαπανών του ${ord.gen(no)} Α.Π.Ε. του έργου «${p.title}»`,
    protocolNo: null,
    protocolDate: gr(ape.drafted_at),
    legalRef: 'άρθρο 156 §3γ ν. 4412/2016 · εγκύκλιοι 20/2006 και 30/2007',
    bodyHtml: html,
    signatories: [
      { label: 'Ο ανάδοχος', name: k.contractor_name },
      {
        label: 'Ο επιβλέπων', name: c.author?.full_name ?? '',
        capacity: c.author?.specialty ?? undefined,
      },
      {
        label: 'Ο προϊστάμενος της Δ/νσης', name: c.head?.full_name ?? '',
        capacity: c.head?.specialty ?? undefined,
      },
    ],
    recipients: [],
  })
}

/* ================================================================== */
/* 3. ΕΙΣΗΓΗΣΗ ΠΡΟΣ ΤΗ ΔΗΜΟΤΙΚΗ ΕΠΙΤΡΟΠΗ                              */
/* ================================================================== */
export function eisigisiEpitropis(c: ApeDocContext): string {
  const { ape, contract: k, project: p } = c
  const { t } = totalsOf(c)
  const no = ape.serial_no
  const has132 = t.art132Total > 0
  const vat = (x: number) => Math.round((x * k.vat_rate) / 100 * 100) / 100
  const withVat = (x: number) => Math.round((x + vat(x)) * 100) / 100
  const body = AWARD_BODY[k.award_body ?? 'dimotiki_epitropi']

  const tcNeeded = ape.supplementary_needed || t.savings > 0 || has132

  const html = `
${DOC_STYLE}
<p class="lead">Προς τη ${esc(body)}</p>

<h2>Θέμα</h2>
<p>Έγκριση του ${esc(ord.gen(no))} Ανακεφαλαιωτικού Πίνακα Εργασιών${
    has132 ? ' και των εργασιών του άρθρου 132 του ν. 4412/2016' : ''
  } του έργου «${esc(p.title)}», αναδόχου «${esc(k.contractor_name)}».</p>

<h2>Εισήγηση</h2>
<p>Η Διευθύνουσα Υπηρεσία συνέταξε τον ${esc(ord.acc(no))} Ανακεφαλαιωτικό Πίνακα Εργασιών
   του ως άνω έργου, ο οποίος συνοδεύεται από αιτιολογική έκθεση και από το
   φύλλο ελέγχου των επί έλαττον δαπανών.</p>

<p>${esc(ape.reason)}</p>

<table class="cost narrow">
  <tr><td>Αξία αρχικής σύμβασης (χωρίς Φ.Π.Α.)</td>
      <td class="num">${eur(k.initial_value_net)}</td></tr>
  <tr><td>Δαπάνη με τον ${esc(ord.acc(no))} Α.Π.Ε. (χωρίς Φ.Π.Α.)</td>
      <td class="num">${eur(has132 ? t.projectSubtotal2 : t.subtotal2)}</td></tr>
  ${has132 ? `<tr><td>εκ των οποίων εργασίες άρθρου 132</td>
      <td class="num">${eur(t.art132Total)}</td></tr>` : ''}
  <tr class="strong"><td>Συνολική δαπάνη με Φ.Π.Α.</td>
      <td class="num">${eur(withVat(has132 ? t.projectSubtotal2 : t.subtotal2))}</td></tr>
</table>

<p>${t.balanced && !has132
    ? `Ο ${ord.nom(no)} Α.Π.Ε. βρίσκεται σε ισοζύγιο έναντι της αρχικής σύμβασης: η μεταβολή
       των εργασιών απορροφάται από το κονδύλιο των απροβλέπτων, το οποίο απομένει
       ${eur(t.contingencyRemaining)}.`
    : has132
      ? `Ο ${ord.nom(no)} Α.Π.Ε. προσαυξάνει τη σύμβαση κατά ${eur(t.art132Total)}, ήτοι
         ποσοστό ${pct((t.art132Total / k.initial_value_net) * 100)}, εντός του
         ορίου του 15% της παρ. 2 του άρθρου 132.`
      : `Ο ${ord.nom(no)} Α.Π.Ε. ΔΕΝ βρίσκεται σε ισοζύγιο: η αύξηση υπερβαίνει τα διαθέσιμα
         απρόβλεπτα κατά ${eur(-t.contingencyRemaining)}.`}</p>

${tcNeeded
    ? `<p>Για την έγκριση απαιτείται προηγούμενη γνωμοδότηση του οικείου Τεχνικού
       Συμβουλίου Δημοσίων Έργων${ape.tc_opinion_id ? ', η οποία έχει ληφθεί' : ', η οποία εκκρεμεί'}.</p>`
    : '<p>Δεν απαιτείται γνωμοδότηση του Τεχνικού Συμβουλίου.</p>'}

<h2>Προτεινόμενη απόφαση</h2>
<p>Εισηγούμαστε την έγκριση του ${esc(ord.gen(no))} Ανακεφαλαιωτικού Πίνακα Εργασιών${
    has132 ? ' και των εργασιών του άρθρου 132 του ν. 4412/2016' : ''
  } του έργου «${esc(p.title)}», συνολικής δαπάνης
   ${eur(withVat(has132 ? t.projectSubtotal2 : t.subtotal2))} με Φ.Π.Α.</p>`

  return wrapDocument({
    org: c.org,
    title: `Εισήγηση προς τη ${body}`,
    subject: `Έγκριση του ${ord.gen(no)} Α.Π.Ε. του έργου «${p.title}»`,
    protocolNo: null,
    protocolDate: gr(ape.drafted_at),
    legalRef: 'άρθρα 156 και 132 ν. 4412/2016',
    bodyHtml: html,
    signatories: [
      {
        label: 'Ο Προϊστάμενος της Δ/νσης', name: c.head?.full_name ?? '',
        capacity: c.head?.specialty ?? undefined,
      },
    ],
    recipients: [],
  })
}

/* ------------------------------------------------------------------ */
const DOC_STYLE = `<style>
h2{font-size:11.5pt;letter-spacing:.06em;margin:6mm 0 3mm;text-transform:uppercase}
h3{font-size:10.5pt;margin:5mm 0 2mm}
p{margin:0 0 3mm;text-align:justify}
.lead{font-style:italic;color:#333}
ol.hist,ol.terms{margin:0 0 4mm 6mm;padding:0}
ol.hist li,ol.terms li{margin-bottom:2.5mm;text-align:justify}
table{border-collapse:collapse;width:100%;font-size:9.5pt;margin:3mm 0 4mm}
table.cost td,table.cost th{border:.5pt solid #999;padding:1.6mm 2mm}
table.cost.narrow{width:auto;min-width:60%}
table.check td,table.check th{border:.4pt solid #999;padding:1.1mm 1.4mm;font-size:8pt}
table.check th{background:#f2f0ec;font-weight:600;vertical-align:middle;text-align:center}
table.check .idx{font-weight:400;color:#666;font-size:7pt}
table.mini{font-size:9pt}
table.mini td{border-bottom:.4pt solid #ccc;padding:1.2mm 2mm}
table.mini td:first-child{color:#666;width:9mm}
.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.c{text-align:center}
.strong td{font-weight:700;background:#faf9f7}
.warn{background:#fdf6ec}
.two{display:flex;gap:8mm}
.two>div{flex:1}
.verdict{margin-top:4mm;padding:2.5mm 3mm;border-left:2pt solid #999;font-size:10pt}
.verdict.ok{border-color:#2f6f4f;background:#f2f8f4}
.verdict.bad{border-color:#8c3b2e;background:#fbf1ef}
.closing{margin-top:4mm;font-weight:600}
</style>`
