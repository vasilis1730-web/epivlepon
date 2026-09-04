/**
 * Δοκιμή του υπολογιστικού μοντέλου ΑΠΕ έναντι ΠΡΑΓΜΑΤΙΚΩΝ εγκεκριμένων
 * πινάκων της Δ/νσης Τεχνικών Έργων & Υποδομών του Δήμου Ρόδου.
 *
 * Τα αναμενόμενα ποσά δεν είναι επινοημένα: αντιγράφονται από τις
 * αιτιολογικές εκθέσεις που συνοδεύουν τους εγκεκριμένους ΑΠΕ. Αν το
 * μοντέλο αποκλίνει έστω κατά λεπτό, η δοκιμή πέφτει.
 *
 *   node tests/apetotals/harness.mjs
 */
import { build } from 'esbuild'
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '../..')
const OUT = resolve(HERE, 'out')
mkdirSync(OUT, { recursive: true })

/* Το rules.ts εισάγει μόνο τύπους από το types.ts και βοηθούς από το
   format.ts — τα δένουμε όλα σε ένα module χωρίς εξαρτήσεις React. */
await build({
  entryPoints: [resolve(ROOT, 'app/src/lib/rules.ts')],
  outfile: resolve(OUT, 'rules.mjs'),
  bundle: true,
  format: 'esm',
  platform: 'node',
  logLevel: 'silent',
})

const { apeTotals } = await import(resolve(OUT, 'rules.mjs'))

/* ------------------------------------------------------------------ */
/* Βοηθοί                                                             */
/* ------------------------------------------------------------------ */
const eur = n => new Intl.NumberFormat('el-GR',
  { style: 'currency', currency: 'EUR' }).format(n)

let failures = 0

/** Φτιάχνει μία γραμμή που αποδίδει ακριβώς την επιθυμητή δαπάνη. */
const line = (amountInitial, amountNew, opts = {}) => ({
  unit_price: 1,
  qty_initial: amountInitial,
  qty_previous: opts.previous ?? amountInitial,
  qty_new: amountNew,
  funding_source: opts.funding ?? 'symvatiko',
  is_article_132: opts.art132 ?? false,
})

function check(label, actual, expected) {
  const ok = Math.abs(actual - expected) < 0.015
  if (!ok) failures++
  console.log(`   ${ok ? '✓' : '✗'} ${label.padEnd(28)} ${eur(actual).padStart(15)}` +
    (ok ? '' : `   αναμενόταν ${eur(expected)}`))
}

/* ================================================================== */
/* 1. ΚΟΣΚΙΝΟΥ — 1ος ΑΠΕ                                              */
/*    «Κατεπείγουσα άρση επικινδύνων καταπτώσεων ... Δ.Κ. Κοσκινού»    */
/*    Ανάδοχος ΤΕΚΤΕΡ Ε.Ε. — αιτιολογική έκθεση 1/7/2026               */
/* ================================================================== */
console.log('\n═══ ΚΟΣΚΙΝΟΥ — 1ος ΑΠΕ (με εργασίες άρθρου 132) ═══')
{
  const contractWorks = 183_957.48
  const geOePct = 18
  const contractSubtotal1 = 217_069.83   // 183.957,48 + 33.112,35
  const contingency = 32_560.47

  const t = apeTotals(
    [
      // Δύο ομάδες: Χωματουργικά και Σκυροδέματα (αθροιστικά)
      line(66_668.39, 92_502.82),   // ΧΩΜΑΤΟΥΡΓΙΚΑ
      line(117_289.09, 119_047.73), // ΣΚΥΡΟΔΕΜΑΤΑ
      // Υπερσυμβατικές εργασίες άρθρου 132
      line(0, 31_728.76, { art132: true }),
    ],
    { geOePct, contractWorksPlusGeOe: contractSubtotal1, contingencyAmount: contingency },
  )

  check('Άθροισμα Εργασιών ΑΠΕ', t.worksNew, 211_550.55)
  check('Γ.Ε. & Ο.Ε. 18%', t.geOe, 38_079.10)
  check('ΣΥΝΟΛΟ 1', t.subtotal1, 249_629.65)
  check('Χρησιμοποιηθέντα απρόβλ.', t.contingencyUsed, 32_559.82)
  check('Υπόλοιπο απροβλέπτων', t.contingencyRemaining, 0.65)
  check('ΣΥΝΟΛΟ 2 (ισοζύγιο)', t.subtotal2, 249_630.30)
  check('Άρθρο 132 — εργασίες', t.art132Works, 31_728.76)
  check('Άρθρο 132 — ΓΕ & ΟΕ', t.art132GeOe, 5_711.18)
  check('Άρθρο 132 — σύνολο', t.art132Total, 37_439.94)
  check('Δαπάνη έργου — εργασίες', t.projectWorks, 243_279.31)
  check('Δαπάνη έργου — ΓΕ & ΟΕ', t.projectGeOe, 43_790.28)
  check('Δαπάνη έργου — ΣΥΝΟΛΟ 1', t.projectSubtotal1, 287_069.59)
  check('Δαπάνη έργου — ΣΥΝΟΛΟ 2', t.projectSubtotal2, 287_070.24)

  const balanced = t.balanced
  console.log(`   ${balanced ? '✓' : '✗'} ισοζύγιο έναντι σύμβασης`)
  if (!balanced) failures++
}

