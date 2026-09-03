-- =====================================================================
-- ΣΥΣΤΗΜΑ ΕΠΙΒΛΕΨΗΣ ΔΗΜΟΣΙΩΝ ΕΡΓΩΝ  ("Απόλυτος Οδηγός & Σύστημα Ελέγχου")
-- Migration 0001 : Extensions, schemas, enums (λεξικά τιμών)
-- Πλατφόρμα      : Supabase / PostgreSQL >= 15
-- Νομικό πλαίσιο : ν. 4412/2016, Βιβλίο Ι, Μέρος Β' (άρθρα 134-175),
--                  όπως ισχύει μετά τον ν. 4782/2021 (Α' 36) και τις
--                  μεταγενέστερες τροποποιήσεις (ν. 5218/2025, ν. 5313/2026)
-- =====================================================================

create extension if not exists "pgcrypto";      -- gen_random_uuid()
create extension if not exists "btree_gist";    -- exclusion constraints
create extension if not exists "unaccent";

-- Ιδιωτικό schema για βοηθητικές συναρτήσεις (δεν εκτίθεται στο PostgREST)
create schema if not exists app;

comment on schema app is
  'Εσωτερικές συναρτήσεις ασφαλείας, κανόνων και υπολογισμών. Δεν εκτίθεται μέσω API.';

-- ---------------------------------------------------------------------
-- 1. ΡΟΛΟΙ ΚΑΙ ΦΟΡΕΙΣ
-- ---------------------------------------------------------------------

create type public.role_type as enum (
  'admin',                 -- Διαχειριστής συστήματος
  'proistameni_arxi',      -- Προϊσταμένη Αρχή (άρθρο 2 §2 περ.4 ν.4412/2016)
  'proistamenos_dy',       -- Προϊστάμενος Διευθύνουσας Υπηρεσίας
  'epivlepon',             -- Επιβλέπων Μηχανικός (άρθρο 136 §1-2)
  'voithos_epivlepon',     -- Βοηθός επιβλέποντος / μέλος ομάδας επίβλεψης
  'syntonistis',           -- Συντονιστής ομάδας επίβλεψης (άρθρο 136 §2)
  'ife',                   -- Ιδιωτικός Φορέας Επίβλεψης (άρθρο 136 §3-5)
  'anadochos',             -- Ανάδοχος / εκπρόσωπος αναδόχου
  'techniko_symvoulio',    -- Μέλος Τεχνικού Συμβουλίου
  'epitropi_paralavis',    -- Μέλος Επιτροπής Παραλαβής (άρθρο 172)
  'epitropi_timon',        -- Μέλος Επιτροπής ΠΚΤΜΝΕ (άρθρο 156 §5)
  'theatis'                -- Πρόσβαση μόνο ανάγνωσης
);

comment on type public.role_type is
  'Ρόλοι χρηστών. Κάθε ρόλος αντιστοιχεί σε διακριτά καθήκοντα του ν.4412/2016.';

create type public.party_type as enum (
  'anadochos',
  'epivlepon',
  'dieuthynousa_ypiresia',
  'proistameni_arxi',
  'techniko_symvoulio',
  'epitropi',
  'ife',
  'kyrios_ergou'
);

comment on type public.party_type is
  'Υπόχρεο μέρος για μια ενέργεια/προθεσμία — τεκμηριώνει τον διαχωρισμό ρόλων.';

-- ---------------------------------------------------------------------
-- 2. ΕΡΓΟ & ΣΥΜΒΑΣΗ
-- ---------------------------------------------------------------------

create type public.project_category as enum (
  'odopoiia',                    -- Οδοποιία
  'oikodomika',                  -- Οικοδομικά
  'ydraulika',                   -- Υδραυλικά
  'limenika',                    -- Λιμενικά
  'hlektromichanologika',        -- Ηλεκτρομηχανολογικά
  'viomichanika_energeiaka',     -- Βιομηχανικά - Ενεργειακά
  'prasino',                     -- Πράσινο
  'katharismos_epexergasia',     -- Καθαρισμός & επεξεργασία νερού/υγρών αποβλήτων
  'geotrhseis',
  'loipa'
);

comment on type public.project_category is
  'Κατηγορία έργου. Καθορίζει τις εφαρμοστέες "Ομάδες Εργασιών" '
  '(Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017, ΦΕΚ Β΄1956/2017) που χρησιμοποιούνται '
  'στον έλεγχο του ορίου 20% των επί έλασσον δαπανών (άρθρο 156 §3γ).';

create type public.contract_regime as enum (
  'n4412_meta_n4782',      -- Συμβάσεις με διακήρυξη/ανάθεση υπό το καθεστώς ν.4782/2021
  'n4412_pro_n4782'        -- Μεταβατικές: διακηρύξεις πριν την 01.06.2021
);

comment on type public.contract_regime is
  'Νομικό καθεστώς εκτέλεσης. Κρίσιμο διότι ο ν.4782/2021 (άρθρο 142) εφαρμόζεται '
  'στις διαδικασίες που εκκινούν μετά την έναρξη ισχύος του.';

create type public.supervision_mode as enum (
  'ypiresiaki',            -- Επίβλεψη από υπαλλήλους της Δ.Υ. (άρθρο 136 §1-2)
  'ife',                   -- Ιδιωτικός Φορέας Επίβλεψης (άρθρο 136 §3-5)
  'mikti'                  -- Μικτή / κλιμάκιο επίβλεψης (άρθρο 136 §8)
);

create type public.deadline_kind as enum (
  'synoliki',              -- Συνολική προθεσμία (άρθρο 147 §1)
  'tmimatiki_apokleistiki',-- Τμηματική αποκλειστική
  'tmimatiki_endeiktiki',  -- Τμηματική ενδεικτική
  'oriaki'                 -- Οριακή προθεσμία (άρθρο 147 §4)
);

-- ---------------------------------------------------------------------
-- 3. ΕΓΓΥΗΣΕΙΣ (άρθρο 72)
-- ---------------------------------------------------------------------

create type public.guarantee_type as enum (
  'kalis_ektelesis',       -- Καλής εκτέλεσης — 5% (άρθρο 72 §4)
  'prosthetti',            -- Πρόσθετη εγγύηση για μεγάλες εκπτώσεις (άρθρο 72 §4)
  'prokatavolis',          -- Προκαταβολής — ίση με το ποσό (άρθρο 72 §7, άρθρο 150)
  'kalis_leitourgias',     -- Καλής λειτουργίας
  'dekaton'                -- Κρατήσεις/δεκάτων (παλαιό καθεστώς)
);

create type public.guarantee_status as enum (
  'ekremmei_katathesi',    -- Εκκρεμεί κατάθεση
  'energi',                -- Ενεργή
  'meiomeni_70',           -- Μειωμένη κατά 70% (άρθρο 72 §14 περ.β)
  'apodesmevmeni',         -- Επιστραφείσα
  'katapiptousa'           -- Καταπεσούσα
);

-- ---------------------------------------------------------------------
-- 4. ΜΗΧΑΝΗ ΡΟΗΣ (WORKFLOW / FAIL-SAFE)
-- ---------------------------------------------------------------------

create type public.stage_phase as enum (
  'f0_systasi',            -- Σύσταση φακέλου & ανάληψη καθηκόντων
  'f1_egkatastasi',        -- Εγκατάσταση αναδόχου
  'f2_ektelesi',           -- Εκτέλεση (επαναλαμβανόμενοι κύκλοι)
  'f3_peraiosi',           -- Περαίωση
  'f4_paralavi'            -- Συντήρηση & Παραλαβή
);

create type public.stage_status as enum (
  'locked',                -- Κλειδωμένο: εκκρεμούν προαπαιτούμενα
  'available',             -- Διαθέσιμο προς εκκίνηση
  'in_progress',           -- Σε εξέλιξη
  'pending_approval',      -- Εκκρεμεί έγκριση από άλλο ρόλο
  'completed',             -- Ολοκληρωμένο
  'not_applicable',        -- Δεν εφαρμόζεται (με υποχρεωτική αιτιολόγηση)
  'overdue'                -- Ολοκληρωμένο/εκκρεμές εκπρόθεσμα
);

create type public.recurrence_type as enum (
  'once',                  -- Άπαξ
  'repeating',             -- Επαναλαμβανόμενο (π.χ. λογαριασμοί, ΑΠΕ)
  'continuous',            -- Συνεχές (π.χ. ημερολόγιο)
  'conditional'            -- Υπό αίρεση (π.χ. ποινικές ρήτρες, ενστάσεις)
);

create type public.deadline_basis as enum (
  'ypografi_symvasis',
  'egkrisi_xronodiagrammatos',
  'enarxi_ergasion',
  'lixi_prothesmias',
  'ypovoli_eggrafou',
  'koinopoiisi_praxis',
  'bebaiosi_peratosis',
  'lixi_syntirisis',
  'custom'
);

-- ---------------------------------------------------------------------
-- 5. ΕΓΓΡΑΦΑ
-- ---------------------------------------------------------------------

create type public.document_status as enum (
  'draft',                 -- Πρόχειρο (αυτόματα παραχθέν)
  'submitted',             -- Υποβλήθηκε (από ανάδοχο)
  'under_review',          -- Υπό έλεγχο
  'signed',                -- Υπογεγραμμένο
  'approved',              -- Εγκεκριμένο
  'rejected',              -- Απορριφθέν
  'communicated',          -- Κοινοποιηθέν (άρθρο 143)
  'deemed_approved',       -- Θεωρείται εγκεκριμένο λόγω παρόδου προθεσμίας
  'archived'
);

create type public.signature_kind as enum (
  'apla',                  -- Απλή υπογραφή
  'psifiaki_egkekrimeni',  -- Εγκεκριμένη ψηφιακή υπογραφή (Καν. eIDAS 910/2014)
  'anepifylakta',          -- Υπογραφή αναδόχου ανεπιφύλακτα
  'me_epifylaxi',          -- Υπογραφή αναδόχου με επιφύλαξη (άρθρο 156 §7)
  'arnisi'                 -- Άρνηση υπογραφής
);

-- ---------------------------------------------------------------------
-- 6. ΕΠΙΜΕΤΡΗΣΕΙΣ / ΑΦΑΝΕΙΣ (άρθρο 151)
-- ---------------------------------------------------------------------

create type public.measurement_type as enum (
  'tmimatiki',             -- Τμηματική επιμέτρηση (άρθρο 151 §2)
  'afanon',                -- Διακριτή επιμέτρηση αφανών εργασιών (άρθρο 151 §7)
  'zygisis',               -- Επιμέτρηση με ζύγιση (άρθρο 151 §7)
  'teliki'                 -- Τελική επιμέτρηση (άρθρο 151 §9)
);

create type public.measurement_status as enum (
  'draft',
  'submitted',             -- Υποβλήθηκε από τον ανάδοχο με δήλωση αληθείας
  'sampled',               -- Επελέγη σε δειγματοληπτικό έλεγχο (άρθρο 151 §3)
  'under_check',
  'returned_for_fix',      -- Επεστράφη για διόρθωση (άρθρο 151 §4)
  'approved',
  'deemed_approved',
  'rejected'
);

create type public.inaccuracy_grade as enum (
  'kamia',                 -- Καμία ανακρίβεια
  'anakrivis',             -- Ανακριβής επιμέτρηση (άρθρο 151 §4)
  'psevdis'                -- Ψευδής δήλωση (άρθρο 151 §5-6) — κύρωση/κατάπτωση
);

-- ---------------------------------------------------------------------
-- 7. ΛΟΓΑΡΙΑΣΜΟΙ (άρθρο 152)
-- ---------------------------------------------------------------------

create type public.payment_type as enum (
  'tmimatikos',            -- Τμηματικός (ανακεφαλαιωτικός) λογαριασμός
  'telikos',               -- Τελικός λογαριασμός (άρθρο 152 §)
  'prokatavoli'            -- Λογαριασμός προκαταβολής (άρθρο 150)
);

create type public.payment_status as enum (
  'draft',
  'submitted',
  'under_review',
  'returned_for_fix',
  'approved',
  'deemed_approved',       -- Εγκρίθηκε σιωπηρά μετά την πάροδο 1 μηνός
  'paid',
  'rejected'
);

-- ---------------------------------------------------------------------
-- 8. ΑΠΕ / ΠΚΤΜΝΕ (άρθρα 155-156)
-- ---------------------------------------------------------------------

create type public.ape_type as enum (
  'taktopoiitikos',        -- Τακτοποιητικός (χωρίς αύξηση δαπάνης)
  'me_apravlepta',         -- Με χρήση απροβλέπτων (άρθρο 156 §3β)
  'me_epi_elasson',        -- Με χρήση επί έλασσον δαπανών (άρθρο 156 §3γ)
  'me_pktmne',             -- Με Π.Κ.Τ.Μ.Ν.Ε. (άρθρο 156 §5-6)
  'symplirwmatiki_symvasi',-- Με συμπληρωματική σύμβαση (άρθρο 156 §1)
  'epeigousa_apravlepti'   -- Επείγουσες & απρόβλεπτες πρόσθετες (άρθρο 155)
);

create type public.ape_status as enum (
  'draft',
  'signed_anepifylakta',
  'signed_me_epifylaxi',
  'not_signed',            -- Κοινοποιείται κατ' άρθρο 143
  'tc_opinion_pending',    -- Εκκρεμεί γνωμοδότηση Τεχνικού Συμβουλίου
  'approved',
  'rejected'
);

create type public.new_price_basis as enum (
  'analogi_symvatiki_timi',-- Από όμοιες/ανάλογες συμβατικές τιμές (άρθρο 156 §5α)
  'egkekrimena_analytika', -- Από εγκεκριμένα αναλυτικά τιμολόγια (άρθρο 156 §5β)
  'apologistika'           -- Από απολογιστικά στοιχεία κόστους (άρθρο 156 §5γ)
);

-- ---------------------------------------------------------------------
-- 9. ΠΡΟΘΕΣΜΙΕΣ / ΡΗΤΡΕΣ / ΠΕΡΑΙΩΣΗ
-- ---------------------------------------------------------------------

create type public.extension_type as enum (
  'me_anatheorisi',        -- Παράταση με αναθεώρηση (υπαιτιότητα κυρίου έργου)
  'xoris_anatheorisi'      -- Παράταση χωρίς αναθεώρηση (υπαιτιότητα αναδόχου)
);

create type public.decision_outcome as enum (
  'pending',
  'accepted',
  'partially_accepted',
  'rejected',
  'deemed_accepted'        -- Τεκμήριο σιωπηρής αποδοχής
);

create type public.penalty_kind as enum (
  'poiniki_ritra_prothesmias',  -- Άρθρο 148
  'eidiki_ritra_imerologiou',   -- Άρθρο 146 (100-500 € / ημέρα)
  'ritra_telikis_epimetrisis',  -- Άρθρο 151 §10 (2‰/μήνα, max 6 μήνες)
  'alli'
);

create type public.defect_severity as enum (
  'epousiodes',            -- Επουσιώδη ελαττώματα (άρθρο 168 §3)
  'ousiodes'               -- Ουσιώδη — εφαρμογή άρθρων 159, 160
);

create type public.acceptance_status as enum (
  'not_due',
  'committee_pending',     -- Εκκρεμεί ορισμός επιτροπής
  'in_progress',
  'suspended_defects',     -- Αναστολή λόγω ελαττωμάτων
  'completed',
  'auto_completed'         -- Αυτοδίκαιη παραλαβή (άρθρο 172)
);

-- ---------------------------------------------------------------------
-- 10. ΗΜΕΡΟΛΟΓΙΟ (άρθρο 146)
-- ---------------------------------------------------------------------

create type public.diary_mode as enum (
  'imerisio',              -- Ημερήσιο (κανόνας)
  'evdomadiaio',           -- Εβδομαδιαίο (μικρά έργα)
  'apallagi'               -- Απαλλαγή τήρησης (μικρά έργα)
);

create type public.diary_status as enum (
  'draft',
  'submitted',             -- Συμπληρώθηκε & υπεγράφη ψηφιακά από τεχνικό αναδόχου
  'reviewed',              -- Ελέγχθηκε/διορθώθηκε από επιβλέποντα (2 εργάσιμες)
  'approved',              -- Εγκρίθηκε από προϊστάμενο Δ.Υ.
  'missing'                -- Παράλειψη τήρησης — γενεσιουργός ειδικής ποινικής ρήτρας
);

create type public.weather_condition as enum (
  'aithria','nefosi','vrochi','entoni_vrochi','xioni','pagetos','anemos','kayswnas'
);

-- ---------------------------------------------------------------------
-- 11. ΠΟΙΟΤΗΤΑ & ΕΛΕΓΧΟΙ
-- ---------------------------------------------------------------------

create type public.test_result as enum (
  'symmorfo','mi_symmorfo','ekremmes','akyro'
);

create type public.audit_action as enum (
  'insert','update','delete','status_change','approve','reject','lock_override'
);
