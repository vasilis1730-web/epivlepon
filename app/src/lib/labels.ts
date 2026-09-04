import type { AwardBody,
  PartyType, RoleType, StagePhase, StageStatus, RecurrenceType,
  MeasurementStatus, PaymentStatus, ApeStatus, ApeType,
  GuaranteeType, GuaranteeStatus, DiaryStatus, ProjectCategory,
} from './types'

export const PARTY: Record<PartyType, string> = {
  anadochos: 'Ανάδοχος',
  epivlepon: 'Επιβλέπων',
  dieuthynousa_ypiresia: 'Διευθύνουσα Υπηρεσία',
  proistameni_arxi: 'Προϊσταμένη Αρχή',
  techniko_symvoulio: 'Τεχνικό Συμβούλιο',
  epitropi: 'Επιτροπή',
  ife: 'Ιδιωτικός Φορέας Επίβλεψης',
  kyrios_ergou: 'Κύριος του Έργου',
}

export const ROLE: Record<RoleType, string> = {
  admin: 'Διαχειριστής',
  proistameni_arxi: 'Προϊσταμένη Αρχή',
  proistamenos_dy: 'Προϊστάμενος Δ.Υ.',
  epivlepon: 'Επιβλέπων Μηχανικός',
  voithos_epivlepon: 'Βοηθός Επιβλέποντος',
  syntonistis: 'Συντονιστής Επίβλεψης',
  ife: 'Ιδιωτικός Φορέας Επίβλεψης',
  anadochos: 'Ανάδοχος',
  techniko_symvoulio: 'Τεχνικό Συμβούλιο',
  epitropi_paralavis: 'Επιτροπή Παραλαβής',
  epitropi_timon: 'Επιτροπή Τιμών',
  theatis: 'Θεατής',
}

export const PHASE: Record<StagePhase, { key: string; name: string }> = {
  f0_systasi:     { key: 'Φ0', name: 'Σύσταση φακέλου & ανάληψη καθηκόντων' },
  f1_egkatastasi: { key: 'Φ1', name: 'Εγκατάσταση αναδόχου' },
  f2_ektelesi:    { key: 'Φ2', name: 'Εκτέλεση' },
  f3_peraiosi:    { key: 'Φ3', name: 'Περαίωση' },
  f4_paralavi:    { key: 'Φ4', name: 'Συντήρηση & παραλαβή' },
}

export const STAGE_STATUS: Record<StageStatus, string> = {
  locked: 'Κλειδωμένο',
  available: 'Διαθέσιμο',
  in_progress: 'Σε εξέλιξη',
  pending_approval: 'Προς έγκριση',
  completed: 'Ολοκληρωμένο',
  not_applicable: 'Δεν εφαρμόζεται',
  overdue: 'Εκπρόθεσμο',
}

export const RECURRENCE: Record<RecurrenceType, string> = {
  once: 'άπαξ',
  repeating: 'επαναλαμβανόμενο',
  continuous: 'συνεχές',
  conditional: 'υπό αίρεση',
}

export const MEASUREMENT_STATUS: Record<MeasurementStatus, string> = {
  draft: 'Πρόχειρη',
  submitted: 'Υποβλήθηκε',
  sampled: 'Σε δειγματοληπτικό έλεγχο',
  under_check: 'Υπό έλεγχο',
  returned_for_fix: 'Επεστράφη για διόρθωση',
  approved: 'Εγκεκριμένη',
  deemed_approved: 'Σιωπηρά εγκεκριμένη',
  rejected: 'Απορρίφθηκε',
}

export const PAYMENT_STATUS: Record<PaymentStatus, string> = {
  draft: 'Πρόχειρος',
  submitted: 'Υποβλήθηκε',
  under_review: 'Υπό έλεγχο',
  returned_for_fix: 'Επεστράφη για συμπλήρωση',
  approved: 'Εγκεκριμένος',
  deemed_approved: 'Σιωπηρά εγκεκριμένος',
  paid: 'Πληρωμένος',
  rejected: 'Απορρίφθηκε',
}

export const APE_STATUS: Record<ApeStatus, string> = {
  draft: 'Σε σύνταξη',
  signed_anepifylakta: 'Υπεγράφη ανεπιφύλακτα',
  signed_me_epifylaxi: 'Υπεγράφη με επιφύλαξη',
  not_signed: 'Δεν υπεγράφη — κοινοποιήθηκε',
  tc_opinion_pending: 'Εκκρεμεί γνωμοδότηση Τ.Σ.',
  approved: 'Εγκεκριμένος',
  rejected: 'Απορρίφθηκε',
}