/* ================================================================== */
/* 2. ΚΑΛΛΙΘΕΑ — 1ος ΑΠΕ (καθαρό ισοζύγιο, χωρίς άρθρο 132)           */
/*    «1η ΣΣ — Συντηρήσεις/επισκευές δημοτικών κτιρίων Δ.Ε. Καλλιθέας» */
/* ================================================================== */
console.log('\n═══ ΚΑΛΛΙΘΕΑ — 1ος ΑΠΕ (καθαρό ισοζύγιο) ═══')
{
  const t = apeTotals(
    [line(23_226.11, 26_596.01)],
    { geOePct: 18, contractWorksPlusGeOe: 27_406.81, contingencyAmount: 4_111.02 },
  )

  check('Άθροισμα Εργασιών ΑΠΕ', t.worksNew, 26_596.01)
  check('Γ.Ε. & Ο.Ε. 18%', t.geOe, 4_787.28)
  check('ΣΥΝΟΛΟ 1', t.subtotal1, 31_383.29)
  check('Υπόλοιπο απροβλέπτων', t.contingencyRemaining, 134.54)
  check('ΣΥΝΟΛΟ 2 (ισοζύγιο)', t.subtotal2, 31_517.83)

  console.log(`   ${t.balanced ? '✓' : '✗'} ισοζύγιο έναντι σύμβασης`)
  if (!t.balanced) failures++
  console.log(`   ${!t.art132Total ? '✓' : '✗'} καμία εργασία άρθρου 132`)
}

/* ================================================================== */
/* 3. Ν. ΡΟΔΟΥ — 2ος ΑΠΕ (μείωση εργασιών, ΑΠΕ επί ΑΠΕ)               */
/*    «Επείγουσες εργασίες αποκατάστασης ζημιών — πυρκαγιές 2023»      */
/* ================================================================== */
console.log('\n═══ Ν. ΡΟΔΟΥ — 2ος ΑΠΕ (επί του 1ου ΑΠΕ) ═══')
{
  // Βάση σύγκρισης εδώ είναι ο ΕΓΚΕΚΡΙΜΕΝΟΣ 1ος ΑΠΕ: Σ1 = 645.175,55
  const t = apeTotals(
    [
      line(546_758.94, 546_702.36, { previous: 546_758.94 }),
      line(0, 81_960.57, { art132: true }),
    ],
    { geOePct: 18, contractWorksPlusGeOe: 645_175.55, contingencyAmount: 21.99 },
  )

  check('Άθροισμα Εργασιών ΑΠΕ', t.worksNew, 546_702.36)
  check('Γ.Ε. & Ο.Ε. 18%', t.geOe, 98_406.42)
  check('ΣΥΝΟΛΟ 1', t.subtotal1, 645_108.78)
  check('Υπόλοιπο απροβλέπτων', t.contingencyRemaining, 88.76)
  check('ΣΥΝΟΛΟ 2', t.subtotal2, 645_197.54)
  check('Άρθρο 132 — ΓΕ & ΟΕ', t.art132GeOe, 14_752.90)
  check('Άρθρο 132 — σύνολο', t.art132Total, 96_713.47)
  check('Δαπάνη έργου — ΣΥΝΟΛΟ 1', t.projectSubtotal1, 741_822.25)
  check('Δαπάνη έργου — ΣΥΝΟΛΟ 2', t.projectSubtotal2, 741_911.01)
}

/* ================================================================== */
/* 4. Ο κανόνας του ισοζυγίου: υπέρβαση απροβλέπτων ΔΕΝ σιωπά          */
/* ================================================================== */
console.log('\n═══ Έλεγχος υπέρβασης απροβλέπτων ═══')
{
  const t = apeTotals(
    [line(100_000, 160_000)],
    { geOePct: 18, contractWorksPlusGeOe: 118_000, contingencyAmount: 17_700 },
  )
  const ok = t.contingencyOverrun && !t.balanced
  if (!ok) failures++
  console.log(`   ${ok ? '✓' : '✗'} η υπέρβαση εντοπίζεται (υπόλοιπο ${eur(t.contingencyRemaining)})`)
}

/* ------------------------------------------------------------------ */
rmSync(OUT, { recursive: true, force: true })
console.log(
  failures === 0
    ? '\nΟΛΑ ΤΑ ΣΥΝΟΛΑ ΣΥΜΦΩΝΟΥΝ ΜΕ ΤΟΥΣ ΕΓΚΕΚΡΙΜΕΝΟΥΣ ΠΙΝΑΚΕΣ.\n'
    : `\nΑΠΟΤΥΧΙΑ: ${failures} αποκλίσεις από τα επίσημα έγγραφα.\n`,
)
process.exit(failures === 0 ? 0 : 1)