export const APE_TYPE: Record<ApeType, string> = {
  taktopoiitikos: 'Τακτοποιητικός',
  me_apravlepta: 'Με χρήση απροβλέπτων',
  me_epi_elasson: 'Με επί έλασσον δαπάνες',
  me_pktmne: 'Με Π.Κ.Τ.Μ.Ν.Ε.',
  symplirwmatiki_symvasi: 'Με συμπληρωματική σύμβαση',
  epeigousa_apravlepti: 'Επείγουσες & απρόβλεπτες (άρθρο 155)',
}

export const GUARANTEE_TYPE: Record<GuaranteeType, string> = {
  kalis_ektelesis: 'Καλής εκτέλεσης',
  prosthetti: 'Πρόσθετη',
  prokatavolis: 'Προκαταβολής',
  kalis_leitourgias: 'Καλής λειτουργίας',
  dekaton: 'Δεκάτων',
}

export const GUARANTEE_STATUS: Record<GuaranteeStatus, string> = {
  ekremmei_katathesi: 'Εκκρεμεί κατάθεση',
  energi: 'Ενεργή',
  meiomeni_70: 'Μειωμένη κατά 70%',
  apodesmevmeni: 'Επιστράφηκε',
  katapiptousa: 'Καταπεσούσα',
}

export const DIARY_STATUS: Record<DiaryStatus, string> = {
  draft: 'Πρόχειρη',
  submitted: 'Υποβλήθηκε',
  reviewed: 'Ελέγχθηκε',
  approved: 'Εγκεκριμένη',
  missing: 'Λείπει',
}

export const CATEGORY: Record<ProjectCategory, string> = {
  odopoiia: 'Οδοποιία',
  oikodomika: 'Οικοδομικά',
  ydraulika: 'Υδραυλικά',
  limenika: 'Λιμενικά',
  hlektromichanologika: 'Ηλεκτρομηχανολογικά',
  viomichanika_energeiaka: 'Βιομηχανικά - Ενεργειακά',
  prasino: 'Πράσινο',
  katharismos_epexergasia: 'Καθαρισμός & επεξεργασία',
  geotrhseis: 'Γεωτρήσεις',
  loipa: 'Λοιπά',
}

export const WEATHER: Record<string, string> = {
  aithria: 'Αίθριος',
  nefosi: 'Νεφώσεις',
  vrochi: 'Βροχή',
  entoni_vrochi: 'Έντονη βροχή',
  xioni: 'Χιόνι',
  pagetos: 'Παγετός',
  anemos: 'Ισχυροί άνεμοι',
  kayswnas: 'Καύσωνας',
}

/** Μετατροπή αναγνωριστικού διάταξης σε αναγνώσιμη παραπομπή. */
const PARAGRAPH_ALIAS: Record<string, string> = {
  '1e': '1ε', '3a': '3α', '3b': '3β', '3c': '3γ', '14b': '14β',
}

export function formatLegalRef(ref: string | null | undefined): string {
  if (!ref) return ''
  if (ref === 'PD305/1996') return 'π.δ. 305/1996'
  if (ref === 'YA38107/2017') return 'Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017'
  if (ref === 'N4727/2020') return 'ν. 4727/2020 άρθρο 76'
  if (ref.startsWith('N4412/')) {
    const [article, paragraph] = ref.slice(6).split('/')
    const art = article.replace('A', 'Α')
    return paragraph
      ? `άρθρο ${art} §${PARAGRAPH_ALIAS[paragraph] ?? paragraph}`
      : `άρθρο ${art}`
  }
  return ref
}

/** Σύντομη μορφή για ετικέτες (chips). */
export function shortLegalRef(ref: string | null | undefined): string {
  const full = formatLegalRef(ref)
  return full.replace('ν. 4412/2016 ', '').replace('Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017', 'Υ.Α. 38107/2017')
}

export const AWARD_BODY: Record<AwardBody, string> = {
  dimotiki_epitropi: 'Δημοτική Επιτροπή',
  oikonomiki_epitropi: 'Οικονομική Επιτροπή',
  dimotiko_symvoulio: 'Δημοτικό Συμβούλιο',
  dioikitiko_symvoulio: 'Διοικητικό Συμβούλιο',
  allo: 'Άλλο όργανο',
}
