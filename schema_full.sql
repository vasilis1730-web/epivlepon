-- ===================================================================
-- ΣΥΣΤΗΜΑ ΕΠΙΒΛΕΨΗΣ ΔΗΜΟΣΙΩΝ ΕΡΓΩΝ — ΕΝΙΑΙΟ SQL SCHEMA
-- Παράχθηκε: 2026-09-03
-- Σειρά: 0001 → 0019, 0021 → 0023. Το 0020_demo_seed.sql είναι ΠΡΟΑΙΡΕΤΙΚΟ
-- (δοκιμαστικά δεδομένα) και παρατίθεται τελευταίο.
-- ===================================================================


-- >>>>>>>>>>>>>>>>>>>> 0001_extensions_enums.sql <<<<<<<<<<<<<<<<<<<<

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

-- >>>>>>>>>>>>>>>>>>>> 0002_core_org_users.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0002 : Φορέας, χρήστες, ρόλοι, νομικές παραπομπές, audit trail
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 ΝΟΜΙΚΕΣ ΠΑΡΑΠΟΜΠΕΣ
--     Κεντρικό μητρώο διατάξεων. ΚΑΘΕ στάδιο, ενέργεια, έγγραφο και
--     κανόνας του συστήματος δείχνει εδώ (απαίτηση: αυστηρή νομική
--     τεκμηρίωση). Ενημερώνεται χωρίς αλλαγή κώδικα.
-- ---------------------------------------------------------------------
create table public.legal_refs (
  id              text primary key,                    -- π.χ. 'N4412/151/7'
  law             text not null,                       -- 'ν. 4412/2016'
  article         text not null,                       -- '151'
  paragraph       text,                                -- '7'
  title           text not null,                       -- 'Επιμετρήσεις — αφανείς εργασίες'
  fek             text,                                -- 'Α΄ 147/08.08.2016'
  amended_by      text[],                              -- {'ν. 4782/2021 άρθρο 70'}
  in_force_from   date,
  in_force_to     date,                                -- null = ισχύουσα
  url             text,
  notes           text,
  created_at      timestamptz not null default now()
);

comment on table public.legal_refs is
  'Μητρώο νομικών διατάξεων. Κάθε βήμα/έγγραφο/κανόνας φέρει υποχρεωτικά '
  'παραπομπή εδώ (fail-safe τεκμηρίωσης).';

-- ---------------------------------------------------------------------
-- 2.2 ΦΟΡΕΑΣ (Δήμος / Διεύθυνση) — υποστήριξη πολλαπλών υπηρεσιών
-- ---------------------------------------------------------------------
create table public.organizations (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,                       -- 'Δήμος Ρόδου'
  unit            text,                                -- 'Δ/νση Τεχνικών Έργων & Υποδομών'
  afm             text,
  address         text,
  phone           text,
  email           text,
  logo_path       text,                                -- storage: letterhead/λογότυπο
  letterhead_html text,                                -- Επικεφαλίδα εγγράφων
  created_at      timestamptz not null default now(),
  constraint organizations_afm_chk check (afm is null or afm ~ '^[0-9]{9}$')
);

-- ---------------------------------------------------------------------
-- 2.3 ΧΡΗΣΤΕΣ — προφίλ συνδεδεμένο με auth.users του Supabase
-- ---------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key,                    -- = auth.users.id
  org_id          uuid not null references public.organizations(id) on delete restrict,
  full_name       text not null,
  email           text not null,
  phone           text,
  specialty       text,                                -- 'ΠΕ Μηχανολόγος Μηχανικός'
  grade           text,                                -- 'ΠΕ/ΤΕ' κ.λπ.
  registry_no     text,                                -- Αρ. Μητρώου ΤΕΕ
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on column public.profiles.id is
  'Ταυτίζεται με auth.users.id του Supabase (FK προστίθεται στο 0012 ή χειροκίνητα).';

-- Καθολικοί ρόλοι (ανεξάρτητοι έργου): admin, προϊστάμενος Δ.Υ., κ.λπ.
create table public.org_roles (
  id              bigint generated always as identity primary key,
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  org_id          uuid not null references public.organizations(id) on delete cascade,
  role            public.role_type not null,
  valid_from      date not null default current_date,
  valid_to        date,
  decision_ada    text,                                -- ΑΔΑ απόφασης τοποθέτησης
  unique (profile_id, org_id, role)
);

-- ---------------------------------------------------------------------
-- 2.4 ΑΝΑΔΟΧΟΙ
-- ---------------------------------------------------------------------
create table public.contractors (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations(id) on delete restrict,
  name               text not null,
  legal_form         text,                             -- Α.Ε. / Ο.Ε. / Ατομική / Κ/Ξ
  afm                text not null,
  doy                text,
  gemi               text,
  meep_mieedde       text,                             -- Αρ. ΜΗ.Ε.Ε.Δ.Ε. (πρώην ΜΕΕΠ)
  categories         text[],                           -- Κατηγορίες/τάξεις πτυχίου
  legal_rep_name     text,
  legal_rep_afm      text,
  address            text,
  email              text not null,
  phone              text,
  is_joint_venture   boolean not null default false,   -- Κοινοπραξία (άρθρο 140)
  jv_members         jsonb,                            -- [{name, afm, percent}]
  created_at         timestamptz not null default now(),
  constraint contractors_afm_chk check (afm ~ '^[0-9]{9}$'),
  unique (org_id, afm)
);

comment on column public.contractors.jv_members is
  'Μέλη κοινοπραξίας και ποσοστά — άρθρο 140 ν.4412/2016 (αλληλέγγυα ευθύνη).';

-- ---------------------------------------------------------------------
-- 2.5 ΙΔΙΩΤΙΚΟΣ ΦΟΡΕΑΣ ΕΠΙΒΛΕΨΗΣ (άρθρο 136 §3-5)
-- ---------------------------------------------------------------------
create table public.private_supervisors (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  afm                text not null,
  certification_no   text,                             -- Αρ. πιστοποίησης / μητρώου
  certification_to   date,
  email              text,
  phone              text,
  created_at         timestamptz not null default now()
);

comment on table public.private_supervisors is
  'Πιστοποιημένοι Ιδιωτικοί Φορείς Επίβλεψης — άρθρο 136 §3 ν.4412/2016. '
  'Η αμοιβή τους βαρύνει αποκλειστικά τον ανάδοχο.';

-- ---------------------------------------------------------------------
-- 2.6 AUDIT TRAIL — append-only, μη διαγράψιμο
-- ---------------------------------------------------------------------
create table public.audit_log (
  id              bigint generated always as identity primary key,
  occurred_at     timestamptz not null default now(),
  actor_id        uuid,                                -- profiles.id (nullable: system)
  actor_role      public.role_type,
  table_name      text not null,
  record_id       text not null,
  action          public.audit_action not null,
  project_id      uuid,
  old_data        jsonb,
  new_data        jsonb,
  reason          text,                                -- αιτιολόγηση (π.χ. lock_override)
  ip              inet
);

create index audit_log_project_idx on public.audit_log (project_id, occurred_at desc);
create index audit_log_record_idx  on public.audit_log (table_name, record_id);

comment on table public.audit_log is
  'Αμετάβλητο ιστορικό ενεργειών. Καμία διαγραφή/ενημέρωση δεν επιτρέπεται '
  '(βλ. πολιτικές RLS στο 0012) — τεκμηριώνει τη διοικητική αλυσίδα ευθύνης.';

-- ---------------------------------------------------------------------
-- 2.7 Γενικός trigger ενημέρωσης updated_at
-- ---------------------------------------------------------------------
create or replace function app.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger trg_profiles_touch
  before update on public.profiles
  for each row execute function app.touch_updated_at();

-- >>>>>>>>>>>>>>>>>>>> 0003_projects_contracts.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0003 : Έργα, συμβάσεις, ανάθεση καθηκόντων, προθεσμίες,
--                  εγγυήσεις, προκαταβολές
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 ΕΡΓΟ
-- ---------------------------------------------------------------------
create table public.projects (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid not null references public.organizations(id) on delete restrict,
  code                  text not null,                  -- Εσωτερικός κωδικός έργου
  title                 text not null,
  category              public.project_category not null,
  cpv                   text,
  ka_budget_code        text,                           -- Κ.Α. προϋπολογισμού
  funding_source        text,                           -- ΣΑΤΑ / ΠΔΕ / ΕΣΠΑ / Ίδιοι πόροι
  mis_code              text,                           -- Κωδικός ΟΠΣ (αν υπάρχει)
  study_budget_net      numeric(14,2) not null,         -- Προϋπολογισμός μελέτης (χωρίς ΦΠΑ)
  estimated_value_net   numeric(14,2) not null,         -- Εκτιμώμενη αξία (άρθρο 6)
  vat_rate              numeric(5,2)  not null default 24.00,
  tender_publication_at date,                           -- Ημ/νία δημοσίευσης διακήρυξης
  adam_tender           text,                           -- ΑΔΑΜ διακήρυξης
  award_decision_ada    text,                           -- ΑΔΑ απόφασης κατακύρωσης
  location              text,
  latitude              numeric(9,6),
  longitude             numeric(9,6),
  is_archived           boolean not null default false,
  created_by            uuid references public.profiles(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (org_id, code),
  constraint projects_amounts_chk check (study_budget_net > 0 and estimated_value_net > 0)
);

comment on column public.projects.tender_publication_at is
  'Καθορίζει το εφαρμοστέο καθεστώς (ν.4782/2021 vs προγενέστερο) και '
  'χρησιμοποιείται για την αυτόματη επιλογή του contract_regime.';

create trigger trg_projects_touch
  before update on public.projects
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------
-- 3.2 ΣΥΜΒΑΣΗ (άρθρο 135)
-- ---------------------------------------------------------------------
create table public.contracts (
  id                      uuid primary key default gen_random_uuid(),
  project_id              uuid not null unique references public.projects(id) on delete cascade,
  contractor_id           uuid not null references public.contractors(id) on delete restrict,
  regime                  public.contract_regime not null default 'n4412_meta_n4782',
  supervision_mode        public.supervision_mode not null default 'ypiresiaki',
  private_supervisor_id   uuid references public.private_supervisors(id),

  -- Στοιχεία υπογραφής
  contract_no             text not null,
  signed_at               date not null,                -- Αφετηρία ΟΛΩΝ των προθεσμιών (άρθρο 147 §2)
  adam_contract           text,                         -- ΑΔΑΜ σύμβασης (ν.4013/2011)
  ada_contract            text,

  -- Οικονομικά αρχικής σύμβασης (όλα χωρίς ΦΠΑ)
  discount_pct            numeric(6,3) not null,        -- Μέση τεκμαρτή έκπτωση %
  works_value_net         numeric(14,2) not null,       -- Δαπάνη εργασιών μετά έκπτωση
  ge_oe_pct               numeric(5,2)  not null default 18.00,   -- ΓΕ & ΟΕ
  ge_oe_amount            numeric(14,2) not null default 0,
  contingency_pct         numeric(5,2)  not null,       -- Απρόβλεπτα 9% ή 15% (άρθρο 156 §3β)
  contingency_amount      numeric(14,2) not null default 0,
  revision_amount         numeric(14,2) not null default 0,       -- Αναθεώρηση
  initial_value_net       numeric(14,2) not null,       -- ΑΞΙΑ ΑΡΧΙΚΗΣ ΣΥΜΒΑΣΗΣ (βάση ελέγχων 50%/15%/10%)
  vat_rate                numeric(5,2)  not null default 24.00,
  total_with_vat          numeric(14,2) generated always as
                            (round(initial_value_net * (1 + vat_rate/100), 2)) stored,

  -- Προθεσμίες (άρθρο 147)
  total_duration_days     integer not null,             -- Συνολική προθεσμία σε ημέρες
  works_start_deadline    date,                         -- ≤ 30 ημ. από υπογραφή (άρθρο 145 §2)
  schedule_submit_days    integer not null default 15,  -- 15-30 ημ. (άρθρο 145 §1)
  original_end_date       date not null,                -- signed_at + total_duration_days
  current_end_date        date not null,                -- Μετά τις εγκεκριμένες παρατάσεις
  oriaki_end_date         date,                         -- Οριακή προθεσμία (άρθρο 147 §4)

  -- Συντήρηση & παραλαβή
  maintenance_months      integer not null default 15,  -- Άρθρο 171 (γενικά 15 μήνες)

  -- Ρήτρες
  has_prim_clause         boolean not null default false, -- Ρήτρα πρόσθετης καταβολής (άρθρο 149)
  daily_penalty_basis     numeric(14,2),                  -- Βάση υπολογισμού ποινικών ρητρών (άρθρο 148)
  diary_mode              public.diary_mode not null default 'imerisio',
  diary_penalty_per_day   numeric(8,2) not null default 100.00,   -- 100-500 € (άρθρο 146)

  status                  text not null default 'active',
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  constraint contracts_discount_chk    check (discount_pct >= 0 and discount_pct < 100),
  constraint contracts_contingency_chk check (contingency_pct in (9.00, 15.00)),
  constraint contracts_duration_chk    check (total_duration_days > 0),
  constraint contracts_dates_chk       check (original_end_date > signed_at
                                              and current_end_date >= original_end_date),
  constraint contracts_schedule_chk    check (schedule_submit_days between 15 and 30),
  constraint contracts_diary_pen_chk   check (diary_penalty_per_day between 100 and 500),
  constraint contracts_ife_chk         check (
        (supervision_mode = 'ife' and private_supervisor_id is not null)
     or (supervision_mode <> 'ife')),
  constraint contracts_status_chk      check (status in
        ('active','suspended','dissolved','contractor_default','completed','accepted'))
);

comment on column public.contracts.initial_value_net is
  'Αξία αρχικής σύμβασης χωρίς αναθεώρηση και ΦΠΑ. Βάση υπολογισμού των ορίων: '
  '50% (άρθρο 156 §1), 15% (§3α), 10% επί έλασσον (§3γ).';
comment on column public.contracts.contingency_pct is
  'Απρόβλεπτες δαπάνες: 9% για έργα προϋπολογισμού ίσου/μεγαλύτερου του ορίου '
  'του άρθρου 5, 15% για μικρότερα (άρθρο 156 §3β ν.4412/2016).';
comment on column public.contracts.maintenance_months is
  'Χρόνος υποχρεωτικής συντήρησης — γενικά 15 μήνες, έως 5 έτη σε ειδικές '
  'περιπτώσεις, δυνατή μείωση σε έργα < 250.000 € (άρθρο 171).';

create trigger trg_contracts_touch
  before update on public.contracts
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------
-- 3.3 ΑΝΑΘΕΣΗ ΚΑΘΗΚΟΝΤΩΝ ΑΝΑ ΕΡΓΟ (άρθρο 136 §1-2, §8)
-- ---------------------------------------------------------------------
create table public.project_assignments (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  profile_id      uuid references public.profiles(id) on delete restrict,
  contractor_id   uuid references public.contractors(id) on delete restrict,
  role            public.role_type not null,
  is_coordinator  boolean not null default false,       -- Συντονιστής ομάδας (άρθρο 136 §2)
  duties          text,                                 -- Σαφώς κατανεμημένα καθήκοντα
  decision_no     text,                                 -- Αρ. απόφασης ορισμού
  decision_ada    text,
  decision_date   date,
  valid_from      date not null default current_date,
  valid_to        date,
  legal_ref_id    text references public.legal_refs(id),
  created_at      timestamptz not null default now(),
  constraint pa_subject_chk check (
       (profile_id is not null and contractor_id is null)
    or (profile_id is null and contractor_id is not null))
);

create unique index project_assignments_active_role_idx
  on public.project_assignments (project_id, profile_id, role)
  where valid_to is null;

comment on table public.project_assignments is
  'Ανάθεση καθηκόντων ανά έργο. Ο ορισμός επιβλέποντος με ρητή απόφαση της '
  'Διευθύνουσας Υπηρεσίας είναι προαπαιτούμενο για την εκκίνηση της ροής '
  '(άρθρο 136 §1-2 ν.4412/2016).';

-- Τεχνικοί του αναδόχου (άρθρο 139) — και υπεύθυνος ημερολογίου (άρθρο 146)
create table public.contractor_staff (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null references public.projects(id) on delete cascade,
  full_name            text not null,
  specialty            text not null,
  registry_no          text,
  role_title           text not null,                  -- 'Προϊστάμενος εργοταξίου', 'Τεχνικός ημερολογίου'
  is_site_manager      boolean not null default false,
  is_diary_keeper      boolean not null default false, -- Άρθρο 146 §1
  is_safety_technician boolean not null default false, -- Τεχνικός ασφαλείας
  declared_at          date not null,
  accepted_at          date,
  removed_at           date,
  legal_ref_id         text references public.legal_refs(id),
  created_at           timestamptz not null default now()
);

create unique index contractor_staff_one_diary_keeper_idx
  on public.contractor_staff (project_id)
  where is_diary_keeper and removed_at is null;

-- ---------------------------------------------------------------------
-- 3.4 ΠΡΟΘΕΣΜΙΕΣ ΣΥΜΒΑΣΗΣ (άρθρο 147)
-- ---------------------------------------------------------------------
create table public.contract_deadlines (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  kind            public.deadline_kind not null,
  title           text not null,
  description     text,
  original_date   date not null,
  current_date_   date not null,                        -- Μετά παρατάσεις/αναστολές
  completed_at    date,
  legal_ref_id    text references public.legal_refs(id) ,
  created_at      timestamptz not null default now(),
  constraint cd_dates_chk check (current_date_ >= original_date)
);

create unique index contract_deadlines_one_total_idx
  on public.contract_deadlines (project_id)
  where kind = 'synoliki';

-- ---------------------------------------------------------------------
-- 3.5 ΕΓΓΥΗΣΕΙΣ (άρθρο 72)
-- ---------------------------------------------------------------------
create table public.guarantees (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  gtype              public.guarantee_type not null,
  issuer             text not null,                    -- Τράπεζα / ΤΜΕΔΕ
  guarantee_no       text not null,
  issued_at          date not null,
  valid_to           date,                             -- null = αόριστης διάρκειας
  original_amount    numeric(14,2) not null check (original_amount > 0),
  current_amount     numeric(14,2) not null,
  pct_of_contract    numeric(6,3),                     -- 5,000 για καλής εκτέλεσης
  status             public.guarantee_status not null default 'energi',
  covers_ape_id      uuid,                             -- Συμπληρωματική για ΑΠΕ
  legal_ref_id       text references public.legal_refs(id),
  notes              text,
  created_at         timestamptz not null default now(),
  unique (project_id, gtype, guarantee_no),
  constraint guarantees_current_chk check (current_amount >= 0
                                           and current_amount <= original_amount)
);

comment on table public.guarantees is
  'Εγγυητικές επιστολές. Καλής εκτέλεσης 5% επί της εκτιμώμενης αξίας (άρθρο 72 §4)· '
  'εγγύηση προκαταβολής ίση με το ποσό της προκαταβολής (άρθρο 72 §7).';

-- Ιστορικό μειώσεων / αποδεσμεύσεων — ΤΟ ΚΡΙΣΙΜΟ ΒΗΜΑ "ΜΕΙΩΣΕΙΣ ΕΓΓΥΗΣΕΩΝ"
create table public.guarantee_events (
  id                 uuid primary key default gen_random_uuid(),
  guarantee_id       uuid not null references public.guarantees(id) on delete cascade,
  event_type         text not null,                    -- 'meiosi_70','apodesmevsi','katapt','ananeosi'
  reduction_pct      numeric(6,3),
  amount_before      numeric(14,2) not null,
  amount_after       numeric(14,2) not null,
  trigger_event      text not null,                    -- 'egkrisi_telikis_epimetrisis' κ.λπ.
  trigger_ref_id     uuid,                             -- FK προς την πράξη που τη θεμελιώνει
  decision_no        text,
  decision_date      date not null,
  decision_ada       text,
  legal_ref_id       text references public.legal_refs(id),
  performed_by       uuid references public.profiles(id),
  created_at         timestamptz not null default now(),
  constraint ge_type_chk check (event_type in
        ('meiosi_70','apodesmevsi','merikia_apodesmevsi','katapt','ananeosi','avxisi')),
  constraint ge_amounts_chk check (amount_after >= 0)
);

comment on table public.guarantee_events is
  'Μειώσεις/αποδεσμεύσεις εγγυήσεων. Κατά το άρθρο 72 §14 περ. β΄ ν.4412/2016 η '
  'εγγύηση καλής εκτέλεσης ΜΕΙΩΝΕΤΑΙ ΚΑΤΑ 70% αμέσως μετά την ΕΓΚΡΙΣΗ ΤΗΣ ΤΕΛΙΚΗΣ '
  'ΕΠΙΜΕΤΡΗΣΗΣ, και επιστρέφεται στο σύνολό της μετά την έγκριση του πρωτοκόλλου '
  'παραλαβής και του τελικού λογαριασμού. Το σύστημα δεν επιτρέπει καταχώριση '
  'μείωσης 70% χωρίς εγκεκριμένη τελική επιμέτρηση (βλ. 0011).';

-- ---------------------------------------------------------------------
-- 3.6 ΠΡΟΚΑΤΑΒΟΛΗ (άρθρο 150)
-- ---------------------------------------------------------------------
create table public.advances (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  requested_at       date,
  approved_at        date,
  decision_ada       text,
  amount             numeric(14,2) not null check (amount > 0),
  pct_of_contract    numeric(6,3) not null,            -- ≤ 15% (άρθρο 150)
  purpose            text not null,                    -- 'egkatastasi' (≤5%/7%) | 'ylika_exoplismos' (≤10%)
  interest_rate      numeric(6,4),                     -- Επιτόκιο εντόκου προκαταβολής
  guarantee_id       uuid references public.guarantees(id),
  amortized_amount   numeric(14,2) not null default 0,
  fully_amortized_at date,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint advances_pct_chk     check (pct_of_contract > 0 and pct_of_contract <= 15),
  constraint advances_purpose_chk check (purpose in ('egkatastasi','ylika_exoplismos'))
);

comment on table public.advances is
  'Προκαταβολές — έως 15% της αξίας της σύμβασης χωρίς αναθεώρηση και ΦΠΑ: '
  'έως 5% (ή 7% σε έργα με εξαιρετικά υψηλό κόστος εκκίνησης) για εγκαταστάσεις '
  'και έως 10% για προμήθεια υλικών/εξοπλισμού (άρθρο 150 ν.4412/2016). '
  'Απαιτείται ισόποση εγγυητική επιστολή (άρθρο 72 §7).';

-- >>>>>>>>>>>>>>>>>>>> 0004_budget_workgroups.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0004 : Ομάδες εργασιών, τιμολόγιο, προϋπολογισμός, νέες τιμές
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 ΟΜΑΔΕΣ ΕΡΓΑΣΙΩΝ
--     Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017 (ΦΕΚ Β΄1956/07.06.2017)
--     «Καθορισμός Ομάδων εργασιών ανά κατηγορία έργων».
--     Απαραίτητο για τον έλεγχο του ορίου 20% ανά ομάδα (άρθρο 156 §3γ).
-- ---------------------------------------------------------------------
create table public.work_groups (
  id              bigint generated always as identity primary key,
  category        public.project_category not null,
  code            text not null,                       -- 'A', 'B', 'Γ' ...
  title           text not null,                       -- 'Χωματουργικά', 'Τεχνικά έργα' ...
  legal_ref_id    text references public.legal_refs(id),
  unique (category, code)
);

comment on table public.work_groups is
  'Ομάδες εργασιών ανά κατηγορία έργου (Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017). '
  'Ο περιορισμός των επί έλασσον δαπανών (20% ανά ομάδα) υπολογίζεται πάνω σε αυτές.';

-- ---------------------------------------------------------------------
-- 4.2 ΕΚΔΟΣΕΙΣ ΠΡΟΫΠΟΛΟΓΙΣΜΟΥ
--     v0 = αρχική σύμβαση, v1..vN = εγκεκριμένοι ΑΠΕ
-- ---------------------------------------------------------------------
create table public.budget_versions (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  version_no      integer not null,                    -- 0 = αρχική σύμβαση
  label           text not null,                       -- 'Αρχική Σύμβαση', '1ος ΑΠΕ'
  ape_id          uuid,                                -- FK ορίζεται στο 0009
  is_current      boolean not null default false,
  approved_at     date,
  total_net       numeric(14,2) not null default 0,
  created_at      timestamptz not null default now(),
  unique (project_id, version_no)
);

create unique index budget_versions_one_current_idx
  on public.budget_versions (project_id) where is_current;

-- ---------------------------------------------------------------------
-- 4.3 ΑΡΘΡΑ ΤΙΜΟΛΟΓΙΟΥ / ΠΡΟΫΠΟΛΟΓΙΣΜΟΥ
-- ---------------------------------------------------------------------
create table public.budget_items (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  version_id         uuid not null references public.budget_versions(id) on delete cascade,
  line_no            integer not null,                 -- Α/Α στον προϋπολογισμό
  item_code          text not null,                    -- Κωδ. άρθρου (ΝΕΤ/ΑΤΟΕ/ΗΛΜ/ΝΕΤ ΟΔΟ)
  etep_code          text,                             -- Κωδικός ΕΤΕΠ / ΕΛΟΤ ΤΠ
  revision_code      text,                             -- Κωδικός αναθεώρησης (π.χ. ΟΔΟ-1123Α)
  description        text not null,
  unit               text not null,                    -- m3, m2, kg, τεμ., κατ' αποκοπή
  work_group_id      bigint references public.work_groups(id),
  unit_price         numeric(14,4) not null check (unit_price >= 0),
  quantity           numeric(16,4) not null check (quantity >= 0),
  amount             numeric(14,2) generated always as
                       (round(unit_price * quantity, 2)) stored,
  is_new_price       boolean not null default false,   -- Προήλθε από ΠΚΤΜΝΕ
  new_price_item_id  uuid,                             -- FK ορίζεται στο 0009
  is_apologistiki    boolean not null default false,   -- Απολογιστική εργασία (άρθρο 154)
  notes              text,
  created_at         timestamptz not null default now(),
  unique (version_id, line_no)
);

create index budget_items_project_idx on public.budget_items (project_id, version_id);
create index budget_items_group_idx   on public.budget_items (work_group_id);

comment on column public.budget_items.is_new_price is
  'true όταν το άρθρο προέρχεται από Π.Κ.Τ.Μ.Ν.Ε. (άρθρο 156 §5-6). '
  'Κανόνας ελέγχου: νέο άρθρο ΔΕΝ επιτρέπεται να χρηματοδοτηθεί από επί έλασσον '
  'δαπάνες (άρθρο 156 §3γ) — βλ. trigger στο 0009.';

-- ---------------------------------------------------------------------
-- 4.4 ΠΡΩΤΟΚΟΛΛΑ ΚΑΝΟΝΙΣΜΟΥ ΤΙΜΩΝ ΜΟΝΑΔΟΣ ΝΕΩΝ ΕΡΓΑΣΙΩΝ (Π.Κ.Τ.Μ.Ν.Ε.)
--     Άρθρο 156 §5-6 ν.4412/2016
-- ---------------------------------------------------------------------
create table public.new_price_protocols (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  protocol_no        integer not null,                 -- 1ο ΠΚΤΜΝΕ, 2ο ΠΚΤΜΝΕ ...
  drafted_at         date not null,
  committee_members  jsonb not null,                   -- [{profile_id, name, role}] ≥2, κανόνας: 3 τεχνικοί
  sigma_coefficient  numeric(10,6),                    -- Συντελεστής σ = Α:Β (άρθρο 156 §6)
  discount_applied   numeric(6,3),                     -- Τεκμαρτή έκπτωση δημοπρασίας
  contractor_signed  public.signature_kind,
  status             public.ape_status not null default 'draft',
  tc_opinion_id      uuid,                             -- Γνωμοδότηση Τεχνικού Συμβουλίου
  approved_at        date,
  approval_ada       text,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (project_id, protocol_no)
);

comment on column public.new_price_protocols.committee_members is
  'Επιτροπή κανονισμού νέων τιμών: τρεις τεχνικοί υπάλληλοι της υπηρεσίας, '
  'μεταξύ των οποίων ΥΠΟΧΡΕΩΤΙΚΑ ο επιβλέπων· κατ'' εξαίρεση δύο, εφόσον δεν '
  'επαρκεί το προσωπικό (άρθρο 156 §5 ν.4412/2016).';

create table public.new_price_items (
  id                 uuid primary key default gen_random_uuid(),
  protocol_id        uuid not null references public.new_price_protocols(id) on delete cascade,
  item_code          text not null,                    -- 'Ν.1', 'Ν.2' ...
  description        text not null,
  unit               text not null,
  work_group_id      bigint references public.work_groups(id),
  basis              public.new_price_basis not null,
  basis_reference    text not null,                    -- Ποιο συμβατικό άρθρο / αναλυτικό τιμολόγιο
  analysis           jsonb,                            -- Ανάλυση τιμής (υλικά, εργασία, ΜΕ)
  price_before_disc  numeric(14,4) not null,
  price_final        numeric(14,4) not null,           -- Μετά την τεκμαρτή έκπτωση
  quantity           numeric(16,4) not null default 0,
  justification      text not null,                    -- Τεκμηρίωση αναγκαιότητας
  created_at         timestamptz not null default now(),
  unique (protocol_id, item_code),
  constraint npi_price_chk check (price_final <= price_before_disc)
);

comment on table public.new_price_items is
  'Νέες τιμές μονάδος. Ιεράρχηση πηγών κατά το άρθρο 156 §5: (α) όμοιες ή '
  'ανάλογες συμβατικές τιμές, (β) εγκεκριμένα αναλυτικά τιμολόγια, '
  '(γ) απολογιστικά στοιχεία κόστους. Επί των τιμών εφαρμόζεται η τεκμαρτή έκπτωση.';

alter table public.budget_items
  add constraint budget_items_new_price_fk
  foreign key (new_price_item_id) references public.new_price_items(id) on delete set null;

-- ---------------------------------------------------------------------
-- 4.5 ΑΠΟΛΟΓΙΣΤΙΚΕΣ ΕΡΓΑΣΙΕΣ (άρθρο 154) &
--     ΕΠΕΙΓΟΥΣΕΣ / ΑΠΡΟΒΛΕΠΤΕΣ ΠΡΟΣΘΕΤΕΣ (άρθρο 155)
-- ---------------------------------------------------------------------
create table public.apologistika (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  kind               text not null,                    -- 'apologistiki' (154) | 'epeigousa' (155)
  ordered_at         date not null,
  order_ref          text not null,                    -- Εντολή Δ.Υ. / εγγραφή στο ημερολόγιο
  description        text not null,
  justification      text not null,
  cost_documented    numeric(14,2) not null default 0,
  contractor_fee_pct numeric(5,2) not null default 18.00,  -- Όφελος αναδόχου
  total_amount       numeric(14,2) generated always as
                       (round(cost_documented * (1 + contractor_fee_pct/100), 2)) stored,
  supporting_docs    jsonb,                            -- Παραστατικά / ζυγολόγια
  included_in_ape_id uuid,                             -- Τακτοποιείται σε επόμενο ΑΠΕ
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint apologistika_kind_chk check (kind in ('apologistiki','epeigousa'))
);

comment on table public.apologistika is
  'Απολογιστικές εργασίες (άρθρο 154) και επείγουσες/απρόβλεπτες πρόσθετες '
  'εργασίες (άρθρο 155). Κατ'' άρθρο 156 §2, οι εργασίες των άρθρων 154-155 '
  'ΔΕΝ απαιτούν προηγούμενο ΑΠΕ, τακτοποιούνται όμως σε επόμενο.';

-- >>>>>>>>>>>>>>>>>>>> 0005_workflow_engine.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0005 : ΜΗΧΑΝΗ ΡΟΗΣ (Workflow Engine) — Fail-Safe λειτουργία
--
-- Αρχή σχεδίασης: κάθε στάδιο είναι ΠΡΟΑΠΑΙΤΟΥΜΕΝΟ (checkpoint) του επομένου.
-- Κανένα στάδιο δεν κλείνει αν δεν ικανοποιηθούν:
--   (α) τα προαπαιτούμενα στάδια,
--   (β) όλες οι υποχρεωτικές ενέργειες της λίστας ελέγχου,
--   (γ) όλα τα υποχρεωτικά έγγραφα (συνημμένα/παραχθέντα),
--   (δ) ο ειδικός κανόνας ελέγχου (guard function) του σταδίου.
-- Παράκαμψη επιτρέπεται ΜΟΝΟ σε προϊστάμενο Δ.Υ., με υποχρεωτική
-- αιτιολόγηση, και καταγράφεται ανεξίτηλα στο audit_log.
-- =====================================================================

create type app.blocker as (
  code       text,
  message    text,
  severity   text,     -- 'hard' = απαγορευτικό, 'soft' = προειδοποίηση
  legal_ref  text
);

-- ---------------------------------------------------------------------
-- 5.1 ΚΑΤΑΛΟΓΟΣ ΣΤΑΔΙΩΝ (πρότυπη ροή — seed στο 0013)
-- ---------------------------------------------------------------------
create table public.workflow_stages (
  code             text primary key,                   -- 'S06_XRONODIAGRAMMA'
  phase            public.stage_phase not null,
  ordinal          integer not null unique,
  title            text not null,
  purpose          text not null,                      -- Τι επιτυγχάνεται στο στάδιο
  responsible      public.party_type not null,         -- Ποιος έχει την πρωτοβουλία
  approver         public.party_type,                  -- Ποιος εγκρίνει
  recurrence       public.recurrence_type not null default 'once',
  legal_ref_id     text references public.legal_refs(id),
  extra_legal_refs text[],
  deadline_days    integer,                            -- Προθεσμία σε ημέρες
  deadline_months  integer,                            -- ή σε μήνες
  deadline_basis   public.deadline_basis,
  deadline_is_working_days boolean not null default false,
  tacit_approval   boolean not null default false,     -- Σιωπηρή έγκριση αν παρέλθει άπρακτη
  tacit_effect     text,                               -- Τι επέρχεται σιωπηρά
  applies_when     jsonb,                              -- Συνθήκη εφαρμογής (βλ. app.stage_applies)
  guard_fn         text,                               -- Ειδικός κανόνας ελέγχου
  risk_note        text,                               -- Τι διακυβεύεται αν παραλειφθεί
  is_mandatory     boolean not null default true,
  created_at       timestamptz not null default now()
);

comment on table public.workflow_stages is
  'Πρότυπος οδηγός επίβλεψης: 35 στάδια από την υπογραφή της σύμβασης έως την '
  'παραλαβή. Κάθε στάδιο φέρει υποχρεωτική νομική παραπομπή.';

-- Προαπαιτούμενα (κατευθυνόμενος άκυκλος γράφος)
create table public.stage_prerequisites (
  stage_code       text not null references public.workflow_stages(code) on delete cascade,
  requires_code    text not null references public.workflow_stages(code) on delete cascade,
  is_hard          boolean not null default true,      -- false = προειδοποίηση μόνο
  rationale        text,
  primary key (stage_code, requires_code),
  constraint sp_no_self check (stage_code <> requires_code)
);

-- Λίστα ελέγχου ενεργειών ανά στάδιο — ΔΙΑΧΩΡΙΣΜΟΣ ΡΟΛΩΝ
create table public.stage_tasks (
  id               bigint generated always as identity primary key,
  stage_code       text not null references public.workflow_stages(code) on delete cascade,
  ordinal          integer not null,
  party            public.party_type not null,         -- Ανάδοχος ή Επιβλέπων ή Δ.Υ. ...
  title            text not null,
  detail           text,
  legal_ref_id     text references public.legal_refs(id),
  is_mandatory     boolean not null default true,
  needs_evidence   boolean not null default false,     -- Απαιτεί συνημμένο τεκμήριο
  unique (stage_code, ordinal)
);

comment on table public.stage_tasks is
  'Ενέργειες ανά στάδιο, διακριτά ανά υπόχρεο μέρος: τι κάνει ο ΑΝΑΔΟΧΟΣ και '
  'τι ελέγχει/συντάσσει ο ΕΠΙΒΛΕΠΩΝ ή η ΔΙΕΥΘΥΝΟΥΣΑ ΥΠΗΡΕΣΙΑ.';

-- Υποχρεωτικά έγγραφα ανά στάδιο (συνδέονται με πρότυπα στο 0006)
create table public.stage_documents (
  id               bigint generated always as identity primary key,
  stage_code       text not null references public.workflow_stages(code) on delete cascade,
  doc_code         text not null,                      -- 'BEBAIOSI_PERATOSIS'
  title            text not null,
  produced_by      public.party_type not null,
  is_mandatory     boolean not null default true,
  legal_ref_id     text references public.legal_refs(id),
  unique (stage_code, doc_code)
);

-- ---------------------------------------------------------------------
-- 5.2 ΣΤΙΓΜΙΟΤΥΠΑ ΑΝΑ ΕΡΓΟ
-- ---------------------------------------------------------------------
create table public.project_stages (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects(id) on delete cascade,
  stage_code       text not null references public.workflow_stages(code) on delete restrict,
  cycle_no         integer not null default 1,         -- Για επαναλαμβανόμενα στάδια
  status           public.stage_status not null default 'locked',
  due_date         date,
  started_at       timestamptz,
  completed_at     timestamptz,
  completed_by     uuid references public.profiles(id),
  na_reason        text,                               -- Αιτιολόγηση 'not_applicable'
  override_by      uuid references public.profiles(id),-- Παράκαμψη κλειδώματος
  override_reason  text,
  override_at      timestamptz,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (project_id, stage_code, cycle_no),
  constraint ps_na_chk check (status <> 'not_applicable' or na_reason is not null),
  constraint ps_override_chk check (override_by is null or override_reason is not null)
);

create index project_stages_project_idx on public.project_stages (project_id, status);
create index project_stages_due_idx     on public.project_stages (due_date)
  where status in ('available','in_progress','pending_approval');

create trigger trg_project_stages_touch
  before update on public.project_stages
  for each row execute function app.touch_updated_at();

create table public.project_stage_tasks (
  id               uuid primary key default gen_random_uuid(),
  project_stage_id uuid not null references public.project_stages(id) on delete cascade,
  stage_task_id    bigint not null references public.stage_tasks(id) on delete restrict,
  is_done          boolean not null default false,
  done_at          timestamptz,
  done_by          uuid references public.profiles(id),
  evidence_doc_id  uuid,                               -- FK ορίζεται στο 0006
  waived           boolean not null default false,
  waive_reason     text,
  notes            text,
  unique (project_stage_id, stage_task_id),
  constraint pst_waive_chk check (not waived or waive_reason is not null)
);

-- ---------------------------------------------------------------------
-- 5.3 ΣΥΝΑΡΤΗΣΕΙΣ ΜΗΧΑΝΗΣ
-- ---------------------------------------------------------------------

-- Εφαρμοσιμότητα σταδίου βάσει χαρακτηριστικών της σύμβασης
create or replace function app.stage_applies(p_project_id uuid, p_stage_code text)
returns boolean
language plpgsql stable as $$
declare
  v_cond jsonb;
  v_ctx  jsonb;
begin
  select applies_when into v_cond from public.workflow_stages where code = p_stage_code;
  if v_cond is null then
    return true;
  end if;

  select to_jsonb(t) into v_ctx from (
    select c.regime::text            as regime,
           c.supervision_mode::text  as supervision_mode,
           c.diary_mode::text        as diary_mode,
           c.has_prim_clause         as has_prim_clause,
           c.initial_value_net       as initial_value_net,
           p.category::text          as category
    from public.contracts c
    join public.projects  p on p.id = c.project_id
    where c.project_id = p_project_id
  ) t;

  if v_ctx is null then
    return true;                              -- Δεν έχει καταχωρηθεί σύμβαση ακόμη
  end if;

  -- Απλός μηχανισμός: {"key": value} ή {"key": {"gte": n}} / {"in": [...]}
  return (
    select bool_and(
      case
        when jsonb_typeof(value) = 'object' and value ? 'gte'
          then (v_ctx->>key)::numeric >= (value->>'gte')::numeric
        when jsonb_typeof(value) = 'object' and value ? 'lt'
          then (v_ctx->>key)::numeric <  (value->>'lt')::numeric
        when jsonb_typeof(value) = 'object' and value ? 'in'
          then (v_ctx->>key) in (select jsonb_array_elements_text(value->'in'))
        else (v_ctx->>key) = trim(both '"' from value::text)
      end)
    from jsonb_each(v_cond)
  );
end $$;

-- Υπολογισμός ημερομηνίας λήξης προθεσμίας σταδίου
create or replace function app.compute_stage_due(p_project_id uuid, p_stage_code text)
returns date
language plpgsql stable as $$
declare
  s        public.workflow_stages%rowtype;
  v_base   date;
  v_result date;
begin
  select * into s from public.workflow_stages where code = p_stage_code;
  if s.deadline_days is null and s.deadline_months is null then
    return null;
  end if;

  select case s.deadline_basis
           when 'ypografi_symvasis'  then c.signed_at
           when 'lixi_prothesmias'   then c.current_end_date
           when 'enarxi_ergasion'    then c.works_start_deadline
           else c.signed_at
         end
    into v_base
  from public.contracts c where c.project_id = p_project_id;

  if v_base is null then
    return null;
  end if;

  v_result := v_base;
  if s.deadline_months is not null then
    v_result := v_result + (s.deadline_months || ' months')::interval;
  end if;
  if s.deadline_days is not null then
    v_result := v_result + s.deadline_days;
  end if;
  return v_result;
end $$;

-- Δημιουργία στιγμιοτύπων ροής για νέο έργο
create or replace function app.instantiate_workflow(p_project_id uuid)
returns integer
language plpgsql security definer set search_path = public, app as $$
declare
  v_count integer := 0;
  r       record;
  v_ps_id uuid;
begin
  for r in select * from public.workflow_stages order by ordinal loop
    if not app.stage_applies(p_project_id, r.code) then
      continue;
    end if;

    insert into public.project_stages (project_id, stage_code, cycle_no, status, due_date)
    values (p_project_id, r.code, 1, 'locked',
            app.compute_stage_due(p_project_id, r.code))
    on conflict (project_id, stage_code, cycle_no) do nothing
    returning id into v_ps_id;

    if v_ps_id is not null then
      insert into public.project_stage_tasks (project_stage_id, stage_task_id)
      select v_ps_id, st.id from public.stage_tasks st where st.stage_code = r.code;
      v_count := v_count + 1;
    end if;
    v_ps_id := null;
  end loop;

  perform app.recompute_availability(p_project_id);
  return v_count;
end $$;

-- Εντοπισμός εμποδίων ολοκλήρωσης ενός σταδίου
create or replace function app.stage_blockers(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare
  ps       public.project_stages%rowtype;
  ws       public.workflow_stages%rowtype;
  v_sql    text;
begin
  select * into ps from public.project_stages where id = p_project_stage_id;
  if not found then
    return;
  end if;
  select * into ws from public.workflow_stages where code = ps.stage_code;

  -- (α) Προαπαιτούμενα στάδια
  return query
    select 'PREREQ_' || sp.requires_code,
           format('Εκκρεμεί το προαπαιτούμενο στάδιο «%s».', w2.title),
           case when sp.is_hard then 'hard' else 'soft' end,
           coalesce(w2.legal_ref_id, '')
    from public.stage_prerequisites sp
    join public.workflow_stages w2 on w2.code = sp.requires_code
    left join public.project_stages ps2
           on ps2.project_id = ps.project_id
          and ps2.stage_code = sp.requires_code
          and ps2.cycle_no = 1
    where sp.stage_code = ps.stage_code
      and coalesce(ps2.status, 'locked') not in ('completed','not_applicable');

  -- (β) Υποχρεωτικές ενέργειες λίστας ελέγχου
  return query
    select 'TASK_' || st.id::text,
           format('Εκκρεμής υποχρεωτική ενέργεια (%s): %s',
                  app.party_label(st.party), st.title),
           'hard',
           coalesce(st.legal_ref_id, '')
    from public.project_stage_tasks pst
    join public.stage_tasks st on st.id = pst.stage_task_id
    where pst.project_stage_id = p_project_stage_id
      and st.is_mandatory
      and not pst.is_done
      and not pst.waived;

  -- (γ) Τεκμήρια που απαιτούνται αλλά λείπουν
  return query
    select 'EVIDENCE_' || st.id::text,
           format('Απαιτείται συνημμένο τεκμήριο για την ενέργεια: %s', st.title),
           'hard',
           coalesce(st.legal_ref_id, '')
    from public.project_stage_tasks pst
    join public.stage_tasks st on st.id = pst.stage_task_id
    where pst.project_stage_id = p_project_stage_id
      and st.needs_evidence
      and pst.is_done
      and pst.evidence_doc_id is null
      and not pst.waived;

  -- (δ) Υποχρεωτικά έγγραφα του σταδίου (ορίζεται στο 0006)
  return query select * from app.guard_required_documents(p_project_stage_id);

  -- (ε) Ειδικός κανόνας του σταδίου
  if ws.guard_fn is not null then
    v_sql := format('select code, message, severity, legal_ref from %s($1)', ws.guard_fn);
    return query execute v_sql using p_project_stage_id;
  end if;
end $$;

create or replace function app.party_label(p public.party_type)
returns text language sql immutable as $$
  select case p
    when 'anadochos'             then 'Ανάδοχος'
    when 'epivlepon'             then 'Επιβλέπων'
    when 'dieuthynousa_ypiresia' then 'Διευθύνουσα Υπηρεσία'
    when 'proistameni_arxi'      then 'Προϊσταμένη Αρχή'
    when 'techniko_symvoulio'    then 'Τεχνικό Συμβούλιο'
    when 'epitropi'              then 'Επιτροπή'
    when 'ife'                   then 'Ιδιωτικός Φορέας Επίβλεψης'
    when 'kyrios_ergou'          then 'Κύριος του Έργου'
  end $$;

-- Επανυπολογισμός: ποια στάδια ξεκλειδώνουν
create or replace function app.recompute_availability(p_project_id uuid)
returns void
language plpgsql security definer set search_path = public, app as $$
declare
  r record;
  v_hard integer;
begin
  for r in
    select ps.* from public.project_stages ps
    where ps.project_id = p_project_id
      and ps.status in ('locked','available')
    order by (select ordinal from public.workflow_stages w where w.code = ps.stage_code)
  loop
    select count(*) into v_hard
    from app.stage_blockers(r.id) b
    where b.severity = 'hard' and b.code like 'PREREQ%';

    if v_hard = 0 and r.status = 'locked' then
      update public.project_stages set status = 'available' where id = r.id;
    elsif v_hard > 0 and r.status = 'available' then
      update public.project_stages set status = 'locked' where id = r.id;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5.4 TRIGGER FAIL-SAFE — απαγορεύει το κλείσιμο σταδίου με εκκρεμότητες
-- ---------------------------------------------------------------------
create or replace function app.guard_stage_transition()
returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  v_blockers text;
  v_is_head  boolean;
begin
  if new.status = old.status then
    return new;
  end if;

  -- Παράκαμψη: μόνο προϊστάμενος Δ.Υ. / Προϊσταμένη Αρχή, με αιτιολόγηση
  if new.override_by is not null and new.override_by is distinct from old.override_by then
    select exists (
      select 1 from public.project_assignments pa
      where pa.project_id = new.project_id
        and pa.profile_id = new.override_by
        and pa.role in ('proistamenos_dy','proistameni_arxi','admin')
        and pa.valid_to is null
    ) into v_is_head;

    if not v_is_head then
      raise exception
        'Η παράκαμψη κλειδώματος επιτρέπεται μόνο στον Προϊστάμενο της Διευθύνουσας Υπηρεσίας ή στην Προϊσταμένη Αρχή.';
    end if;

    insert into public.audit_log
      (actor_id, table_name, record_id, action, project_id, old_data, new_data, reason)
    values (new.override_by, 'project_stages', new.id::text, 'lock_override',
            new.project_id, to_jsonb(old), to_jsonb(new), new.override_reason);

    new.override_at := now();
    return new;
  end if;

  if new.status in ('in_progress','pending_approval','completed') then
    select string_agg('• ' || b.message ||
                      case when coalesce(b.legal_ref,'') <> ''
                           then ' [' || b.legal_ref || ']' else '' end,
                      E'\n')
      into v_blockers
    from app.stage_blockers(new.id) b
    where b.severity = 'hard'
      and (new.status = 'completed' or b.code like 'PREREQ%');

    if v_blockers is not null then
      raise exception E'ΑΠΑΓΟΡΕΥΕΤΑΙ η μετάβαση του σταδίου σε «%».\nΕκκρεμούν:\n%',
        new.status, v_blockers
        using errcode = 'check_violation',
              hint = 'Ολοκληρώστε τα εκκρεμή βήματα ή ζητήστε αιτιολογημένη παράκαμψη από τον Προϊστάμενο της Δ.Υ.';
    end if;
  end if;

  if new.status = 'completed' and new.completed_at is null then
    new.completed_at := now();
    if new.due_date is not null and current_date > new.due_date then
      new.status := 'overdue';
    end if;
  end if;

  return new;
end $$;

create trigger trg_guard_stage_transition
  before update on public.project_stages
  for each row execute function app.guard_stage_transition();

-- Μετά από κάθε ολοκλήρωση, ξεκλείδωσε τα επόμενα
create or replace function app.after_stage_update()
returns trigger language plpgsql as $$
begin
  if new.status in ('completed','not_applicable','overdue')
     and old.status is distinct from new.status then
    perform app.recompute_availability(new.project_id);
  end if;
  return null;
end $$;

create trigger trg_after_stage_update
  after update on public.project_stages
  for each row execute function app.after_stage_update();

-- >>>>>>>>>>>>>>>>>>>> 0006_documents_templates.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0006 : Πρότυπα εγγράφων (templates) & παραγόμενα έγγραφα
--
-- Λογική αυτοματοποίησης:
--   document_templates  = τα πρότυπα της Υπηρεσίας (.docx/.xlsx με πεδία)
--   template_fields     = χάρτης «placeholder → πηγή δεδομένων»
--   documents           = τα παραχθέντα έγγραφα του συγκεκριμένου έργου
-- Η παραγωγή γίνεται server-side (Edge Function) με βάση το payload,
-- ώστε κάθε έγγραφο να είναι αναπαραγώγιμο και ελέγξιμο.
-- =====================================================================

create table public.document_templates (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid references public.organizations(id) on delete cascade, -- null = καθολικό
  doc_code         text not null,                      -- 'ANAL_EPIMETRISI', 'APE', 'PPAE' ...
  title            text not null,
  category         text not null,                      -- 'imerologio','epimetrisi','ape','peraiosi' ...
  file_type        text not null default 'docx',       -- docx | xlsx | html | pdf
  storage_path     text not null,                      -- Supabase Storage: templates/...
  version          integer not null default 1,
  is_active        boolean not null default true,
  stage_code       text references public.workflow_stages(code),
  legal_ref_id     text references public.legal_refs(id),
  numbering_scheme text,                               -- Μοτίβο αρίθμησης, π.χ. '{ΕΤΟΣ}/{ΑΑ}'
  requires_ada     boolean not null default false,     -- Ανάρτηση στη Διαύγεια (ν.4727/2020)
  requires_adam    boolean not null default false,     -- ΚΗΜΔΗΣ (άρθρο 38 ν.4412/2016)
  notes            text,
  created_at       timestamptz not null default now(),
  unique (org_id, doc_code, version),
  constraint dt_filetype_chk check (file_type in ('docx','xlsx','html','pdf','odt'))
);

comment on table public.document_templates is
  'Πρότυπα της Υπηρεσίας. Ο Δήμος ανεβάζει τα δικά του .docx/.xlsx με '
  'placeholders· το σύστημα τα συμπληρώνει από τα δεδομένα του έργου.';

-- Χάρτης πεδίων: πώς γεμίζει κάθε placeholder
create table public.template_fields (
  id               bigint generated always as identity primary key,
  template_id      uuid not null references public.document_templates(id) on delete cascade,
  placeholder      text not null,                      -- '{{ergo.titlos}}'
  label            text not null,                      -- 'Τίτλος έργου'
  source_kind      text not null,                      -- 'field' | 'query' | 'computed' | 'manual'
  source_path      text,                               -- 'projects.title' ή όνομα view/συνάρτησης
  data_type        text not null default 'text',       -- text|number|date|currency|table
  format_mask      text,                               -- '#.##0,00', 'dd/MM/yyyy'
  is_required      boolean not null default true,
  default_value    text,
  unique (template_id, placeholder),
  constraint tf_kind_chk check (source_kind in ('field','query','computed','manual'))
);

comment on table public.template_fields is
  'Δηλωτικός χάρτης συμπλήρωσης προτύπων. Επιτρέπει την προσθήκη νέου προτύπου '
  'από τη διοίκηση ΧΩΡΙΣ αλλαγή κώδικα.';

-- ---------------------------------------------------------------------
-- 6.2 ΠΑΡΑΓΟΜΕΝΑ ΕΓΓΡΑΦΑ
-- ---------------------------------------------------------------------
create table public.documents (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects(id) on delete cascade,
  project_stage_id uuid references public.project_stages(id) on delete set null,
  template_id      uuid references public.document_templates(id) on delete set null,
  doc_code         text not null,
  title            text not null,
  protocol_no      text,                               -- Αρ. πρωτοκόλλου Υπηρεσίας
  protocol_date    date,
  ada              text,                               -- Διαύγεια
  adam             text,                               -- ΚΗΜΔΗΣ
  status           public.document_status not null default 'draft',
  storage_path     text,                               -- Το τελικό αρχείο
  payload          jsonb,                              -- Τιμές πεδίων κατά την παραγωγή
  checksum         text,                               -- SHA-256 ακεραιότητας
  entity_type      text,                               -- 'measurement','ape','payment_certificate' ...
  entity_id        uuid,                               -- Σύνδεση με τη δομημένη εγγραφή
  version          integer not null default 1,
  supersedes_id    uuid references public.documents(id),
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index documents_project_idx on public.documents (project_id, doc_code);
create index documents_entity_idx  on public.documents (entity_type, entity_id);

create trigger trg_documents_touch
  before update on public.documents
  for each row execute function app.touch_updated_at();

-- Υπογραφές
create table public.document_signatures (
  id               uuid primary key default gen_random_uuid(),
  document_id      uuid not null references public.documents(id) on delete cascade,
  signer_profile   uuid references public.profiles(id),
  signer_name      text not null,
  signer_capacity  text not null,                      -- 'Επιβλέπων', 'Νόμιμος εκπρόσωπος αναδόχου'
  party            public.party_type not null,
  kind             public.signature_kind not null default 'apla',
  reservation_text text,                               -- Κείμενο επιφύλαξης (άρθρο 156 §7)
  signed_at        timestamptz not null default now(),
  certificate_info jsonb,
  constraint ds_reservation_chk check (kind <> 'me_epifylaxi' or reservation_text is not null)
);

comment on column public.document_signatures.kind is
  'Η υπογραφή ΑΠΕ/ΠΚΤΜΝΕ «με επιφύλαξη» διατηρεί τα δικαιώματα του αναδόχου· '
  'η άρνηση υπογραφής οδηγεί σε κοινοποίηση κατ'' άρθρο 143 ν.4412/2016.';

-- Κοινοποιήσεις (άρθρο 143 — κοινοποίηση στον ανάδοχο)
create table public.document_communications (
  id               uuid primary key default gen_random_uuid(),
  document_id      uuid not null references public.documents(id) on delete cascade,
  recipient_party  public.party_type not null,
  recipient_name   text not null,
  method           text not null,                      -- 'ilektroniki','epidosi','systimeni'
  sent_at          timestamptz not null default now(),
  received_at      timestamptz,                        -- Αφετηρία προθεσμιών ένστασης
  proof_path       text,                               -- Αποδεικτικό επίδοσης
  legal_ref_id     text references public.legal_refs(id),
  constraint dc_method_chk check (method in ('ilektroniki','epidosi','systimeni','autopswia'))
);

comment on table public.document_communications is
  'Κοινοποίηση πράξεων στον ανάδοχο (άρθρο 143 ν.4412/2016). Το received_at '
  'αποτελεί την αφετηρία της ανατρεπτικής προθεσμίας ένστασης (άρθρο 174).';

-- Σύνδεση τεκμηρίων της λίστας ελέγχου με έγγραφα
alter table public.project_stage_tasks
  add constraint pst_evidence_fk
  foreign key (evidence_doc_id) references public.documents(id) on delete set null;

-- ---------------------------------------------------------------------
-- 6.3 ΓΕΝΙΚΟΣ ΚΑΝΟΝΑΣ: στάδιο δεν κλείνει χωρίς τα υποχρεωτικά έγγραφα
-- ---------------------------------------------------------------------
create or replace function app.guard_required_documents(p_project_stage_id uuid)
returns setof app.blocker
language sql stable security definer set search_path = public, app as $$
  select ('DOC_' || sd.doc_code)::text,
         format('Λείπει το υποχρεωτικό έγγραφο: %s (συντάσσεται από: %s).',
                sd.title, app.party_label(sd.produced_by))::text,
         'hard'::text,
         coalesce(sd.legal_ref_id, '')::text
  from public.project_stages ps
  join public.stage_documents sd on sd.stage_code = ps.stage_code
  where ps.id = p_project_stage_id
    and sd.is_mandatory
    and not exists (
      select 1 from public.documents d
      where d.project_id = ps.project_id
        and d.doc_code = sd.doc_code
        and d.status in ('signed','approved','communicated','deemed_approved')
    );
$$;

-- >>>>>>>>>>>>>>>>>>>> 0007_schedule_diary_quality.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0007 : Χρονοδιάγραμμα (άρθρο 145), Ημερολόγιο (άρθρο 146),
--                  Ποιότητα & έλεγχοι (άρθρα 138, 158-159), αυτοψίες,
--                  τριμηνιαίες εκθέσεις (άρθρο 136 §10)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 7.1 ΧΡΟΝΟΔΙΑΓΡΑΜΜΑ ΚΑΤΑΣΚΕΥΗΣ (άρθρο 145)
-- ---------------------------------------------------------------------
create table public.schedules (
  id                  uuid primary key default gen_random_uuid(),
  project_id          uuid not null references public.projects(id) on delete cascade,
  version_no          integer not null default 0,      -- 0 = αρχικό, 1..N = αναπροσαρμογές
  label               text not null default 'Αρχικό χρονοδιάγραμμα',
  method              text not null,                   -- 'diktyoti_analysi' | 'grammiko'
  submitted_at        date,
  submit_due_date     date,                            -- 15-30 ημ. από υπογραφή (§1)
  approved_at         date,
  approval_due_date   date,                            -- submitted_at + 15 ημ. (§2)
  approved_by         uuid references public.profiles(id),
  deemed_approved     boolean not null default false,  -- Σιωπηρή έγκριση (§2)
  clarifications_at   date,                            -- Έγγραφο αίτημα διευκρινίσεων
  reason              text,                            -- Αιτία αναπροσαρμογής
  document_id         uuid references public.documents(id),
  period_granularity  text not null default 'trimino', -- Τουλάχιστον τριμηνιαία (§3)
  legal_ref_id        text references public.legal_refs(id),
  created_at          timestamptz not null default now(),
  unique (project_id, version_no),
  constraint sched_method_chk check (method in ('diktyoti_analysi','grammiko')),
  constraint sched_appr_chk   check (approved_at is null or submitted_at is not null)
);

comment on table public.schedules is
  'Χρονοδιάγραμμα κατασκευής (άρθρο 145 ν.4412/2016). Υποβολή σε προθεσμία που '
  'ορίζεται στα συμβατικά τεύχη, μεταξύ 15 και 30 ημερών από την υπογραφή· '
  'έγκριση από τη Δ.Υ. εντός 15 ημερών, άλλως ΤΕΚΜΑΙΡΕΤΑΙ ΕΓΚΕΚΡΙΜΕΝΟ. '
  'Δικτυωτή ανάλυση υποχρεωτική για έργα άνω του 1.000.000 €.';

create table public.schedule_activities (
  id                uuid primary key default gen_random_uuid(),
  schedule_id       uuid not null references public.schedules(id) on delete cascade,
  code              text not null,
  description       text not null,
  work_group_id     bigint references public.work_groups(id),
  planned_start     date not null,
  planned_finish    date not null,
  actual_start      date,
  actual_finish     date,
  planned_amount    numeric(14,2) not null default 0,
  progress_pct      numeric(5,2) not null default 0,
  is_critical       boolean not null default false,    -- Κρίσιμη διαδρομή
  predecessors      text[],
  unique (schedule_id, code),
  constraint sa_dates_chk    check (planned_finish >= planned_start),
  constraint sa_progress_chk check (progress_pct between 0 and 100)
);

-- Τετραγωνικός πίνακας ποσοτήτων ανά περίοδο (άρθρο 145 §3)
create table public.schedule_periods (
  id                uuid primary key default gen_random_uuid(),
  schedule_id       uuid not null references public.schedules(id) on delete cascade,
  period_no         integer not null,
  period_from       date not null,
  period_to         date not null,
  planned_amount    numeric(14,2) not null default 0,
  cumulative_amount numeric(14,2) not null default 0,
  actual_amount     numeric(14,2),
  unique (schedule_id, period_no)
);

-- Οργανόγραμμα εργοταξίου (άρθρο 145 §4) — εντός 1 μηνός
create table public.site_organograms (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null references public.projects(id) on delete cascade,
  submitted_at      date,
  due_date          date,
  personnel         jsonb not null default '[]'::jsonb,   -- [{eidikotita, plithos}]
  equipment         jsonb not null default '[]'::jsonb,   -- [{michanima, arithmos}]
  approved_at       date,
  document_id       uuid references public.documents(id),
  legal_ref_id      text references public.legal_refs(id),
  created_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7.2 ΗΜΕΡΟΛΟΓΙΟ ΕΡΓΟΥ (άρθρο 146)
-- ---------------------------------------------------------------------
create table public.diary_entries (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  entry_date         date not null,
  site_label         text,                             -- Για έργα με διακριτά μέτωπα
  weather            public.weather_condition,
  temperature_c      numeric(4,1),
  personnel          jsonb not null default '[]'::jsonb, -- [{eidikotita, arithmos}]
  equipment          jsonb not null default '[]'::jsonb, -- [{michanima, ores}]
  works_description  text not null,
  work_locations     text,
  progress_notes     text,
  delay_reasons      text,
  critical_start_end text,                             -- Έναρξη/πέρας κρίσιμων εργασιών
  materials_received text,
  lab_tests_note     text,
  traffic_measures   text,                             -- Κυκλοφοριακές ρυθμίσεις
  accidents          text,
  supervisor_orders  text,                             -- Εντολές επίβλεψης
  extraordinary      text,                             -- Έκτακτα περιστατικά
  other_notes        text,
  status             public.diary_status not null default 'draft',
  submitted_by       uuid references public.contractor_staff(id),
  submitted_at       timestamptz,
  review_due         date,                             -- submitted + 2 εργάσιμες (άρθρο 146)
  reviewed_by        uuid references public.profiles(id),
  reviewed_at        timestamptz,
  supervisor_remarks text,
  approved_by        uuid references public.profiles(id),
  approved_at        timestamptz,
  signature_hash     text,                             -- Ψηφιακή υπογραφή τηρούντος
  document_id        uuid references public.documents(id),
  created_at         timestamptz not null default now(),
  unique (project_id, entry_date, site_label)
);

create index diary_entries_project_date_idx on public.diary_entries (project_id, entry_date desc);

comment on table public.diary_entries is
  'Ηλεκτρονικό ημερολόγιο έργου (άρθρο 146 ν.4412/2016). Τηρείται ΚΑΘΗΜΕΡΙΝΑ '
  'από τεχνικό του αναδόχου (άρθρο 139), αποστέλλεται ηλεκτρονικά στον '
  'επιβλέποντα και στον προϊστάμενο της Δ.Υ.· ο επιβλέπων ελέγχει/διορθώνει '
  'εντός ΔΥΟ (2) ΕΡΓΑΣΙΜΩΝ ΗΜΕΡΩΝ. Η παράλειψη τήρησης επισύρει ειδική ποινική '
  'ρήτρα 100-500 € ανά ημέρα.';

-- ---------------------------------------------------------------------
-- 7.3 ΠΟΙΟΤΗΤΑ
-- ---------------------------------------------------------------------
create table public.quality_plans (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  version_no         integer not null default 1,
  submitted_at       date,
  approved_at        date,
  approved_by        uuid references public.profiles(id),
  scope              text,
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (project_id, version_no)
);

comment on table public.quality_plans is
  'Πρόγραμμα Ποιότητας Έργου (ΠΠΕ) — άρθρο 158 ν.4412/2016.';

-- Έγκριση πηγών λήψης / υλικών (άρθρο 138 §12 — απόφαση εντός 30 ημερών)
create table public.material_approvals (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  material           text not null,
  source_description text not null,                    -- Λατομείο / προμηθευτής / πηγή
  requested_at       date not null,
  decision_due       date,                             -- requested_at + 30 ημέρες
  decided_at         date,
  outcome            public.decision_outcome not null default 'pending',
  deviates_from_study boolean not null default false,
  standards          text[],                           -- ΕΤΕΠ / ΕΛΟΤ ΕΝ που εφαρμόζονται
  ce_marking         boolean,
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now()
);

create table public.lab_tests (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  sample_code        text not null,
  material           text not null,
  test_type          text not null,
  standard           text,                             -- ΕΛΟΤ ΕΝ / ΕΤΕΠ
  lab_name           text,
  sampled_at         date not null,
  sampled_location   text,
  result             public.test_result not null default 'ekremmes',
  result_value       text,
  report_no          text,
  report_date        date,
  document_id        uuid references public.documents(id),
  diary_entry_id     uuid references public.diary_entries(id),
  created_at         timestamptz not null default now()
);

-- Αυτοψίες (άρθρο 136 §11) — πρόσκληση αναδόχου τουλάχιστον 24 ώρες πριν
create table public.site_inspections (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  purpose            text not null,
  invitation_sent_at timestamptz,
  scheduled_at       timestamptz not null,
  performed_at       timestamptz,
  performed_by       text,                             -- Τεχνικός ή επιτροπή
  contractor_present boolean,
  findings           text,
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint si_notice_chk check (
    invitation_sent_at is null
    or scheduled_at - invitation_sent_at >= interval '24 hours')
);

comment on constraint si_notice_chk on public.site_inspections is
  'Ο ανάδοχος καλείται να παραστεί τουλάχιστον 24 ώρες πριν (άρθρο 136 §11).';

-- ---------------------------------------------------------------------
-- 7.4 ΤΡΙΜΗΝΙΑΙΕΣ ΕΚΘΕΣΕΙΣ (άρθρο 136 §10 — Δ.Υ.· άρθρο 138 §17 — ανάδοχος)
-- ---------------------------------------------------------------------
create table public.quarterly_reports (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  author_party       public.party_type not null,       -- 'dieuthynousa_ypiresia' ή 'anadochos'
  year               integer not null,
  quarter            integer not null check (quarter between 1 and 4),
  period_from        date not null,
  period_to          date not null,
  physical_progress  numeric(5,2),
  financial_progress numeric(5,2),
  premetrisi_errors  text,                             -- Σφάλματα προμέτρησης (§10)
  unforeseen_events  text,                             -- Απρόβλεπτες περιστάσεις (§10)
  delays_analysis    text,
  proposed_actions   text,
  document_id        uuid references public.documents(id),
  submitted_at       date,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (project_id, author_party, year, quarter)
);

comment on table public.quarterly_reports is
  'Η Διευθύνουσα Υπηρεσία συντάσσει ΑΝΑ ΤΡΙΜΗΝΟ έκθεση πορείας, με εντοπισμό '
  'σφαλμάτων προμέτρησης και απρόβλεπτων περιστάσεων. Η μη τήρηση συνιστά '
  'ΠΕΙΘΑΡΧΙΚΟ ΠΑΡΑΠΤΩΜΑ (άρθρο 136 §10 ν.4412/2016).';

-- >>>>>>>>>>>>>>>>>>>> 0008_measurements_hidden_works.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0008 : Επιμετρήσεις & Αφανείς Εργασίες (άρθρο 151 ν.4412/2016)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 8.1 ΕΠΙΜΕΤΡΗΣΕΙΣ
-- ---------------------------------------------------------------------
create table public.measurements (
  id                    uuid primary key default gen_random_uuid(),
  project_id            uuid not null references public.projects(id) on delete cascade,
  mtype                 public.measurement_type not null default 'tmimatiki',
  serial_no             integer not null,               -- Α/Α επιμέτρησης
  period_from           date,
  period_to             date,
  work_section          text,                           -- Διακριτό τμήμα έργου (§2)
  budget_version_id     uuid references public.budget_versions(id),

  -- Υποβολή από τον ΑΝΑΔΟΧΟ
  submitted_at          date,
  submitted_by_staff    uuid references public.contractor_staff(id),
  truth_declaration     boolean not null default false, -- Δήλωση περί αληθείας (§1)
  has_drawings          boolean not null default false, -- Επιμετρητικά σχέδια (§2)
  electronic_form       boolean not null default true,  -- Έντυπη & ηλεκτρονική μορφή (§2)

  -- Έλεγχος από την ΕΠΙΒΛΕΨΗ / Δ.Υ.
  status                public.measurement_status not null default 'draft',
  selected_for_audit    boolean not null default false, -- Δειγματοληψία (§3)
  checked_by            uuid references public.profiles(id),
  checked_at            date,
  approval_due          date,                           -- submitted_at + 30 ημέρες
  approved_at           date,
  approved_by           uuid references public.profiles(id),
  deemed_approved       boolean not null default false,
  inaccuracy            public.inaccuracy_grade not null default 'kamia',
  inaccuracy_pct        numeric(6,3),
  correction_deadline   date,
  remarks               text,

  contractual_amount    numeric(14,2) not null default 0, -- Ποσότητες εντός σύμβασης
  extra_amount          numeric(14,2) not null default 0, -- Πέραν των συμβατικών (§1)
  total_amount          numeric(14,2) generated always as
                          (contractual_amount + extra_amount) stored,

  document_id           uuid references public.documents(id),
  legal_ref_id          text references public.legal_refs(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (project_id, mtype, serial_no)
);

create index measurements_project_status_idx on public.measurements (project_id, status);

create trigger trg_measurements_touch
  before update on public.measurements
  for each row execute function app.touch_updated_at();

comment on table public.measurements is
  'Επιμετρήσεις (άρθρο 151 ν.4412/2016). Συντάσσονται σε κάθε τμηματική '
  'προθεσμία ή μηνιαίως, ανά διακριτό τμήμα έργου, με δήλωση αληθείας του '
  'αναδόχου, και αποτελούν ΠΡΟΑΠΑΙΤΟΥΜΕΝΟ για την υποβολή λογαριασμού.';

comment on column public.measurements.selected_for_audit is
  'Άρθρο 151 §3: ο προϊστάμενος της Δ.Υ. διενεργεί ΥΠΟΧΡΕΩΤΙΚΑ δειγματοληπτικό '
  'έλεγχο στο 40% των υποβληθεισών επιμετρήσεων ή σε τουλάχιστον τέσσερις (4), '
  'εφόσον οι υποβληθείσες είναι λιγότερες από δέκα (10).';

create table public.measurement_lines (
  id                 uuid primary key default gen_random_uuid(),
  measurement_id     uuid not null references public.measurements(id) on delete cascade,
  budget_item_id     uuid not null references public.budget_items(id) on delete restrict,
  quantity_period    numeric(16,4) not null default 0,  -- Ποσότητα περιόδου
  quantity_cumul     numeric(16,4) not null default 0,  -- Σωρευτική ποσότητα
  unit_price         numeric(14,4) not null,
  amount_period      numeric(14,2) generated always as
                       (round(quantity_period * unit_price, 2)) stored,
  amount_cumul       numeric(14,2) generated always as
                       (round(quantity_cumul  * unit_price, 2)) stored,
  measurement_data   jsonb,                             -- Επιμετρητικά στοιχεία/υπολογισμοί
  drawing_refs       text[],
  is_hidden_work     boolean not null default false,    -- Αφανής εργασία (§7)
  hidden_notice_id   uuid,                              -- FK ορίζεται πιο κάτω
  exceeds_contract   boolean not null default false,
  unique (measurement_id, budget_item_id)
);

create index measurement_lines_item_idx on public.measurement_lines (budget_item_id);

-- Δειγματοληπτικοί έλεγχοι (άρθρο 151 §3-6)
create table public.measurement_audits (
  id                 uuid primary key default gen_random_uuid(),
  measurement_id     uuid not null references public.measurements(id) on delete cascade,
  audit_round        integer not null default 1,
  ordered_at         date not null,
  ordered_by         uuid references public.profiles(id),
  auditor            text not null,
  performed_at       date,
  findings           text,
  grade              public.inaccuracy_grade not null default 'kamia',
  deviation_pct      numeric(6,3),
  full_audit_ordered boolean not null default false,    -- Πλήρης έλεγχος (§4)
  sanction_applied   text,                              -- Κύρωση/κατάπτωση εγγύησης (§5-6)
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (measurement_id, audit_round)
);

comment on table public.measurement_audits is
  'Δειγματοληπτικός/πλήρης έλεγχος επιμετρήσεων. Επανειλημμένη υποβολή ψευδών '
  'επιμετρήσεων επισύρει υποχρεωτική έκπτωση του αναδόχου και κατάπτωση της '
  'εγγύησης καλής εκτέλεσης (άρθρο 151 §5-6 ν.4412/2016).';

-- ---------------------------------------------------------------------
-- 8.2 ΑΦΑΝΕΙΣ ΕΡΓΑΣΙΕΣ — «ΠΠΑΕ» (άρθρο 151 §7)
-- ---------------------------------------------------------------------
create table public.hidden_work_notices (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null references public.projects(id) on delete cascade,
  serial_no            integer not null,
  work_description     text not null,
  location             text not null,
  work_group_id        bigint references public.work_groups(id),

  -- ΑΝΑΔΟΧΟΣ: δήλωση γνωστοποίησης αφανών εργασιών + πρόσκληση επιβλέποντος
  declaration_at       date not null,                   -- Δήλωση γνωστοποίησης
  declared_by_staff    uuid references public.contractor_staff(id),
  truth_declaration    boolean not null default false,  -- Δήλωση περί αληθείας
  invitation_sent_at   date not null,                   -- Πρόσκληση προς επιβλέποντα
  inspection_due       date generated always as (invitation_sent_at + 3) stored,

  -- ΕΠΙΒΛΕΠΩΝ: έλεγχος πριν την επικάλυψη & έκθεση
  inspected_at         date,
  inspected_by         uuid references public.profiles(id),
  supervisor_report_at date,                            -- Υποβάλλεται αμελλητί στη Δ.Υ.
  photos_count         integer not null default 0,
  video_path           text,
  covered_at           date,                            -- Ημερομηνία επικάλυψης

  -- Δ.Υ.: εγκριτική πράξη της επιμέτρησης αφανών εντός 30 ημερών
  measurement_id       uuid references public.measurements(id),
  approval_due         date,
  approved_at          date,
  approved_by          uuid references public.profiles(id),
  deemed_approved      boolean not null default false,

  supervisor_overdue   boolean not null default false,  -- Υπερημερία κυρίου του έργου
  status               text not null default 'declared',
  document_id          uuid references public.documents(id),
  legal_ref_id         text references public.legal_refs(id),
  created_at           timestamptz not null default now(),
  unique (project_id, serial_no),
  constraint hwn_status_chk check (status in
    ('declared','inspected','reported','measured','approved','overdue','rejected')),
  constraint hwn_cover_chk check (covered_at is null or inspected_at is not null),
  constraint hwn_photos_chk check (inspected_at is null or photos_count > 0)
);

create index hidden_work_notices_due_idx on public.hidden_work_notices (inspection_due)
  where inspected_at is null;

comment on table public.hidden_work_notices is
  'Αφανείς εργασίες / πρωτόκολλα παραλαβής αφανών εργασιών (ΠΠΑΕ) — άρθρο 151 §7 '
  'ν.4412/2016, όπως ισχύει. Ο ανάδοχος ΠΡΙΝ ΤΗΝ ΕΠΙΚΑΛΥΨΗ καλεί τον επιβλέποντα '
  'σε ημερομηνία που ΔΕΝ ΑΠΕΧΕΙ ΠΕΡΙΣΣΟΤΕΡΟ ΑΠΟ ΤΡΕΙΣ (3) ΗΜΕΡΕΣ από την '
  'κοινοποίηση. Ο επιβλέπων συντάσσει έκθεση με ΕΠΑΡΚΕΙΣ ΨΗΦΙΑΚΕΣ ΦΩΤΟΓΡΑΦΙΕΣ '
  '(εντάσσονται στο Μητρώο του Έργου). Η παράλειψη ελέγχου εντός της προθεσμίας '
  'ΣΥΝΙΣΤΑ ΥΠΕΡΗΜΕΡΙΑ ΤΟΥ ΚΥΡΙΟΥ ΤΟΥ ΕΡΓΟΥ. Η εγκριτική πράξη της επιμέτρησης '
  'εκδίδεται από τη Δ.Υ. εντός ΤΡΙΑΝΤΑ (30) ΗΜΕΡΩΝ από την υποβολή.';

comment on constraint hwn_photos_chk on public.hidden_work_notices is
  'Δεν επιτρέπεται καταχώριση ελέγχου αφανών χωρίς ψηφιακές φωτογραφίες '
  '(άρθρο 151 §7 — τεκμηρίωση στο Μητρώο Έργου).';

create table public.hidden_work_photos (
  id                 uuid primary key default gen_random_uuid(),
  notice_id          uuid not null references public.hidden_work_notices(id) on delete cascade,
  storage_path       text not null,
  taken_at           timestamptz,
  latitude           numeric(9,6),
  longitude          numeric(9,6),
  caption            text,
  checksum           text,
  uploaded_by        uuid references public.profiles(id),
  created_at         timestamptz not null default now()
);

alter table public.measurement_lines
  add constraint ml_hidden_notice_fk
  foreign key (hidden_notice_id) references public.hidden_work_notices(id) on delete set null;

-- Συγχρονισμός αριθμού φωτογραφιών
create or replace function app.sync_hidden_photos_count()
returns trigger language plpgsql as $$
begin
  update public.hidden_work_notices h
     set photos_count = (select count(*) from public.hidden_work_photos p
                         where p.notice_id = h.id)
   where h.id = coalesce(new.notice_id, old.notice_id);
  return null;
end $$;

create trigger trg_sync_hidden_photos
  after insert or delete on public.hidden_work_photos
  for each row execute function app.sync_hidden_photos_count();

-- ---------------------------------------------------------------------
-- 8.3 ΤΕΛΙΚΗ ΕΠΙΜΕΤΡΗΣΗ (άρθρο 151 §9-11)
-- ---------------------------------------------------------------------
create table public.final_measurement (
  id                     uuid primary key default gen_random_uuid(),
  project_id             uuid not null unique references public.projects(id) on delete cascade,
  measurement_id         uuid references public.measurements(id),
  completion_date        date not null,                 -- Ημερομηνία περαίωσης εργασιών
  contractor_due         date,                          -- +2 μήνες: υποβολή από ανάδοχο
  submitted_at           date,
  supervisor_report_due  date,                          -- +2 μήνες: έκθεση επιβλέποντος
  supervisor_report_at   date,
  approval_due           date,                          -- +2 μήνες: έγκριση Δ.Υ.
  approved_at            date,
  approved_by            uuid references public.profiles(id),
  approval_ada           text,
  prepared_by_service    boolean not null default false, -- Συντάχθηκε από την υπηρεσία (§10)
  service_cost_charged   numeric(14,2),                  -- Σε βάρος του αναδόχου
  penalty_months         integer not null default 0,     -- Μήνες καθυστέρησης (max 6)
  penalty_amount         numeric(14,2) not null default 0, -- 2‰ ανά μήνα (§10)
  document_id            uuid references public.documents(id),
  legal_ref_id           text references public.legal_refs(id),
  created_at             timestamptz not null default now(),
  constraint fm_penalty_months_chk check (penalty_months between 0 and 6)
);

comment on table public.final_measurement is
  'Τελική επιμέτρηση (άρθρο 151 §9-11). Υποβάλλεται από τον ανάδοχο εντός ΔΥΟ (2) '
  'ΜΗΝΩΝ από την περαίωση· ο επιβλέπων υποβάλλει έκθεση εντός ΔΥΟ (2) ΜΗΝΩΝ· η '
  'Δ.Υ. εγκρίνει εντός ΔΥΟ (2) ΜΗΝΩΝ. Καθυστέρηση υποβολής επισύρει ποινική ρήτρα '
  '2‰ της συμβατικής αξίας ανά συμπληρωμένο μήνα, με ανώτατο όριο έξι (6) μήνες. '
  'Η ΕΓΚΡΙΣΗ ΤΗΣ ΤΕΛΙΚΗΣ ΕΠΙΜΕΤΡΗΣΗΣ ΕΙΝΑΙ ΤΟ ΓΕΓΟΝΟΣ ΠΟΥ ΕΝΕΡΓΟΠΟΙΕΙ ΤΗ ΜΕΙΩΣΗ '
  'ΤΗΣ ΕΓΓΥΗΣΗΣ ΚΑΛΗΣ ΕΚΤΕΛΕΣΗΣ ΚΑΤΑ 70% (άρθρο 72 §14 περ. β΄).';

-- ---------------------------------------------------------------------
-- 8.4 ΑΥΤΟΜΑΤΙΣΜΟΙ ΠΡΟΘΕΣΜΙΩΝ
-- ---------------------------------------------------------------------
create or replace function app.set_measurement_dates()
returns trigger language plpgsql as $$
begin
  if new.submitted_at is not null and new.approval_due is null then
    new.approval_due := new.submitted_at + 30;   -- άρθρο 151 §7 (εγκριτική πράξη)
  end if;
  return new;
end $$;

create trigger trg_measurement_dates
  before insert or update on public.measurements
  for each row execute function app.set_measurement_dates();

create or replace function app.set_final_measurement_dates()
returns trigger language plpgsql as $$
begin
  new.contractor_due := (new.completion_date + interval '2 months')::date;
  if new.submitted_at is not null then
    new.supervisor_report_due := (new.submitted_at + interval '2 months')::date;
  end if;
  if new.supervisor_report_at is not null then
    new.approval_due := (new.supervisor_report_at + interval '2 months')::date;
  end if;
  -- Ποινική ρήτρα 2‰ ανά μήνα καθυστέρησης, έως 6 μήνες (άρθρο 151 §10)
  if new.submitted_at is not null and new.submitted_at > new.contractor_due then
    new.penalty_months := least(6,
      greatest(0, (extract(year  from age(new.submitted_at, new.contractor_due))*12
                 + extract(month from age(new.submitted_at, new.contractor_due)))::int));
    new.penalty_amount := round(
      coalesce((select c.initial_value_net from public.contracts c
                where c.project_id = new.project_id), 0)
      * 0.002 * new.penalty_months, 2);
  end if;
  return new;
end $$;

create trigger trg_final_measurement_dates
  before insert or update on public.final_measurement
  for each row execute function app.set_final_measurement_dates();

-- Κανόνας δειγματοληψίας άρθρου 151 §3
create or replace function public.required_audit_count(p_project_id uuid)
returns integer language sql stable as $$
  select case
           when count(*) = 0 then 0
           when count(*) < 10 then least(4, count(*))::int
           else ceil(count(*) * 0.40)::int
         end
  from public.measurements m
  where m.project_id = p_project_id
    and m.mtype = 'tmimatiki'
    and m.submitted_at is not null;
$$;

comment on function public.required_audit_count(uuid) is
  'Επιστρέφει τον ελάχιστο αριθμό επιμετρήσεων που πρέπει να ελεγχθούν '
  'δειγματοληπτικά: 40% των υποβληθεισών, ή τουλάχιστον 4 αν είναι λιγότερες '
  'από 10 (άρθρο 151 §3 ν.4412/2016).';

-- >>>>>>>>>>>>>>>>>>>> 0009_payments_ape.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0009 : Λογαριασμοί (άρθρο 152) και Ανακεφαλαιωτικοί Πίνακες
--                  Εργασιών — ΑΠΕ (άρθρα 155-156)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 9.1 ΓΝΩΜΟΔΟΤΗΣΕΙΣ ΤΕΧΝΙΚΟΥ ΣΥΜΒΟΥΛΙΟΥ
-- ---------------------------------------------------------------------
create table public.technical_council_opinions (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  subject            text not null,
  subject_kind       text not null,                    -- 'ape','symplirwmatiki','epi_elasson','ensta','ekptosi'
  requested_at       date not null,
  meeting_date       date,
  opinion_no         text,
  outcome            public.decision_outcome not null default 'pending',
  opinion_text       text,
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint tco_kind_chk check (subject_kind in
    ('ape','symplirwmatiki','epi_elasson','ensta','ekptosi','dialysi','paratasi','allo'))
);

comment on table public.technical_council_opinions is
  'Γνωμοδοτήσεις Τεχνικού Συμβουλίου. Απαιτούνται υποχρεωτικά πριν την υπογραφή '
  'συμπληρωματικής σύμβασης (άρθρο 156 §1 περ. ε΄) και για τη χρήση επί έλασσον '
  'δαπανών (άρθρο 156 §3γ), κατόπιν εισήγησης της Δ.Υ.';

-- ---------------------------------------------------------------------
-- 9.2 ΑΝΑΚΕΦΑΛΑΙΩΤΙΚΟΙ ΠΙΝΑΚΕΣ ΕΡΓΑΣΙΩΝ (ΑΠΕ)
-- ---------------------------------------------------------------------
create table public.ape (
  id                      uuid primary key default gen_random_uuid(),
  project_id              uuid not null references public.projects(id) on delete cascade,
  serial_no               integer not null,            -- 1ος, 2ος ΑΠΕ ...
  atype                   public.ape_type not null,
  budget_version_id       uuid references public.budget_versions(id),
  new_price_protocol_id   uuid references public.new_price_protocols(id),

  reason                  text not null,               -- Αιτιολόγηση αναγκαιότητας
  drafted_at              date not null,
  drafted_by              uuid references public.profiles(id),

  -- Οικονομικά (όλα χωρίς ΦΠΑ)
  initial_contract_value  numeric(14,2) not null,      -- Αξία αρχικής σύμβασης
  previous_ape_value      numeric(14,2) not null default 0,
  works_value             numeric(14,2) not null default 0,
  ge_oe_amount            numeric(14,2) not null default 0,
  contingency_used        numeric(14,2) not null default 0,  -- Χρήση απροβλέπτων (§3β)
  contingency_remaining   numeric(14,2) not null default 0,
  savings_used            numeric(14,2) not null default 0,  -- Χρήση επί έλασσον (§3γ)
  revision_amount         numeric(14,2) not null default 0,
  new_total_value         numeric(14,2) not null,      -- Νέα συνολική δαπάνη
  delta_amount            numeric(14,2) generated always as
                            (new_total_value - initial_contract_value) stored,
  delta_pct               numeric(8,4),                -- % επί της αρχικής σύμβασης

  supplementary_needed    boolean not null default false,  -- Απαιτείται συμπληρωματική σύμβαση
  supplementary_value     numeric(14,2) not null default 0,
  extra_guarantee_id      uuid references public.guarantees(id),

  -- Έγκριση
  contractor_signature    public.signature_kind,
  contractor_signed_at    date,
  reservation_text        text,
  tc_opinion_id           uuid references public.technical_council_opinions(id),
  status                  public.ape_status not null default 'draft',
  approved_at             date,
  approved_by             uuid references public.profiles(id),
  approval_decision_no    text,
  approval_ada            text,
  document_id             uuid references public.documents(id),
  legal_ref_id            text references public.legal_refs(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (project_id, serial_no)
);

create trigger trg_ape_touch
  before update on public.ape
  for each row execute function app.touch_updated_at();

comment on table public.ape is
  'Ανακεφαλαιωτικοί Πίνακες Εργασιών (άρθρο 156 §2 ν.4412/2016). Κάθε τροποποίηση '
  'σύμβασης απαιτεί ΑΠΕ που περιλαμβάνει εργασίες, τιμές μονάδος, ποσότητες, '
  'κονδύλια απροβλέπτων, αναθεώρησης και ΦΠΑ, καθώς και τον αρχικό, τον προηγούμενο '
  'και τον νέο προϋπολογισμό. Οι εργασίες των άρθρων 154-155 δεν απαιτούν '
  'προηγούμενο ΑΠΕ.';

alter table public.budget_versions
  add constraint budget_versions_ape_fk
  foreign key (ape_id) references public.ape(id) on delete set null;

alter table public.apologistika
  add constraint apologistika_ape_fk
  foreign key (included_in_ape_id) references public.ape(id) on delete set null;

alter table public.guarantees
  add constraint guarantees_ape_fk
  foreign key (covers_ape_id) references public.ape(id) on delete set null;

alter table public.new_price_protocols
  add constraint npp_tc_opinion_fk
  foreign key (tc_opinion_id) references public.technical_council_opinions(id) on delete set null;

-- Γραμμές ΑΠΕ ανά άρθρο τιμολογίου
create table public.ape_lines (
  id                 uuid primary key default gen_random_uuid(),
  ape_id             uuid not null references public.ape(id) on delete cascade,
  budget_item_id     uuid references public.budget_items(id) on delete set null,
  new_price_item_id  uuid references public.new_price_items(id) on delete set null,
  work_group_id      bigint references public.work_groups(id),
  item_code          text not null,
  description        text not null,
  unit               text not null,
  unit_price         numeric(14,4) not null,
  qty_initial        numeric(16,4) not null default 0,
  qty_previous       numeric(16,4) not null default 0,
  qty_new            numeric(16,4) not null default 0,
  amount_initial     numeric(14,2) generated always as
                       (round(qty_initial * unit_price, 2)) stored,
  amount_new         numeric(14,2) generated always as
                       (round(qty_new * unit_price, 2)) stored,
  delta_amount       numeric(14,2) generated always as
                       (round((qty_new - qty_initial) * unit_price, 2)) stored,
  funding_source     text not null default 'symvatiko', -- 'symvatiko'|'apravlepta'|'epi_elasson'|'symplirwmatiki'
  is_new_item        boolean not null default false,
  notes              text,
  constraint al_funding_chk check (funding_source in
    ('symvatiko','apravlepta','epi_elasson','symplirwmatiki','apologistika'))
);

create index ape_lines_ape_idx   on public.ape_lines (ape_id);
create index ape_lines_group_idx on public.ape_lines (work_group_id);

-- ---------------------------------------------------------------------
-- 9.3 ΚΑΝΟΝΕΣ ΕΛΕΓΧΟΥ ΑΠΕ — Fail-Safe άρθρου 156
-- ---------------------------------------------------------------------
create or replace function app.ape_validation(p_ape_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare
  a               public.ape%rowtype;
  c               public.contracts%rowtype;
  v_cum_increase  numeric;
  v_group         record;
  v_savings_total numeric;
begin
  select * into a from public.ape where id = p_ape_id;
  if not found then return; end if;
  select * into c from public.contracts where project_id = a.project_id;

  -- (1) Σωρευτικό όριο αύξησης 50% της αξίας της αρχικής σύμβασης (άρθρο 156 §1)
  select coalesce(sum(x.delta_amount), 0) into v_cum_increase
  from public.ape x
  where x.project_id = a.project_id
    and (x.status = 'approved' or x.id = a.id)
    and x.delta_amount > 0;

  if c.initial_value_net > 0
     and v_cum_increase > c.initial_value_net * 0.50 then
    return next ('APE_LIMIT_50',
      format('Υπέρβαση του ανώτατου ορίου 50%%: σωρευτική αύξηση %s € έναντι ορίου %s €.',
             to_char(v_cum_increase,'FM999G999G990D00'),
             to_char(c.initial_value_net*0.50,'FM999G999G990D00')),
      'hard', 'N4412/156/1')::app.blocker;
  end if;

  -- (2) Όριο απροβλέπτων 9% ή 15% (άρθρο 156 §3β)
  if a.contingency_used > c.contingency_amount + 0.005 then
    return next ('APE_CONTINGENCY',
      format('Η χρήση απροβλέπτων (%s €) υπερβαίνει το εγκεκριμένο κονδύλιο %s%% (%s €).',
             to_char(a.contingency_used,'FM999G999G990D00'),
             to_char(c.contingency_pct,'FM990D00'),
             to_char(c.contingency_amount,'FM999G999G990D00')),
      'hard', 'N4412/156/3b')::app.blocker;
  end if;

  -- (3) Επί έλασσον: ≤ 20% ανά ΟΜΑΔΑ ΕΡΓΑΣΙΩΝ (άρθρο 156 §3γ)
  for v_group in
    select wg.title as group_title,
           sum(case when al.delta_amount < 0 then -al.delta_amount else 0 end) as savings,
           sum(al.amount_initial) as group_initial
    from public.ape_lines al
    join public.work_groups wg on wg.id = al.work_group_id
    where al.ape_id = p_ape_id
    group by wg.title
  loop
    if v_group.group_initial > 0
       and v_group.savings > v_group.group_initial * 0.20 then
      return next ('APE_SAVINGS_GROUP_20',
        format('Ομάδα «%s»: οι επί έλασσον δαπάνες (%s €) υπερβαίνουν το 20%% της συμβατικής δαπάνης της ομάδας (%s €).',
               v_group.group_title,
               to_char(v_group.savings,'FM999G999G990D00'),
               to_char(v_group.group_initial*0.20,'FM999G999G990D00')),
        'hard', 'N4412/156/3c')::app.blocker;
    end if;
  end loop;

  -- (4) Επί έλασσον: ≤ 10% της αξίας της αρχικής σύμβασης (άρθρο 156 §3γ)
  select coalesce(sum(case when al.delta_amount < 0 then -al.delta_amount else 0 end), 0)
    into v_savings_total
  from public.ape_lines al where al.ape_id = p_ape_id;

  if c.initial_value_net > 0
     and v_savings_total > c.initial_value_net * 0.10 then
    return next ('APE_SAVINGS_TOTAL_10',
      format('Οι επί έλασσον δαπάνες (%s €) υπερβαίνουν το 10%% της αξίας της αρχικής σύμβασης (%s €).',
             to_char(v_savings_total,'FM999G999G990D00'),
             to_char(c.initial_value_net*0.10,'FM999G999G990D00')),
      'hard', 'N4412/156/3c')::app.blocker;
  end if;

  -- (5) Απαγόρευση εισαγωγής ΝΕΩΝ άρθρων με χρηματοδότηση από επί έλασσον
  if exists (select 1 from public.ape_lines al
             where al.ape_id = p_ape_id
               and al.is_new_item
               and al.funding_source = 'epi_elasson') then
    return next ('APE_NEW_ITEM_FROM_SAVINGS',
      'Δεν επιτρέπεται η κάλυψη ΝΕΩΝ άρθρων (μη περιλαμβανομένων στην αρχική σύμβαση) από επί έλασσον δαπάνες.',
      'hard', 'N4412/156/3c')::app.blocker;
  end if;

  -- (6) Γνωμοδότηση Τεχνικού Συμβουλίου όπου απαιτείται
  if (a.supplementary_needed or v_savings_total > 0)
     and a.tc_opinion_id is null then
    return next ('APE_TC_OPINION',
      'Απαιτείται γνωμοδότηση Τεχνικού Συμβουλίου (συμπληρωματική σύμβαση ή χρήση επί έλασσον δαπανών).',
      'hard', 'N4412/156/1e')::app.blocker;
  end if;

  -- (7) Υπογραφή/κοινοποίηση στον ανάδοχο
  if a.contractor_signature is null then
    return next ('APE_SIGNATURE',
      'Ο ΑΠΕ δεν έχει υπογραφεί από τον ανάδοχο ούτε έχει κοινοποιηθεί κατ'' άρθρο 143.',
      'soft', 'N4412/156/7')::app.blocker;
  end if;

  -- (8) ΠΚΤΜΝΕ όταν υπάρχουν νέα άρθρα
  if exists (select 1 from public.ape_lines al where al.ape_id = p_ape_id and al.is_new_item)
     and a.new_price_protocol_id is null then
    return next ('APE_PKTMNE_MISSING',
      'Ο ΑΠΕ περιλαμβάνει νέες εργασίες χωρίς συνοδευτικό Π.Κ.Τ.Μ.Ν.Ε.',
      'hard', 'N4412/156/5')::app.blocker;
  end if;
end $$;

comment on function app.ape_validation(uuid) is
  'Ελεγκτής ορίων άρθρου 156 ν.4412/2016: 50% σωρευτική αύξηση, 9%/15% απρόβλεπτα, '
  '20% ανά ομάδα εργασιών και 10% συνολικά για επί έλασσον, απαγόρευση νέων άρθρων '
  'από επί έλασσον, υποχρεωτική γνωμοδότηση Τεχνικού Συμβουλίου, ΠΚΤΜΝΕ.';

create or replace function app.guard_ape_approval()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_blockers text;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    select string_agg('• ' || b.message || ' [' || b.legal_ref || ']', E'\n')
      into v_blockers
    from app.ape_validation(new.id) b where b.severity = 'hard';

    if v_blockers is not null then
      raise exception E'ΔΕΝ ΕΠΙΤΡΕΠΕΤΑΙ η έγκριση του ΑΠΕ.\n%', v_blockers
        using errcode = 'check_violation';
    end if;
    if new.approved_at is null then new.approved_at := current_date; end if;
  end if;
  return new;
end $$;

create trigger trg_guard_ape_approval
  before update on public.ape
  for each row execute function app.guard_ape_approval();

-- ---------------------------------------------------------------------
-- 9.4 ΛΟΓΑΡΙΑΣΜΟΙ / ΠΙΣΤΟΠΟΙΗΣΕΙΣ (άρθρο 152)
-- ---------------------------------------------------------------------
create table public.payment_certificates (
  id                    uuid primary key default gen_random_uuid(),
  project_id            uuid not null references public.projects(id) on delete cascade,
  ptype                 public.payment_type not null default 'tmimatikos',
  serial_no             integer not null,               -- Α/Α λογαριασμού
  period_from           date,
  period_to             date,
  measurement_id        uuid references public.measurements(id),
  budget_version_id     uuid references public.budget_versions(id),

  submitted_at          date,
  approval_due          date,                           -- submitted_at + 1 μήνας
  returned_at           date,                           -- Επιστροφή για συμπλήρωση
  resubmitted_at        date,
  status                public.payment_status not null default 'draft',
  approved_at           date,
  approved_by           uuid references public.profiles(id),
  deemed_approved       boolean not null default false, -- Σιωπηρή έγκριση

  -- Οικονομικά στοιχεία
  works_cumulative      numeric(14,2) not null default 0,
  ge_oe_amount          numeric(14,2) not null default 0,
  apologistika_amount   numeric(14,2) not null default 0,
  revision_amount       numeric(14,2) not null default 0,
  compensations         numeric(14,2) not null default 0,  -- Αναγνωρισμένες αποζημιώσεις
  gross_cumulative      numeric(14,2) not null default 0,
  previous_certified    numeric(14,2) not null default 0,
  period_amount         numeric(14,2) generated always as
                          (gross_cumulative - previous_certified) stored,

  -- Κρατήσεις / μειώσεις
  advance_amortization  numeric(14,2) not null default 0, -- Απόσβεση προκαταβολής (άρθρο 150)
  advance_interest      numeric(14,2) not null default 0,
  penalties_amount      numeric(14,2) not null default 0, -- Ποινικές ρήτρες (άρθρα 146,148,151)
  retentions_pct        numeric(5,2)  not null default 5.00,  -- Κρατήσεις 5% (άρθρο 152)
  retentions_amount     numeric(14,2) not null default 0,
  other_deductions      numeric(14,2) not null default 0,
  vat_rate              numeric(5,2)  not null default 24.00,
  vat_amount            numeric(14,2) not null default 0,
  net_payable           numeric(14,2) not null default 0,

  -- Συνημμένα (άρθρο 152)
  has_summary_table     boolean not null default false, -- Ανακεφαλαιωτικός συνοπτικός πίνακας επιμετρήσεων
  has_revision_calc     boolean not null default false, -- Υπολογισμός αναθεώρησης
  has_apologistika_docs boolean not null default false, -- Δικαιολογητικά απολογιστικών
  has_decisions         boolean not null default false, -- Αποφάσεις αποζημιώσεων/ρητρών

  payment_order_no      text,                           -- Αρ. χρηματικού εντάλματος
  paid_at               date,
  document_id           uuid references public.documents(id),
  legal_ref_id          text references public.legal_refs(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (project_id, ptype, serial_no)
);

create trigger trg_payment_certificates_touch
  before update on public.payment_certificates
  for each row execute function app.touch_updated_at();

comment on table public.payment_certificates is
  'Λογαριασμοί (άρθρο 152 ν.4412/2016). Υποβάλλονται στη Δ.Υ., η οποία τους '
  'ελέγχει, διορθώνει και ΕΓΚΡΙΝΕΙ ΕΝΤΟΣ ΕΝΟΣ (1) ΜΗΝΟΣ. Αν η προθεσμία παρέλθει '
  'άπρακτη, ο λογαριασμός ΘΕΩΡΕΙΤΑΙ ΕΓΚΕΚΡΙΜΕΝΟΣ και καθίσταται πληρωτέος, '
  'υπόκειται όμως σε μεταγενέστερο έλεγχο και διόρθωση. Σε κάθε πληρωμή '
  'διενεργούνται κρατήσεις 5%.';

create table public.payment_certificate_lines (
  id                 uuid primary key default gen_random_uuid(),
  certificate_id     uuid not null references public.payment_certificates(id) on delete cascade,
  budget_item_id     uuid references public.budget_items(id) on delete set null,
  item_code          text not null,
  description        text not null,
  unit               text,
  unit_price         numeric(14,4) not null default 0,
  qty_cumulative     numeric(16,4) not null default 0,
  qty_previous       numeric(16,4) not null default 0,
  amount_cumulative  numeric(14,2) not null default 0,
  work_group_id      bigint references public.work_groups(id)
);

-- Κανόνες: προαπαιτούμενα υποβολής λογαριασμού
create or replace function app.payment_validation(p_cert_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare pc public.payment_certificates%rowtype;
begin
  select * into pc from public.payment_certificates where id = p_cert_id;
  if not found then return; end if;

  if pc.measurement_id is null then
    return next ('PAY_NO_MEASUREMENT',
      'Δεν έχει συνδεθεί εγκεκριμένη επιμέτρηση. Η υποβολή επιμέτρησης αποτελεί προϋπόθεση πληρωμής.',
      'hard', 'N4412/151/2')::app.blocker;
  else
    if not exists (select 1 from public.measurements m
                   where m.id = pc.measurement_id
                     and m.status in ('approved','deemed_approved')) then
      return next ('PAY_MEASUREMENT_NOT_APPROVED',
        'Η συνδεδεμένη επιμέτρηση δεν έχει εγκριθεί.',
        'hard', 'N4412/151/2')::app.blocker;
    end if;
  end if;

  if not pc.has_summary_table then
    return next ('PAY_NO_SUMMARY',
      'Λείπει ο ανακεφαλαιωτικός συνοπτικός πίνακας των επιμετρήσεων εργασιών.',
      'hard', 'N4412/152')::app.blocker;
  end if;

  if pc.revision_amount <> 0 and not pc.has_revision_calc then
    return next ('PAY_NO_REVISION_CALC',
      'Περιλαμβάνεται αναθεώρηση χωρίς συνημμένο υπολογισμό αναθεώρησης.',
      'hard', 'N4412/152')::app.blocker;
  end if;

  if pc.apologistika_amount <> 0 and not pc.has_apologistika_docs then
    return next ('PAY_NO_APOL_DOCS',
      'Περιλαμβάνονται απολογιστικές εργασίες χωρίς τα προβλεπόμενα δικαιολογητικά.',
      'hard', 'N4412/154')::app.blocker;
  end if;

  -- Ο τελικός λογαριασμός προϋποθέτει παραλαβή & εγκεκριμένο πρωτόκολλο
  if pc.ptype = 'telikos' then
    if not exists (select 1 from public.acceptances ac
                   where ac.project_id = pc.project_id
                     and ac.status in ('completed','auto_completed')) then
      return next ('PAY_FINAL_NO_ACCEPTANCE',
        'Ο τελικός λογαριασμός υποβάλλεται μετά την παραλαβή του έργου και την έγκριση του πρωτοκόλλου.',
        'hard', 'N4412/152')::app.blocker;
    end if;
  end if;
end $$;

-- Αυτόματος υπολογισμός προθεσμίας & σιωπηρής έγκρισης
create or replace function app.set_payment_dates()
returns trigger language plpgsql as $$
begin
  if new.submitted_at is not null then
    new.approval_due := (coalesce(new.resubmitted_at, new.submitted_at)
                         + interval '1 month')::date;
  end if;
  new.retentions_amount := round(new.gross_cumulative * new.retentions_pct / 100, 2)
                           - coalesce((select sum(p.retentions_amount)
                                       from public.payment_certificates p
                                       where p.project_id = new.project_id
                                         and p.serial_no < new.serial_no
                                         and p.ptype = new.ptype), 0);
  -- Σημείωση: η period_amount είναι generated column και υπολογίζεται ΜΕΤΑ τα
  -- BEFORE triggers, γι' αυτό εδώ αναπαράγεται ρητά ο τύπος της.
  new.net_payable := round(
      (new.gross_cumulative - new.previous_certified)
    - new.advance_amortization - new.advance_interest
    - new.penalties_amount - new.retentions_amount - new.other_deductions, 2);
  new.vat_amount := round(greatest(new.net_payable,0) * new.vat_rate / 100, 2);
  return new;
end $$;

create trigger trg_set_payment_dates
  before insert or update on public.payment_certificates
  for each row execute function app.set_payment_dates();

-- >>>>>>>>>>>>>>>>>>>> 0010_completion_acceptance.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0010 : Παρατάσεις & αναστολές (άρθρο 147), ποινικές ρήτρες
--                  (άρθρα 146, 148, 151), περαίωση & Βεβαίωση Περάτωσης
--                  (άρθρο 168), συντήρηση (άρθρο 171), παραλαβή (άρθρο 172),
--                  ενστάσεις (άρθρο 174)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 10.1 ΠΑΡΑΤΑΣΕΙΣ ΠΡΟΘΕΣΜΙΩΝ (άρθρο 147 §5-6, §8)
-- ---------------------------------------------------------------------
create table public.time_extensions (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  deadline_id        uuid references public.contract_deadlines(id) on delete set null,
  serial_no          integer not null,
  requested_by       public.party_type not null default 'anadochos',
  requested_at       date,                              -- Πριν τη λήξη της προθεσμίας
  request_doc_id     uuid references public.documents(id),
  reason             text not null,
  responsibility     text not null,                     -- 'kyrios_ergou' | 'anadochos' | 'meikti'
  etype              public.extension_type not null,
  requested_days     integer not null check (requested_days > 0),
  granted_days       integer,
  decision_due       date,                              -- requested_at + 30 ημέρες (§5)
  decided_at         date,
  outcome            public.decision_outcome not null default 'pending',
  deemed_accepted    boolean not null default false,    -- Σιωπηρή αποδοχή (§5)
  new_end_date       date,
  decision_no        text,
  decision_ada       text,
  penalties_apply    boolean not null default false,    -- Ρήτρες και σε παράταση «χωρίς αναθεώρηση»
  tc_opinion_id      uuid references public.technical_council_opinions(id),
  beyond_oriaki      boolean not null default false,    -- Παράταση πέραν της οριακής (§8)
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (project_id, serial_no),
  constraint te_resp_chk check (responsibility in ('kyrios_ergou','anadochos','meikti'))
);

comment on table public.time_extensions is
  'Παρατάσεις προθεσμιών (άρθρο 147 ν.4412/2016). Το αίτημα υποβάλλεται ΠΡΙΝ ΤΗ '
  'ΛΗΞΗ της ισχύουσας προθεσμίας. Η αρμόδια αρχή αποφασίζει ΕΝΤΟΣ 30 ΗΜΕΡΩΝ· '
  'άπρακτη πάροδος = ΣΙΩΠΗΡΗ ΑΠΟΔΟΧΗ, με αναδρομική ισχύ από τη λήξη της '
  'προηγούμενης προθεσμίας. Η παράταση χορηγείται «με αναθεώρηση» (υπαιτιότητα '
  'κυρίου του έργου) ή «χωρίς αναθεώρηση» (υπαιτιότητα αναδόχου)· στη δεύτερη '
  'περίπτωση οι ποινικές ρήτρες εξακολουθούν να επιβάλλονται.';

-- Αναστολές λόγω ανωτέρας βίας (άρθρο 147 §7)
create table public.suspensions (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  event_description  text not null,
  event_at           date not null,
  request_due        date generated always as (event_at + 10) stored,  -- 10 ημέρες
  requested_at       date,
  decision_due       date,                              -- requested_at + 10 ημέρες
  decided_at         date,
  outcome            public.decision_outcome not null default 'pending',
  deemed_accepted    boolean not null default false,
  suspended_from     date,
  suspended_to       date,
  suspended_days     integer,
  max_allowed_days   integer,                           -- 1/10 συνολικής ή 30 ημέρες
  decision_ada       text,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now()
);

comment on table public.suspensions is
  'Αναστολή προθεσμιών λόγω ανωτέρας βίας (άρθρο 147 §7): αίτημα εντός 10 ημερών '
  'από το γεγονός, απόφαση εντός 10 ημερών (σιωπηρή αποδοχή), ανώτατο όριο '
  'αναστολής το 1/10 της συνολικής προθεσμίας για συμβάσεις άνω του έτους ή '
  '30 ημέρες για μικρότερες.';

-- ---------------------------------------------------------------------
-- 10.2 ΠΟΙΝΙΚΕΣ ΡΗΤΡΕΣ (άρθρα 146, 148, 151 §10)
-- ---------------------------------------------------------------------
create table public.penalties (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  kind               public.penalty_kind not null,
  period_from        date,
  period_to          date,
  days_count         integer,
  rate_description   text,                              -- π.χ. '2‰ ανά μήνα', '150 €/ημέρα'
  base_amount        numeric(14,2),
  amount             numeric(14,2) not null check (amount >= 0),
  reason             text not null,
  decision_no        text,
  decision_date      date,
  decision_ada       text,
  imposed_by         uuid references public.profiles(id),
  applied_in_cert_id uuid references public.payment_certificates(id),
  waived             boolean not null default false,
  waive_reason       text,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now()
);

comment on table public.penalties is
  'Ποινικές ρήτρες: υπέρβαση προθεσμιών (άρθρο 148), παράλειψη τήρησης ημερολογίου '
  '100-500 €/ημέρα (άρθρο 146), καθυστέρηση υποβολής τελικής επιμέτρησης 2‰/μήνα '
  'με ανώτατο 6 μήνες (άρθρο 151 §10). Παρακρατούνται στον επόμενο λογαριασμό.';

-- Ρήτρα πρόσθετης καταβολής — πριμ (άρθρο 149)
create table public.bonus_clauses (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null unique references public.projects(id) on delete cascade,
  max_pct            numeric(5,2) not null,
  target_date        date not null,
  achieved_date      date,
  amount_awarded     numeric(14,2),
  decision_ada       text,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 10.3 ΠΕΡΑΙΩΣΗ & ΒΕΒΑΙΩΣΗ ΠΕΡΑΤΩΣΗΣ ΕΡΓΑΣΙΩΝ (άρθρο 168)
-- ---------------------------------------------------------------------
create table public.completions (
  id                        uuid primary key default gen_random_uuid(),
  project_id                uuid not null unique references public.projects(id) on delete cascade,

  -- Αφετηρία: λήξη εγκεκριμένου χρόνου περαίωσης
  approved_completion_date  date not null,
  contractor_declared_at    date,                       -- Δήλωση περαίωσης αναδόχου

  -- ΕΠΙΒΛΕΠΩΝ: έγγραφη αναφορά εντός 30 ημερών από τη λήξη (§1)
  supervisor_report_due     date generated always as (approved_completion_date + 30) stored,
  supervisor_report_at      date,
  supervisor_report_doc_id  uuid references public.documents(id),
  tests_completed           boolean not null default false,   -- Προβλεπόμενες δοκιμές
  defects_found             boolean not null default false,
  defects_severity          public.defect_severity,

  -- Δ.Υ.: έκδοση Βεβαίωσης Περάτωσης εντός 10 ημερών από την αναφορά (§2)
  certificate_due           date,
  certificate_issued_at     date,
  certificate_doc_id        uuid references public.documents(id),
  certificate_issued_by     uuid references public.profiles(id),
  actual_completion_date    date,                       -- Πραγματική ημ/νία περαίωσης (§3)
  contractor_notice_at      date,                       -- Όχληση αναδόχου
  deemed_issued             boolean not null default false,  -- Τεκμαίρεται εκδοθείσα (+30 ημ.)
  disciplinary_flag         boolean not null default false,  -- Άρθρο 141 §3

  legal_ref_id              text references public.legal_refs(id),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create trigger trg_completions_touch
  before update on public.completions
  for each row execute function app.touch_updated_at();

comment on table public.completions is
  'Περαίωση εργασιών & Βεβαίωση Περάτωσης (άρθρο 168 ν.4412/2016). Ο επιβλέπων '
  'αναφέρει εγγράφως στη Δ.Υ. ΕΝΤΟΣ 30 ΗΜΕΡΩΝ από τη λήξη του εγκεκριμένου χρόνου '
  'περαίωσης. Ο προϊστάμενος της Δ.Υ. εκδίδει τη Βεβαίωση ΕΝΤΟΣ 10 ΗΜΕΡΩΝ από τη '
  'λήψη της αναφοράς· αν δεν εκδοθεί, ΤΕΚΜΑΙΡΕΤΑΙ ΕΚΔΟΘΕΙΣΑ 30 ημέρες μετά την '
  'έγγραφη όχληση του αναδόχου, με πειθαρχική ευθύνη των υπαιτίων (άρθρο 141 §3). '
  'Επί επουσιωδών ελαττωμάτων τάσσεται εύλογη προθεσμία αποκατάστασης και η '
  'Βεβαίωση εκδίδεται με την πραγματική ημερομηνία περαίωσης, χωρίς προσμέτρηση '
  'του χρόνου αποκατάστασης.';

create table public.defects (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  source             text not null,                     -- 'peraiosi' | 'syntirisi' | 'paralavi'
  description        text not null,
  severity           public.defect_severity not null,
  identified_at      date not null,
  identified_by      uuid references public.profiles(id),
  remedy_deadline    date,
  remedied_at        date,
  verified_at        date,
  affects_function   boolean not null default false,
  affects_safety     boolean not null default false,
  affects_licensing  boolean not null default false,
  escalated_159_160  boolean not null default false,    -- Εφαρμογή άρθρων 159/160
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint defects_source_chk check (source in ('peraiosi','syntirisi','paralavi','loipa'))
);

comment on column public.defects.severity is
  'Επουσιώδη θεωρούνται τα ελαττώματα που δεν επηρεάζουν τη λειτουργικότητα του '
  'έργου, την ασφάλεια των χρηστών και τους όρους αδειοδότησης (άρθρο 168 §1).';

-- ---------------------------------------------------------------------
-- 10.4 ΧΡΟΝΟΣ ΥΠΟΧΡΕΩΤΙΚΗΣ ΣΥΝΤΗΡΗΣΗΣ (άρθρο 171)
-- ---------------------------------------------------------------------
create table public.maintenance_periods (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null unique references public.projects(id) on delete cascade,
  months             integer not null default 15,
  starts_on          date not null,                     -- Επομένη της Βεβαίωσης Περάτωσης
  ends_on            date not null,
  inspections_done   integer not null default 0,
  notes              text,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint mp_months_chk check (months between 1 and 60),
  constraint mp_dates_chk  check (ends_on > starts_on)
);

comment on table public.maintenance_periods is
  'Χρόνος υποχρεωτικής συντήρησης: γενικά 15 μήνες, έως 5 έτη σε ειδικές '
  'περιπτώσεις και δυνατή μείωση για έργα προϋπολογισμού < 250.000 €. Αρχίζει '
  'την ΕΠΟΜΕΝΗ της έκδοσης της Βεβαίωσης Περάτωσης (άρθρο 171 ν.4412/2016).';

-- ---------------------------------------------------------------------
-- 10.5 ΠΑΡΑΛΑΒΗ (άρθρο 172)
-- ---------------------------------------------------------------------
create table public.committees (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  ckind              text not null,                     -- 'paralavis' | 'timon' | 'autopsias'
  decision_no        text,
  decision_date      date,
  decision_ada       text,
  appointed_at       date,
  must_appoint_by    date,                              -- ≥3 μήνες πριν τη λήξη συντήρησης
  member_count       integer,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint committees_kind_chk check (ckind in ('paralavis','timon','autopsias','allo'))
);

create table public.committee_members (
  id                 uuid primary key default gen_random_uuid(),
  committee_id       uuid not null references public.committees(id) on delete cascade,
  profile_id         uuid references public.profiles(id),
  full_name          text not null,
  capacity           text not null,                     -- 'Τεχνικός υπάλληλος', 'Εκπρόσωπος ΤΕΕ'
  is_chair           boolean not null default false,
  is_external        boolean not null default false,    -- ΤΕΕ / ΓΕΩΤΕΕ
  is_observer        boolean not null default false,    -- Παρατηρητής αναδόχου (χωρίς ψήφο)
  created_at         timestamptz not null default now()
);

create table public.acceptances (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null unique references public.projects(id) on delete cascade,
  committee_id       uuid references public.committees(id),
  maintenance_end    date not null,
  deadline_3m        date generated always as
                       ((maintenance_end + interval '3 months')::date) stored,
  started_at         date,
  protocol_date      date,
  protocol_no        text,
  status             public.acceptance_status not null default 'not_due',
  auto_accepted      boolean not null default false,    -- Αυτοδίκαιη παραλαβή
  confirming_act_at  date,                              -- Βεβαιωτική πράξη Δ.Υ.
  suspended_reason   text,                              -- Αναστολή λόγω ελαττωμάτων
  approved_at        date,                              -- Έγκριση πρωτοκόλλου
  approval_ada       text,
  -- Υποχρεώσεις αναδόχου μετά την παραλαβή
  maintenance_manual boolean not null default false,
  operation_manual   boolean not null default false,
  digital_archive    boolean not null default false,    -- Ψηφιακή τεκμηρίωση σταδίων
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger trg_acceptances_touch
  before update on public.acceptances
  for each row execute function app.touch_updated_at();

comment on table public.acceptances is
  'Παραλαβή του έργου (άρθρο 172 ν.4412/2016). Διενεργείται εντός ΤΡΙΩΝ (3) ΜΗΝΩΝ '
  'από τη λήξη του χρόνου υποχρεωτικής συντήρησης· η επιτροπή (5μελής, με δύο '
  'εκπροσώπους ΤΕΕ/ΓΕΩΤΕΕ) ορίζεται τουλάχιστον ΤΡΕΙΣ (3) ΜΗΝΕΣ πριν τη λήξη. '
  'Αν η επιτροπή δεν ενεργήσει εντός της τρίμηνης προθεσμίας, η παραλαβή θεωρείται '
  'ΑΥΤΟΔΙΚΑΙΩΣ ΣΥΝΤΕΛΕΣΜΕΝΗ και εκδίδεται βεβαιωτική πράξη.';

-- ---------------------------------------------------------------------
-- 10.6 ΕΝΣΤΑΣΕΙΣ — ΔΙΟΙΚΗΤΙΚΗ ΕΠΙΛΥΣΗ ΔΙΑΦΟΡΩΝ (άρθρο 174)
-- ---------------------------------------------------------------------
create table public.objections (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  serial_no          integer not null,
  contested_doc_id   uuid references public.documents(id),
  contested_act      text not null,
  act_communicated_at date not null,                    -- Αφετηρία προθεσμίας
  filing_due         date generated always as (act_communicated_at + 15) stored,
  filed_at           date,
  claim_amount       numeric(14,2),
  grounds            text not null,
  tc_opinion_id      uuid references public.technical_council_opinions(id),
  decision_due       date,                              -- filed_at + 60 ημέρες (30 για έκπτωση)
  decided_at         date,
  outcome            public.decision_outcome not null default 'pending',
  deemed_accepted    boolean not null default false,    -- Σιωπηρή αποδοχή γνωμοδότησης
  decision_ada       text,
  is_admissible      boolean,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (project_id, serial_no)
);

comment on table public.objections is
  'Ενστάσεις κατά πράξεων/παραλείψεων της Δ.Υ. (άρθρο 174 ν.4412/2016): '
  'ανατρεπτική προθεσμία 15 ημερών από την κοινοποίηση, απόφαση της Προϊσταμένης '
  'Αρχής εντός 60 ημερών κατόπιν γνωμοδότησης του Τεχνικού Συμβουλίου (30 ημερών '
  'για ενστάσεις κατά απόφασης έκπτωσης του άρθρου 160)· άπρακτη πάροδος = '
  'σιωπηρή αποδοχή της γνωμοδότησης.';

-- ---------------------------------------------------------------------
-- 10.7 ΑΥΤΟΜΑΤΙΣΜΟΙ ΠΡΟΘΕΣΜΙΩΝ ΠΕΡΑΙΩΣΗΣ / ΠΑΡΑΛΑΒΗΣ
-- ---------------------------------------------------------------------
create or replace function app.set_completion_dates()
returns trigger language plpgsql as $$
begin
  if new.supervisor_report_at is not null then
    new.certificate_due := new.supervisor_report_at + 10;   -- άρθρο 168 §2
  end if;
  if new.certificate_issued_at is null
     and new.contractor_notice_at is not null
     and current_date > new.contractor_notice_at + 30 then
    new.deemed_issued := true;
    new.disciplinary_flag := true;                          -- άρθρο 141 §3
  end if;
  return new;
end $$;

create trigger trg_set_completion_dates
  before insert or update on public.completions
  for each row execute function app.set_completion_dates();

-- Με την έκδοση της Βεβαίωσης Περάτωσης ανοίγει ο χρόνος συντήρησης
create or replace function app.open_maintenance_period()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_months integer;
begin
  if new.certificate_issued_at is not null
     and old.certificate_issued_at is distinct from new.certificate_issued_at then

    select maintenance_months into v_months
    from public.contracts where project_id = new.project_id;
    v_months := coalesce(v_months, 15);

    insert into public.maintenance_periods
      (project_id, months, starts_on, ends_on, legal_ref_id)
    values (new.project_id, v_months,
            new.certificate_issued_at + 1,
            ((new.certificate_issued_at + 1) + (v_months || ' months')::interval)::date,
            'N4412/171')
    on conflict (project_id) do update
      set months     = excluded.months,
          starts_on  = excluded.starts_on,
          ends_on    = excluded.ends_on;

    insert into public.acceptances (project_id, maintenance_end, status, legal_ref_id)
    values (new.project_id,
            ((new.certificate_issued_at + 1) + (v_months || ' months')::interval)::date,
            'not_due', 'N4412/172')
    on conflict (project_id) do update
      set maintenance_end = excluded.maintenance_end;

    -- Η επιτροπή παραλαβής ορίζεται τουλάχιστον 3 μήνες πριν τη λήξη συντήρησης
    insert into public.committees (project_id, ckind, must_appoint_by, legal_ref_id)
    values (new.project_id, 'paralavis',
            (((new.certificate_issued_at + 1)
              + (v_months || ' months')::interval) - interval '3 months')::date,
            'N4412/172');
  end if;
  return null;
end $$;

create trigger trg_open_maintenance_period
  after update on public.completions
  for each row execute function app.open_maintenance_period();

-- >>>>>>>>>>>>>>>>>>>> 0011_guards_views.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0011 : Ειδικοί κανόνες σταδίων (guard functions),
--                  κανόνας μείωσης εγγυήσεων, όψεις παρακολούθησης
-- =====================================================================

-- Βάση υπολογισμού της εγγύησης καλής εκτέλεσης (άρθρο 72 §4)
alter table public.contracts
  add column if not exists estimated_guarantee_base numeric(14,2);

comment on column public.contracts.estimated_guarantee_base is
  'Βάση υπολογισμού της εγγύησης καλής εκτέλεσης (εκτιμώμενη αξία σύμβασης χωρίς '
  'δικαιώματα προαίρεσης και ΦΠΑ) — άρθρο 72 §4 ν.4412/2016.';

-- ---------------------------------------------------------------------
-- 11.1 GUARD: Εγγυητικές επιστολές (άρθρο 72 §4)
-- ---------------------------------------------------------------------
create or replace function app.guard_guarantees(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; c public.contracts%rowtype; v_sum numeric;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into c from public.contracts where project_id = v_pid;
  if not found then
    return next ('NO_CONTRACT','Δεν έχει καταχωρηθεί σύμβαση για το έργο.','hard','N4412/135')::app.blocker;
    return;
  end if;

  select coalesce(sum(g.current_amount),0) into v_sum
  from public.guarantees g
  where g.project_id = v_pid
    and g.gtype in ('kalis_ektelesis','prosthetti')
    and g.status in ('energi','meiomeni_70');

  if v_sum = 0 then
    return next ('GUAR_MISSING',
      'Δεν έχει καταχωρηθεί ενεργή εγγυητική επιστολή καλής εκτέλεσης.',
      'hard','N4412/72/4')::app.blocker;
  elsif v_sum < c.estimated_guarantee_base * 0.05 - 0.01 then
    return next ('GUAR_UNDER_5PCT',
      format('Η κατατεθειμένη εγγύηση (%s €) υπολείπεται του 5%% της εκτιμώμενης αξίας.',
             to_char(v_sum,'FM999G999G990D00')),
      'hard','N4412/72/4')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.2 GUARD: Χρονοδιάγραμμα (άρθρο 145)
-- ---------------------------------------------------------------------
create or replace function app.guard_schedule(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; s public.schedules%rowtype; c public.contracts%rowtype;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into c from public.contracts where project_id = v_pid;
  select * into s from public.schedules
   where project_id = v_pid order by version_no desc limit 1;

  if not found then
    return next ('SCHED_MISSING',
      'Δεν έχει υποβληθεί χρονοδιάγραμμα κατασκευής.','hard','N4412/145/1')::app.blocker;
    return;
  end if;

  if s.submitted_at is null then
    return next ('SCHED_NOT_SUBMITTED',
      'Το χρονοδιάγραμμα δεν έχει υποβληθεί από τον ανάδοχο.','hard','N4412/145/1')::app.blocker;
  elsif c.signed_at is not null and s.submitted_at > c.signed_at + 30 then
    return next ('SCHED_LATE',
      format('Εκπρόθεσμη υποβολή χρονοδιαγράμματος (%s) — η προθεσμία δεν μπορεί να υπερβαίνει τις 30 ημέρες από την υπογραφή.',
             to_char(s.submitted_at,'DD/MM/YYYY')),
      'soft','N4412/145/2')::app.blocker;
  end if;

  if s.approved_at is null and not s.deemed_approved then
    if s.approval_due is not null and current_date > s.approval_due then
      return next ('SCHED_TACIT',
        'Παρήλθε η 15ήμερη προθεσμία έγκρισης: το χρονοδιάγραμμα ΤΕΚΜΑΙΡΕΤΑΙ ΕΓΚΕΚΡΙΜΕΝΟ. Καταχωρίστε τη σιωπηρή έγκριση.',
        'hard','N4412/145/2')::app.blocker;
    else
      return next ('SCHED_PENDING',
        'Εκκρεμεί η έγκριση του χρονοδιαγράμματος από τη Διευθύνουσα Υπηρεσία (προθεσμία 15 ημερών).',
        'hard','N4412/145/2')::app.blocker;
    end if;
  end if;

  if c.initial_value_net > 1000000 and s.method <> 'diktyoti_analysi' then
    return next ('SCHED_METHOD',
      'Για έργα άνω του 1.000.000 € η μέθοδος δικτυωτής ανάλυσης είναι ΥΠΟΧΡΕΩΤΙΚΗ.',
      'hard','N4412/145/3')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.3 GUARD: Ημερολόγιο (άρθρο 146)
-- ---------------------------------------------------------------------
create or replace function app.guard_diary(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; v_missing integer; v_unreviewed integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;

  select count(*) into v_missing from public.v_diary_missing_days d where d.project_id = v_pid;
  if v_missing > 0 then
    return next ('DIARY_MISSING',
      format('Λείπουν %s ημέρες ημερολογίου. Η παράλειψη επισύρει ειδική ποινική ρήτρα 100-500 € ανά ημέρα.',
             v_missing),
      'hard','N4412/146')::app.blocker;
  end if;

  select count(*) into v_unreviewed
  from public.diary_entries e
  where e.project_id = v_pid
    and e.status = 'submitted'
    and e.submitted_at < now() - interval '2 days';
  if v_unreviewed > 0 then
    return next ('DIARY_UNREVIEWED',
      format('%s εγγραφές ημερολογίου δεν ελέγχθηκαν από τον επιβλέποντα εντός δύο (2) εργασίμων ημερών.',
             v_unreviewed),
      'soft','N4412/146')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.4 GUARD: Αφανείς εργασίες (άρθρο 151 §7)
-- ---------------------------------------------------------------------
create or replace function app.guard_hidden_works(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; v_overdue integer; v_covered integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;

  select count(*) into v_overdue
  from public.hidden_work_notices h
  where h.project_id = v_pid and h.inspected_at is null and h.inspection_due < current_date;
  if v_overdue > 0 then
    return next ('HW_OVERDUE',
      format('%s δηλώσεις αφανών εργασιών δεν ελέγχθηκαν εντός της 3ήμερης προθεσμίας — ΥΠΕΡΗΜΕΡΙΑ ΚΥΡΙΟΥ ΤΟΥ ΕΡΓΟΥ.',
             v_overdue),
      'hard','N4412/151/7')::app.blocker;
  end if;

  select count(*) into v_covered
  from public.hidden_work_notices h
  where h.project_id = v_pid and h.covered_at is not null and h.inspected_at is null;
  if v_covered > 0 then
    return next ('HW_COVERED_UNCHECKED',
      format('%s αφανείς εργασίες επικαλύφθηκαν χωρίς προηγούμενο έλεγχο του επιβλέποντος.',
             v_covered),
      'hard','N4412/151/7')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.5 GUARD: Επιμετρήσεις — δειγματοληψία 40% (άρθρο 151 §3)
-- ---------------------------------------------------------------------
create or replace function app.guard_measurements(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; v_required integer; v_done integer; v_overdue integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;

  v_required := public.required_audit_count(v_pid);
  select count(distinct ma.measurement_id) into v_done
  from public.measurement_audits ma
  join public.measurements m on m.id = ma.measurement_id
  where m.project_id = v_pid and ma.performed_at is not null;

  if v_done < v_required then
    return next ('MEAS_AUDIT_SHORTFALL',
      format('Ο υποχρεωτικός δειγματοληπτικός έλεγχος δεν καλύφθηκε: απαιτούνται %s, διενεργήθηκαν %s.',
             v_required, v_done),
      'hard','N4412/151/3')::app.blocker;
  end if;

  select count(*) into v_overdue
  from public.measurements m
  where m.project_id = v_pid
    and m.status not in ('approved','deemed_approved','rejected')
    and m.approval_due is not null and m.approval_due < current_date;
  if v_overdue > 0 then
    return next ('MEAS_OVERDUE',
      format('%s επιμετρήσεις εκκρεμούν πέραν της 30ήμερης προθεσμίας εγκριτικής πράξης.', v_overdue),
      'soft','N4412/151/7')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.6 GUARD: Ανακεφαλαιωτικοί Πίνακες
-- ---------------------------------------------------------------------
create or replace function app.guard_ape_stage(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; r record;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  for r in select id, serial_no from public.ape
           where project_id = v_pid and status <> 'approved' loop
    return query
      select 'APE' || r.serial_no || '_' || b.code, format('%sος ΑΠΕ: %s', r.serial_no, b.message),
             b.severity, b.legal_ref
      from app.ape_validation(r.id) b;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 11.7 GUARD: Βεβαίωση Περάτωσης (άρθρο 168)
-- ---------------------------------------------------------------------
create or replace function app.guard_completion(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; cm public.completions%rowtype; v_defects integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into cm from public.completions where project_id = v_pid;

  if not found or cm.supervisor_report_at is null then
    return next ('COMP_NO_REPORT',
      'Δεν έχει συνταχθεί η έγγραφη αναφορά του επιβλέποντος περί περαίωσης (προθεσμία 30 ημερών από τη λήξη του εγκεκριμένου χρόνου).',
      'hard','N4412/168/1')::app.blocker;
    return;
  end if;

  if not cm.tests_completed then
    return next ('COMP_NO_TESTS',
      'Δεν βεβαιώνεται η ολοκλήρωση των προβλεπόμενων από τη σύμβαση δοκιμών.',
      'hard','N4412/168/1')::app.blocker;
  end if;

  select count(*) into v_defects from public.defects d
  where d.project_id = v_pid and d.source = 'peraiosi' and d.remedied_at is null;
  if v_defects > 0 then
    if cm.defects_severity = 'ousiodes' then
      return next ('COMP_MAJOR_DEFECTS',
        'Υφίστανται ΟΥΣΙΩΔΗ ελαττώματα: εφαρμόζονται τα άρθρα 159 και 160 (ακαταλληλότητα/έκπτωση) και δεν εκδίδεται Βεβαίωση Περάτωσης.',
        'hard','N4412/168/4')::app.blocker;
    else
      return next ('COMP_MINOR_DEFECTS',
        format('Εκκρεμεί η αποκατάσταση %s επουσιωδών ελαττωμάτων εντός της ταχθείσας προθεσμίας.', v_defects),
        'hard','N4412/168/3')::app.blocker;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.8 GUARD + TRIGGER: ΜΕΙΩΣΗ ΕΓΓΥΗΣΕΩΝ (άρθρο 72 §14 περ. β΄)
--      Η μείωση 70% προϋποθέτει ΕΓΚΕΚΡΙΜΕΝΗ ΤΕΛΙΚΗ ΕΠΙΜΕΤΡΗΣΗ.
--      Η ολική αποδέσμευση προϋποθέτει ΠΑΡΑΛΑΒΗ + ΤΕΛΙΚΟ ΛΟΓΑΡΙΑΣΜΟ.
-- ---------------------------------------------------------------------
create or replace function app.guard_guarantee_event()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_pid uuid; g public.guarantees%rowtype;
begin
  select * into g from public.guarantees where id = new.guarantee_id;
  v_pid := g.project_id;

  if new.event_type = 'meiosi_70' then
    if not exists (select 1 from public.final_measurement fm
                   where fm.project_id = v_pid and fm.approved_at is not null) then
      raise exception
        'ΑΠΑΓΟΡΕΥΕΤΑΙ η μείωση της εγγύησης κατά 70%%: δεν υπάρχει ΕΓΚΕΚΡΙΜΕΝΗ ΤΕΛΙΚΗ ΕΠΙΜΕΤΡΗΣΗ (άρθρο 72 §14 περ. β΄ σε συνδυασμό με άρθρο 151 §9 ν.4412/2016).'
        using errcode = 'check_violation';
    end if;
    if abs(new.amount_after - new.amount_before * 0.30) > 0.05 then
      raise exception
        'Η μείωση πρέπει να ανέρχεται σε 70%% της εγγύησης: αναμενόμενο υπόλοιπο %s €.',
        to_char(new.amount_before * 0.30,'FM999G999G990D00')
        using errcode = 'check_violation';
    end if;
  end if;

  if new.event_type = 'apodesmevsi' then
    if not exists (select 1 from public.acceptances a
                   where a.project_id = v_pid
                     and a.status in ('completed','auto_completed')
                     and a.approved_at is not null) then
      raise exception
        'ΑΠΑΓΟΡΕΥΕΤΑΙ η επιστροφή της εγγύησης: δεν έχει εγκριθεί το πρωτόκολλο παραλαβής (άρθρα 72 §14, 172 ν.4412/2016).'
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.payment_certificates pc
                   where pc.project_id = v_pid and pc.ptype = 'telikos'
                     and pc.status in ('approved','deemed_approved','paid')) then
      raise exception
        'ΑΠΑΓΟΡΕΥΕΤΑΙ η επιστροφή της εγγύησης: δεν έχει εγκριθεί ο ΤΕΛΙΚΟΣ ΛΟΓΑΡΙΑΣΜΟΣ (άρθρα 72 §14, 152 ν.4412/2016).'
        using errcode = 'check_violation';
    end if;
  end if;

  update public.guarantees
     set current_amount = new.amount_after,
         status = case new.event_type
                    when 'meiosi_70'   then 'meiomeni_70'::public.guarantee_status
                    when 'apodesmevsi' then 'apodesmevmeni'::public.guarantee_status
                    when 'katapt'      then 'katapiptousa'::public.guarantee_status
                    else status end
   where id = new.guarantee_id;

  return new;
end $$;

create trigger trg_guard_guarantee_event
  before insert on public.guarantee_events
  for each row execute function app.guard_guarantee_event();

create or replace function app.guard_guarantee_reduction(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  if not exists (select 1 from public.final_measurement fm
                 where fm.project_id = v_pid and fm.approved_at is not null) then
    return next ('GUAR_RED_NO_FINAL',
      'Η μείωση της εγγύησης κατά 70% προϋποθέτει εγκεκριμένη τελική επιμέτρηση.',
      'hard','N4412/72/14b')::app.blocker;
  end if;
  if not exists (select 1 from public.guarantee_events ge
                 join public.guarantees g on g.id = ge.guarantee_id
                 where g.project_id = v_pid and ge.event_type = 'meiosi_70') then
    return next ('GUAR_RED_NOT_DONE',
      'Δεν έχει καταχωρηθεί η πράξη μείωσης της εγγύησης καλής εκτέλεσης κατά 70%.',
      'hard','N4412/72/14b')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.9 GUARD: Παραλαβή (άρθρο 172)
-- ---------------------------------------------------------------------
create or replace function app.guard_acceptance(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; a public.acceptances%rowtype; v_members integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into a from public.acceptances where project_id = v_pid;

  if not found then
    return next ('ACC_NOT_OPEN','Δεν έχει ανοίξει διαδικασία παραλαβής.','hard','N4412/172')::app.blocker;
    return;
  end if;

  if a.committee_id is null then
    return next ('ACC_NO_COMMITTEE',
      'Δεν έχει οριστεί επιτροπή παραλαβής (ορίζεται τουλάχιστον 3 μήνες πριν τη λήξη του χρόνου υποχρεωτικής συντήρησης).',
      'hard','N4412/172')::app.blocker;
  else
    select count(*) into v_members from public.committee_members cm
    where cm.committee_id = a.committee_id and not cm.is_observer;
    if v_members < 5 then
      return next ('ACC_COMMITTEE_SIZE',
        format('Η επιτροπή παραλαβής έχει %s μέλη — απαιτείται πενταμελής σύνθεση με δύο εκπροσώπους ΤΕΕ/ΓΕΩΤΕΕ.', v_members),
        'hard','N4412/172')::app.blocker;
    end if;
  end if;

  if current_date > a.deadline_3m and a.protocol_date is null then
    return next ('ACC_AUTO',
      'Παρήλθε η τρίμηνη προθεσμία: η παραλαβή θεωρείται ΑΥΤΟΔΙΚΑΙΩΣ ΣΥΝΤΕΛΕΣΜΕΝΗ — απαιτείται βεβαιωτική πράξη.',
      'hard','N4412/172')::app.blocker;
  end if;

  if not (a.maintenance_manual and a.operation_manual and a.digital_archive) then
    return next ('ACC_DELIVERABLES',
      'Εκκρεμούν παραδοτέα αναδόχου: προϋπολογισμός/οδηγίες συντήρησης, εγχειρίδιο λειτουργίας, ψηφιακή τεκμηρίωση σταδίων κατασκευής.',
      'soft','N4412/172')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.10 ΟΨΕΙΣ ΠΑΡΑΚΟΛΟΥΘΗΣΗΣ
-- ---------------------------------------------------------------------

-- Ημέρες χωρίς εγγραφή ημερολογίου
create or replace view public.v_diary_missing_days as
with span as (
  select c.project_id,
         greatest(c.signed_at, coalesce(c.works_start_deadline, c.signed_at)) as from_d,
         least(current_date,
               coalesce((select cm.actual_completion_date from public.completions cm
                         where cm.project_id = c.project_id), current_date)) as to_d,
         c.diary_mode
  from public.contracts c
  where c.status = 'active' and c.diary_mode = 'imerisio'
)
select s.project_id, d::date as missing_date
from span s
cross join lateral generate_series(s.from_d, s.to_d, interval '1 day') g(d)
where extract(isodow from d) < 6                      -- Εργάσιμες (παραμετροποιήσιμο)
  and not exists (select 1 from public.diary_entries e
                  where e.project_id = s.project_id and e.entry_date = d::date);

comment on view public.v_diary_missing_days is
  'Ημέρες χωρίς εγγραφή ημερολογίου. Κάθε ημέρα γεννά ειδική ποινική ρήτρα '
  '100-500 € (άρθρο 146 ν.4412/2016).';

-- Οικονομική εικόνα έργου
create or replace view public.v_project_financials as
select p.id                            as project_id,
       p.code,
       p.title,
       c.initial_value_net,
       c.contingency_amount,
       c.contingency_pct,
       coalesce(ape.approved_delta, 0)                          as ape_delta,
       c.initial_value_net + coalesce(ape.approved_delta,0)     as current_value_net,
       round(coalesce(ape.approved_delta,0)
             / nullif(c.initial_value_net,0) * 100, 2)          as ape_delta_pct,
       round(c.initial_value_net * 0.50, 2)                     as limit_50pct,
       round(c.initial_value_net * 0.10, 2)                     as limit_savings_10pct,
       coalesce(pay.certified, 0)                               as certified_total,
       coalesce(pay.paid, 0)                                    as paid_total,
       round(coalesce(pay.certified,0)
             / nullif(c.initial_value_net + coalesce(ape.approved_delta,0),0) * 100, 2)
                                                                as financial_progress_pct,
       coalesce(adv.advance, 0)                                 as advance_total,
       coalesce(adv.advance,0) - coalesce(adv.amortized,0)      as advance_outstanding,
       coalesce(pen.total, 0)                                   as penalties_total,
       coalesce(gua.active_guarantees, 0)                       as guarantees_active,
       c.original_end_date,
       c.current_end_date,
       (c.current_end_date - current_date)                      as days_to_deadline
from public.projects p
join public.contracts c on c.project_id = p.id
left join lateral (
    select sum(a.delta_amount) as approved_delta
    from public.ape a where a.project_id = p.id and a.status = 'approved') ape on true
left join lateral (
    select sum(pc.gross_cumulative) filter (where pc.serial_no = (
             select max(x.serial_no) from public.payment_certificates x
             where x.project_id = p.id and x.ptype = 'tmimatikos')) as certified,
           sum(pc.net_payable) filter (where pc.paid_at is not null) as paid
    from public.payment_certificates pc where pc.project_id = p.id) pay on true
left join lateral (
    select sum(a.amount) as advance, sum(a.amortized_amount) as amortized
    from public.advances a where a.project_id = p.id) adv on true
left join lateral (
    select sum(x.amount) as total from public.penalties x
    where x.project_id = p.id and not x.waived) pen on true
left join lateral (
    select sum(g.current_amount) as active_guarantees from public.guarantees g
    where g.project_id = p.id and g.status in ('energi','meiomeni_70')) gua on true;

comment on view public.v_project_financials is
  'Συγκεντρωτική οικονομική εξέλιξη ανά έργο, με τα όρια ελέγχου του άρθρου 156.';

-- Πίνακας προθεσμιών (deadline radar)
create or replace view public.v_deadline_watch as
select ps.project_id, p.code as project_code, p.title as project_title,
       ws.code as stage_code, ws.title as stage_title,
       app.party_label(ws.responsible) as responsible,
       ps.status, ps.due_date,
       (ps.due_date - current_date) as days_left,
       case
         when ps.status in ('completed','not_applicable') then 'ok'
         when ps.due_date is null                          then 'no_deadline'
         when ps.due_date < current_date                   then 'overdue'
         when ps.due_date - current_date <= 5              then 'critical'
         when ps.due_date - current_date <= 15             then 'warning'
         else 'ok'
       end as alert_level,
       ws.legal_ref_id,
       ws.tacit_approval, ws.tacit_effect
from public.project_stages ps
join public.workflow_stages ws on ws.code = ps.stage_code
join public.projects p on p.id = ps.project_id
where ps.status not in ('completed','not_applicable');

-- Πίνακας ελέγχου σταδίων με τα εμπόδια
create or replace view public.v_stage_board as
select ps.id as project_stage_id, ps.project_id, ps.stage_code, ps.cycle_no,
       ws.ordinal, ws.phase, ws.title, ws.purpose,
       app.party_label(ws.responsible) as responsible,
       app.party_label(ws.approver)    as approver,
       ws.legal_ref_id, ws.risk_note, ws.recurrence,
       ps.status, ps.due_date, ps.completed_at,
       (select count(*) from app.stage_blockers(ps.id) b where b.severity='hard') as hard_blockers,
       (select count(*) from app.stage_blockers(ps.id) b where b.severity='soft') as soft_blockers,
       (select count(*) from public.project_stage_tasks t where t.project_stage_id = ps.id) as tasks_total,
       (select count(*) from public.project_stage_tasks t
         where t.project_stage_id = ps.id and (t.is_done or t.waived))                    as tasks_done
from public.project_stages ps
join public.workflow_stages ws on ws.code = ps.stage_code;

-- Εκκρεμείς αφανείς εργασίες
create or replace view public.v_hidden_works_alerts as
select h.project_id, h.serial_no, h.work_description, h.invitation_sent_at,
       h.inspection_due, h.inspected_at, h.photos_count, h.approval_due, h.approved_at,
       case
         when h.inspected_at is null and h.inspection_due < current_date then 'ΥΠΕΡΗΜΕΡΙΑ ΚΥΡΙΟΥ ΕΡΓΟΥ'
         when h.inspected_at is null                                     then 'ΕΚΚΡΕΜΕΙ ΕΛΕΓΧΟΣ'
         when h.photos_count = 0                                         then 'ΛΕΙΠΕΙ ΦΩΤΟΓΡΑΦΙΚΗ ΤΕΚΜΗΡΙΩΣΗ'
         when h.approved_at is null and h.approval_due < current_date    then 'ΕΚΠΡΟΘΕΣΜΗ ΕΓΚΡΙΤΙΚΗ ΠΡΑΞΗ'
         else 'ΟΚ'
       end as alert
from public.hidden_work_notices h;

-- Έλεγχος ορίων ΑΠΕ ανά έργο
create or replace view public.v_ape_limits as
select a.project_id, a.id as ape_id, a.serial_no, a.atype, a.status,
       a.delta_amount, c.initial_value_net,
       round(a.delta_amount / nullif(c.initial_value_net,0) * 100, 2) as delta_pct,
       a.contingency_used, c.contingency_amount,
       (select count(*) from app.ape_validation(a.id) b where b.severity='hard') as violations
from public.ape a
join public.contracts c on c.project_id = a.project_id;

-- >>>>>>>>>>>>>>>>>>>> 0012_rls_security.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0012 : Ασφάλεια — Row Level Security & διαχωρισμός ρόλων
--
-- Αρχή: κάθε χρήστης βλέπει μόνο τα έργα στα οποία έχει ρητή ανάθεση,
-- και γράφει μόνο ό,τι του επιτρέπει ο ρόλος του κατά τον ν.4412/2016.
-- Ο ΑΝΑΔΟΧΟΣ έχει «θυρίδα υποβολής»: καταχωρεί τα δικά του, δεν βλέπει
-- εσωτερικά έγγραφα της Υπηρεσίας και δεν τροποποιεί ό,τι έχει υποβάλει.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 12.1 ΒΟΗΘΗΤΙΚΕΣ ΣΥΝΑΡΤΗΣΕΙΣ ΤΑΥΤΟΤΗΤΑΣ
-- ---------------------------------------------------------------------
create or replace function app.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
    nullif((nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub'), '')::uuid
  );
$$;

-- Σύνδεση χρηστών-αναδόχων με την επιχείρησή τους
create table public.contractor_users (
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  contractor_id  uuid not null references public.contractors(id) on delete cascade,
  is_legal_rep   boolean not null default false,
  created_at     timestamptz not null default now(),
  primary key (profile_id, contractor_id)
);

create or replace function app.my_org() returns uuid
language sql stable security definer set search_path = public, app as $$
  select org_id from public.profiles where id = app.uid();
$$;

create or replace function app.is_admin() returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (select 1 from public.org_roles r
                 where r.profile_id = app.uid()
                   and r.role in ('admin')
                   and (r.valid_to is null or r.valid_to >= current_date));
$$;

-- Καθολικοί ρόλοι υπηρεσίας (βλέπουν όλα τα έργα του φορέα)
create or replace function app.is_service_wide() returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (select 1 from public.org_roles r
                 where r.profile_id = app.uid()
                   and r.role in ('admin','proistamenos_dy','proistameni_arxi','techniko_symvoulio')
                   and (r.valid_to is null or r.valid_to >= current_date));
$$;

create or replace function app.has_project_role(p_project uuid, p_roles public.role_type[])
returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (
    select 1
    from public.project_assignments pa
    where pa.project_id = p_project
      and pa.valid_to is null
      and pa.role = any(p_roles)
      and (
        pa.profile_id = app.uid()
        or pa.contractor_id in (select cu.contractor_id
                                from public.contractor_users cu
                                where cu.profile_id = app.uid())
      )
  );
$$;

create or replace function app.is_contractor_of(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (
    select 1 from public.contracts c
    join public.contractor_users cu on cu.contractor_id = c.contractor_id
    where c.project_id = p_project and cu.profile_id = app.uid()
  );
$$;

create or replace function app.can_read_project(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select app.is_admin()
      or (app.is_service_wide()
          and exists (select 1 from public.projects p
                      where p.id = p_project and p.org_id = app.my_org()))
      or app.has_project_role(p_project, array[
           'epivlepon','voithos_epivlepon','syntonistis','ife',
           'epitropi_paralavis','epitropi_timon','theatis',
           'proistamenos_dy','proistameni_arxi']::public.role_type[])
      or app.is_contractor_of(p_project);
$$;

create or replace function app.can_supervise(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select app.is_admin()
      or (app.is_service_wide()
          and exists (select 1 from public.projects p
                      where p.id = p_project and p.org_id = app.my_org()))
      or app.has_project_role(p_project,
           array['epivlepon','voithos_epivlepon','syntonistis','ife']::public.role_type[]);
$$;

create or replace function app.can_approve(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select app.is_admin()
      or app.has_project_role(p_project,
           array['proistamenos_dy','proistameni_arxi']::public.role_type[])
      or (app.is_service_wide()
          and exists (select 1 from public.projects p
                      where p.id = p_project and p.org_id = app.my_org()));
$$;

-- ---------------------------------------------------------------------
-- 12.2 ΠΙΝΑΚΑΣ ΔΙΚΑΙΩΜΑΤΩΝ (τεκμηριώνει τον διαχωρισμό ρόλων)
-- ---------------------------------------------------------------------
create table app.table_access (
  table_name        text primary key,
  contractor_reads  boolean not null default false,
  contractor_writes boolean not null default false,  -- Δικαίωμα υποβολής (INSERT)
  contractor_update text not null default 'none',    -- none | draft_only | full
  supervisor_writes boolean not null default true,
  approver_only     boolean not null default false,  -- Γράφει μόνο ο Προϊστάμενος Δ.Υ.
  note              text,
  constraint ta_upd_chk check (contractor_update in ('none','draft_only','full'))
);

insert into app.table_access
  (table_name, contractor_reads, contractor_writes, contractor_update,
   supervisor_writes, approver_only, note) values
  ('project_stages',        true,  false, 'none',       true,  false, 'Ροή ελέγχου — ο ανάδοχος βλέπει μόνο την πρόοδο'),
  ('project_stage_tasks',   false, false, 'none',       true,  false, 'Εσωτερική λίστα ελέγχου της Υπηρεσίας'),
  ('documents',             true,  true,  'draft_only', true,  false, 'Ο ανάδοχος βλέπει μόνο κοινοποιημένα ή δικά του'),
  ('schedules',             true,  true,  'draft_only', true,  false, 'Άρθρο 145: υποβολή αναδόχου, έγκριση Δ.Υ.'),
  ('schedule_activities',   true,  true,  'full',       true,  false, 'Λεπτομέρειες χρονοδιαγράμματος'),
  ('schedule_periods',      true,  true,  'full',       true,  false, null),
  ('site_organograms',      true,  true,  'full',       true,  false, 'Άρθρο 145 §4'),
  ('diary_entries',         true,  true,  'draft_only', true,  false, 'Άρθρο 146: τηρεί ο ανάδοχος, ελέγχει ο επιβλέπων'),
  ('contractor_staff',      true,  true,  'full',       true,  false, 'Άρθρο 139'),
  ('measurements',          true,  true,  'draft_only', true,  false, 'Άρθρο 151: υποβάλλει ο ανάδοχος με δήλωση αληθείας'),
  ('measurement_lines',     true,  true,  'full',       true,  false, 'Κλειδώνουν μέσω της κατάστασης της επιμέτρησης'),
  ('measurement_audits',    false, false, 'none',       true,  false, 'Δειγματοληπτικός έλεγχος — αμιγώς υπηρεσιακό'),
  ('hidden_work_notices',   true,  true,  'draft_only', true,  false, 'Άρθρο 151 §7'),
  ('hidden_work_photos',    true,  true,  'full',       true,  false, null),
  ('final_measurement',     true,  true,  'draft_only', true,  false, 'Άρθρο 151 §9'),
  ('payment_certificates',  true,  true,  'draft_only', true,  false, 'Άρθρο 152'),
  ('payment_certificate_lines', true, true, 'full',     true,  false, null),
  ('ape',                   true,  false, 'none',       true,  false, 'Άρθρο 156: συντάσσει η υπηρεσία, υπογράφει ο ανάδοχος'),
  ('ape_lines',             true,  false, 'none',       true,  false, null),
  ('new_price_protocols',   true,  false, 'none',       true,  false, 'Άρθρο 156 §5'),
  ('new_price_items',       true,  false, 'none',       true,  false, null),
  ('budget_versions',       true,  false, 'none',       true,  false, null),
  ('budget_items',          true,  false, 'none',       true,  false, null),
  ('guarantees',            true,  false, 'none',       true,  false, 'Άρθρο 72'),
  ('advances',              true,  true,  'draft_only', true,  false, 'Άρθρο 150'),
  ('time_extensions',       true,  true,  'draft_only', true,  false, 'Άρθρο 147: αίτημα αναδόχου'),
  ('suspensions',           true,  true,  'draft_only', true,  false, 'Άρθρο 147 §7'),
  ('penalties',             true,  false, 'none',       false, true,  'Επιβάλλονται από τη Δ.Υ.'),
  ('bonus_clauses',         true,  false, 'none',       false, true,  'Άρθρο 149'),
  ('objections',            true,  true,  'draft_only', false, false, 'Άρθρο 174: ένσταση αναδόχου'),
  ('technical_council_opinions', true, false, 'none',   false, true,  null),
  ('quality_plans',         true,  true,  'draft_only', true,  false, 'Άρθρο 158'),
  ('material_approvals',    true,  true,  'draft_only', true,  false, 'Άρθρο 138 §12'),
  ('lab_tests',             true,  true,  'full',       true,  false, null),
  ('site_inspections',      true,  false, 'none',       true,  false, 'Άρθρο 136 §11'),
  ('quarterly_reports',     true,  true,  'draft_only', true,  false, 'Άρθρο 136 §10 / 138 §17'),
  ('completions',           true,  false, 'none',       true,  false, 'Άρθρο 168'),
  ('defects',               true,  false, 'none',       true,  false, null),
  ('maintenance_periods',   true,  false, 'none',       true,  false, 'Άρθρο 171'),
  ('committees',            true,  false, 'none',       false, true,  'Άρθρο 172'),
  ('acceptances',           true,  false, 'none',       true,  false, 'Άρθρο 172'),
  ('apologistika',          true,  false, 'none',       true,  false, 'Άρθρα 154-155'),
  ('contract_deadlines',    true,  false, 'none',       true,  false, 'Άρθρο 147'),
  ('project_assignments',   true,  false, 'none',       false, true,  'Άρθρο 136 — ορίζει η Δ.Υ.');

comment on table app.table_access is
  'Μητρώο δικαιωμάτων ανά πίνακα. Αποτυπώνει τον ΔΙΑΧΩΡΙΣΜΟ ΡΟΛΩΝ του ν.4412/2016 '
  'και οδηγεί τη δημιουργία των πολιτικών RLS.';

-- ---------------------------------------------------------------------
-- 12.3 ΑΥΤΟΜΑΤΗ ΠΑΡΑΓΩΓΗ ΠΟΛΙΤΙΚΩΝ ΓΙΑ ΠΙΝΑΚΕΣ ΜΕ project_id
-- ---------------------------------------------------------------------
do $$
declare
  t          record;
  v_read     text;
  v_service  text;
  v_insert   text;
  v_update   text;
  v_lock     text;
  v_cand     text;
begin
  for t in select * from app.table_access loop
    -- Ο πίνακας πρέπει να υπάρχει και να έχει στήλη project_id
    if not exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=t.table_name
                     and column_name='project_id') then
      continue;
    end if;

    execute format('alter table public.%I enable row level security', t.table_name);

    v_read := case when t.contractor_reads
                   then 'app.can_read_project(project_id)'
                   else '(app.can_supervise(project_id) or app.can_approve(project_id))' end;

    -- Δικαίωμα γραφής της Υπηρεσίας
    v_service := case
                   when t.approver_only     then 'app.can_approve(project_id)'
                   when t.supervisor_writes then '(app.can_supervise(project_id) or app.can_approve(project_id))'
                   else 'app.can_approve(project_id)' end;

    v_insert := v_service;
    if t.contractor_writes then
      v_insert := v_insert || ' or app.is_contractor_of(project_id)';
    end if;

    v_update := v_service;
    if t.contractor_update = 'full' then
      v_update := v_update || ' or app.is_contractor_of(project_id)';
    end if;

    execute format('create policy %I on public.%I for select using (%s)',
                   t.table_name || '_sel', t.table_name, v_read);
    execute format('create policy %I on public.%I for insert with check (%s)',
                   t.table_name || '_ins', t.table_name, v_insert);
    execute format('create policy %I on public.%I for update using (%s) with check (%s)',
                   t.table_name || '_upd', t.table_name, v_update, v_update);
    execute format('create policy %I on public.%I for delete using (app.is_admin())',
                   t.table_name || '_del', t.table_name);

    -- Ο ανάδοχος διορθώνει ΜΟΝΟ όσο η εγγραφή είναι σε κατάσταση 'draft'.
    -- Μετά την υποβολή, το περιεχόμενο κλειδώνει (ιχνηλασιμότητα υποβολών).
    if t.contractor_update = 'draft_only' then
      v_lock := null;
      foreach v_cand in array array['status','submitted_at','filed_at',
                                    'decided_at','approved_at','requested_at'] loop
        if exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=t.table_name
                     and column_name=v_cand) then
          v_lock := v_cand;
          exit;
        end if;
      end loop;

      if v_lock = 'status' then
        execute format(
          'create policy %I on public.%I for update
             using (app.is_contractor_of(project_id) and status::text = %L)
             with check (app.is_contractor_of(project_id)
                         and status::text in (%L, %L))',
          t.table_name || '_contractor_upd', t.table_name, 'draft', 'draft', 'submitted');
      elsif v_lock is not null then
        execute format(
          'create policy %I on public.%I for update
             using (app.is_contractor_of(project_id) and %I is null)
             with check (app.is_contractor_of(project_id))',
          t.table_name || '_contractor_upd', t.table_name, v_lock);
      end if;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 12.4 ΕΙΔΙΚΕΣ ΠΟΛΙΤΙΚΕΣ
-- ---------------------------------------------------------------------

-- Έργα & συμβάσεις
alter table public.projects  enable row level security;
alter table public.contracts enable row level security;

create policy projects_sel on public.projects for select
  using (app.can_read_project(id));
create policy projects_ins on public.projects for insert
  with check (app.is_service_wide() and org_id = app.my_org());
create policy projects_upd on public.projects for update
  using (app.can_approve(id) or app.can_supervise(id))
  with check (app.can_approve(id) or app.can_supervise(id));
create policy projects_del on public.projects for delete using (app.is_admin());

create policy contracts_sel on public.contracts for select
  using (app.can_read_project(project_id));
create policy contracts_ins on public.contracts for insert
  with check (app.can_approve(project_id) or app.can_supervise(project_id));
create policy contracts_upd on public.contracts for update
  using (app.can_approve(project_id)) with check (app.can_approve(project_id));

comment on policy contracts_upd on public.contracts is
  'Η τροποποίηση των στοιχείων σύμβασης (ποσά, προθεσμίες) ανήκει στον '
  'Προϊστάμενο της Διευθύνουσας Υπηρεσίας, όχι στον επιβλέποντα.';

-- Έγγραφα: ο ανάδοχος βλέπει μόνο όσα του έχουν κοινοποιηθεί ή υπέβαλε ο ίδιος
drop policy if exists documents_sel on public.documents;
create policy documents_sel on public.documents for select
  using (
    app.can_supervise(project_id) or app.can_approve(project_id)
    or (app.is_contractor_of(project_id) and (
          status in ('communicated','approved','deemed_approved')
          or exists (select 1 from public.document_communications dc
                     where dc.document_id = documents.id
                       and dc.recipient_party = 'anadochos')
          or created_by = app.uid()))
  );

-- Προφίλ & φορείς
alter table public.profiles enable row level security;
create policy profiles_sel on public.profiles for select
  using (id = app.uid() or org_id = app.my_org());
create policy profiles_upd on public.profiles for update
  using (id = app.uid() or app.is_admin()) with check (id = app.uid() or app.is_admin());

alter table public.organizations enable row level security;
create policy organizations_sel on public.organizations for select
  using (id = app.my_org());
create policy organizations_upd on public.organizations for update
  using (app.is_admin()) with check (app.is_admin());

alter table public.contractors enable row level security;
create policy contractors_sel on public.contractors for select
  using (org_id = app.my_org()
         or id in (select contractor_id from public.contractor_users
                   where profile_id = app.uid()));
create policy contractors_ins on public.contractors for insert
  with check (app.is_service_wide() and org_id = app.my_org());
create policy contractors_upd on public.contractors for update
  using (app.is_service_wide() and org_id = app.my_org())
  with check (app.is_service_wide() and org_id = app.my_org());

alter table public.contractor_users enable row level security;
create policy contractor_users_sel on public.contractor_users for select
  using (profile_id = app.uid() or app.is_service_wide());
create policy contractor_users_mod on public.contractor_users for all
  using (app.is_admin()) with check (app.is_admin());

alter table public.org_roles enable row level security;
create policy org_roles_sel on public.org_roles for select
  using (profile_id = app.uid() or app.is_service_wide());
create policy org_roles_mod on public.org_roles for all
  using (app.is_admin()) with check (app.is_admin());

-- Θυγατρικοί πίνακες χωρίς project_id — κληρονομούν από τον γονέα
alter table public.committee_members enable row level security;
create policy committee_members_sel on public.committee_members for select
  using (exists (select 1 from public.committees c
                 where c.id = committee_id and app.can_read_project(c.project_id)));
create policy committee_members_mod on public.committee_members for all
  using (exists (select 1 from public.committees c
                 where c.id = committee_id and app.can_approve(c.project_id)))
  with check (exists (select 1 from public.committees c
                 where c.id = committee_id and app.can_approve(c.project_id)));

alter table public.document_signatures enable row level security;
create policy document_signatures_sel on public.document_signatures for select
  using (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_read_project(d.project_id)));
create policy document_signatures_ins on public.document_signatures for insert
  with check (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_read_project(d.project_id)));

alter table public.document_communications enable row level security;
create policy document_communications_sel on public.document_communications for select
  using (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_read_project(d.project_id)));
create policy document_communications_mod on public.document_communications for all
  using (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_supervise(d.project_id)))
  with check (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_supervise(d.project_id)));

alter table public.guarantee_events enable row level security;
create policy guarantee_events_sel on public.guarantee_events for select
  using (exists (select 1 from public.guarantees g
                 where g.id = guarantee_id and app.can_read_project(g.project_id)));
create policy guarantee_events_ins on public.guarantee_events for insert
  with check (exists (select 1 from public.guarantees g
                 where g.id = guarantee_id and app.can_approve(g.project_id)));

comment on policy guarantee_events_ins on public.guarantee_events is
  'Η μείωση/αποδέσμευση εγγύησης είναι πράξη της Διευθύνουσας Υπηρεσίας.';

-- ---------------------------------------------------------------------
-- 12.5 AUDIT LOG — μόνο ανάγνωση & προσθήκη, ποτέ μεταβολή/διαγραφή
-- ---------------------------------------------------------------------
alter table public.audit_log enable row level security;
create policy audit_sel on public.audit_log for select
  using (app.is_service_wide()
         or (project_id is not null and app.can_supervise(project_id)));
create policy audit_ins on public.audit_log for insert with check (true);
revoke update, delete on public.audit_log from public;

-- Κατάλογοι (ανάγνωση για όλους τους πιστοποιημένους χρήστες)
alter table public.legal_refs        enable row level security;
alter table public.work_groups       enable row level security;
alter table public.workflow_stages   enable row level security;
alter table public.stage_tasks       enable row level security;
alter table public.stage_prerequisites enable row level security;
alter table public.stage_documents   enable row level security;
alter table public.document_templates enable row level security;
alter table public.template_fields   enable row level security;

create policy legal_refs_sel  on public.legal_refs  for select using (true);
create policy work_groups_sel on public.work_groups for select using (true);
create policy stages_sel      on public.workflow_stages for select using (true);
create policy stage_tasks_sel on public.stage_tasks for select using (true);
create policy stage_prereq_sel on public.stage_prerequisites for select using (true);
create policy stage_docs_sel  on public.stage_documents for select using (true);
create policy templates_sel   on public.document_templates for select
  using (org_id is null or org_id = app.my_org());
create policy templates_mod   on public.document_templates for all
  using (app.is_service_wide() and org_id = app.my_org())
  with check (app.is_service_wide() and org_id = app.my_org());
create policy template_fields_sel on public.template_fields for select using (true);

-- ---------------------------------------------------------------------
-- 12.6 ΓΕΝΙΚΟΣ AUDIT TRIGGER
-- ---------------------------------------------------------------------
create or replace function app.audit_row()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_pid uuid;
begin
  begin
    v_pid := (coalesce(to_jsonb(new), to_jsonb(old)) ->> 'project_id')::uuid;
  exception when others then v_pid := null;
  end;

  insert into public.audit_log
    (actor_id, table_name, record_id, action, project_id, old_data, new_data)
  values (app.uid(), tg_table_name,
          coalesce((to_jsonb(new)->>'id'), (to_jsonb(old)->>'id')),
          lower(tg_op)::public.audit_action, v_pid,
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'contracts','project_stages','measurements','hidden_work_notices',
    'payment_certificates','ape','guarantees','guarantee_events',
    'completions','acceptances','time_extensions','penalties','objections',
    'final_measurement','documents']
  loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on public.%1$I
       for each row execute function app.audit_row()', t);
  end loop;
end $$;

-- >>>>>>>>>>>>>>>>>>>> 0013_seed_legal_workflow.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0013 : ΔΕΔΟΜΕΝΑ ΑΝΑΦΟΡΑΣ
--   (α) Μητρώο νομικών διατάξεων
--   (β) Ομάδες εργασιών ανά κατηγορία έργου
--   (γ) Ο ΟΔΗΓΟΣ: 35 στάδια επίβλεψης, προαπαιτούμενα, ενέργειες, έγγραφα
-- =====================================================================

-- ---------------------------------------------------------------------
-- 13.1 ΝΟΜΙΚΕΣ ΔΙΑΤΑΞΕΙΣ
-- ---------------------------------------------------------------------
insert into public.legal_refs (id, law, article, paragraph, title, fek, amended_by, in_force_from) values
('N4412/38',      'ν. 4412/2016','38',  null, 'Κ.Η.Μ.ΔΗ.Σ. — καταχώριση στοιχείων συμβάσεων','Α΄147/2016', '{"ν. 4782/2021"}','2016-08-08'),
('N4412/72/4',    'ν. 4412/2016','72',  '4',  'Εγγύηση καλής εκτέλεσης — 5% της εκτιμώμενης αξίας','Α΄147/2016','{"ν. 4782/2021 άρθρο 21"}','2021-03-09'),
('N4412/72/7',    'ν. 4412/2016','72',  '7',  'Εγγύηση προκαταβολής — ίση με το ποσό της προκαταβολής','Α΄147/2016','{"ν. 4782/2021 άρθρο 21"}','2021-03-09'),
('N4412/72/14b',  'ν. 4412/2016','72',  '14β','Μείωση εγγύησης καλής εκτέλεσης κατά 70% μετά την έγκριση της τελικής επιμέτρησης — ολική επιστροφή μετά την παραλαβή και τον τελικό λογαριασμό','Α΄147/2016','{"ν. 4782/2021 άρθρο 21"}','2021-03-09'),
('N4412/135',     'ν. 4412/2016','135', null, 'Υπογραφή σύμβασης','Α΄147/2016','{"ν. 4782/2021"}','2021-03-09'),
('N4412/136',     'ν. 4412/2016','136', null, 'Διοίκηση του έργου — Παρακολούθηση και επίβλεψη','Α΄147/2016','{"ν. 4782/2021 άρθρο 57"}','2021-03-09'),
('N4412/136/2',   'ν. 4412/2016','136', '2',  'Ορισμός επιβλεπόντων και βοηθών — ομάδα επίβλεψης με συντονιστή','Α΄147/2016','{"ν. 4782/2021 άρθρο 57"}','2021-03-09'),
('N4412/136/3',   'ν. 4412/2016','136', '3',  'Επίβλεψη από πιστοποιημένο Ιδιωτικό Φορέα Επίβλεψης (Ι.Φ.Ε.)','Α΄147/2016','{"ν. 4782/2021 άρθρο 57"}','2021-03-09'),
('N4412/136/5',   'ν. 4412/2016','136', '5',  'Επιτόπιοι έλεγχοι Δ.Υ. — εναντίωση σε πορίσματα Ι.Φ.Ε. εντός 15 ημερών','Α΄147/2016','{"ν. 4782/2021 άρθρο 57"}','2021-03-09'),
('N4412/136/8',   'ν. 4412/2016','136', '8',  'Κλιμάκιο επίβλεψης σε μεγάλα ή ειδικά έργα','Α΄147/2016',null,'2021-03-09'),
('N4412/136/10',  'ν. 4412/2016','136', '10', 'Τριμηνιαίες εκθέσεις πορείας — πειθαρχικό παράπτωμα η μη τήρηση','Α΄147/2016','{"ν. 4782/2021 άρθρο 57"}','2021-03-09'),
('N4412/136/11',  'ν. 4412/2016','136', '11', 'Αυτοψία — πρόσκληση αναδόχου τουλάχιστον 24 ώρες πριν','Α΄147/2016',null,'2021-03-09'),
('N4412/136A',    'ν. 4412/2016','136Α',null, 'Παρακολούθηση και επίβλεψη έργων κάτω των ορίων','Α΄147/2016','{"ν. 4782/2021"}','2021-03-09'),
('N4412/137',     'ν. 4412/2016','137', null, 'Υπερημερία του κυρίου του έργου','Α΄147/2016',null,'2021-03-09'),
('N4412/138',     'ν. 4412/2016','138', null, 'Γενικές υποχρεώσεις του αναδόχου','Α΄147/2016','{"ν. 4782/2021 άρθρο 59"}','2021-03-09'),
('N4412/138/2',   'ν. 4412/2016','138', '2',  'Έλεγχος της μελέτης από τον ανάδοχο (20-60 ημέρες)','Α΄147/2016','{"ν. 4782/2021 άρθρο 59"}','2021-03-09'),
('N4412/138/9',   'ν. 4412/2016','138', '9',  'Τήρηση εργατικής νομοθεσίας, πρόληψη ατυχημάτων, προστασία περιβάλλοντος','Α΄147/2016',null,'2021-03-09'),
('N4412/138/10',  'ν. 4412/2016','138', '10', 'Ελάχιστο τεχνικό προσωπικό ανά ειδικότητα','Α΄147/2016',null,'2021-03-09'),
('N4412/138/12',  'ν. 4412/2016','138', '12', 'Πηγές λήψης υλικών — έγκριση εντός 30 ημερών','Α΄147/2016',null,'2021-03-09'),
('N4412/138/14',  'ν. 4412/2016','138', '14', 'Αρχαιότητες — άμεση ειδοποίηση της Δ.Υ.','Α΄147/2016',null,'2021-03-09'),
('N4412/138/17',  'ν. 4412/2016','138', '17', 'Τριμηνιαία συνοπτική αναφορά προόδου από τον ανάδοχο','Α΄147/2016',null,'2021-03-09'),
('N4412/139',     'ν. 4412/2016','139', null, 'Διεύθυνση του έργου από την πλευρά του αναδόχου','Α΄147/2016','{"ν. 4782/2021 άρθρο 60"}','2021-03-09'),
('N4412/140',     'ν. 4412/2016','140', null, 'Υποχρεώσεις μελών αναδόχου κοινοπραξίας','Α΄147/2016',null,'2021-03-09'),
('N4412/141',     'ν. 4412/2016','141', null, 'Πειθαρχικές ευθύνες διοικητικών οργάνων','Α΄147/2016',null,'2021-03-09'),
('N4412/143',     'ν. 4412/2016','143', null, 'Κοινοποίηση στον ανάδοχο — εκπροσώπηση','Α΄147/2016',null,'2021-03-09'),
('N4412/144',     'ν. 4412/2016','144', null, 'Σύμπραξη του μελετητή στην κατασκευή','Α΄147/2016',null,'2021-03-09'),
('N4412/145/1',   'ν. 4412/2016','145', '1',  'Υποβολή χρονοδιαγράμματος εντός 15-30 ημερών από την υπογραφή','Α΄147/2016','{"ν. 4782/2021 άρθρο 65"}','2021-03-09'),
('N4412/145/2',   'ν. 4412/2016','145', '2',  'Έγκριση χρονοδιαγράμματος εντός 15 ημερών — τεκμήριο έγκρισης — έναρξη εργασιών εντός 30 ημερών','Α΄147/2016','{"ν. 4782/2021 άρθρο 65"}','2021-03-09'),
('N4412/145/3',   'ν. 4412/2016','145', '3',  'Περιεχόμενο — δικτυωτή ανάλυση υποχρεωτική άνω του 1.000.000 €','Α΄147/2016',null,'2021-03-09'),
('N4412/145/4',   'ν. 4412/2016','145', '4',  'Οργανόγραμμα εργοταξίου εντός ενός μηνός','Α΄147/2016',null,'2021-03-09'),
('N4412/146',     'ν. 4412/2016','146', null, 'Ημερολόγιο του έργου — ηλεκτρονική τήρηση, έλεγχος εντός 2 εργασίμων, ειδική ποινική ρήτρα 100-500 €/ημέρα','Α΄147/2016','{"ν. 4782/2021 άρθρο 66"}','2021-03-09'),
('N4412/147/1',   'ν. 4412/2016','147', '1',  'Συνολική και τμηματικές προθεσμίες','Α΄147/2016',null,'2021-03-09'),
('N4412/147/2',   'ν. 4412/2016','147', '2',  'Έναρξη προθεσμιών από την υπογραφή της σύμβασης','Α΄147/2016',null,'2021-03-09'),
('N4412/147/4',   'ν. 4412/2016','147', '4',  'Οριακή προθεσμία — το ήμισυ της αρχικής, τουλάχιστον 3 μήνες','Α΄147/2016',null,'2021-03-09'),
('N4412/147/5',   'ν. 4412/2016','147', '5',  'Παράταση — απόφαση εντός 30 ημερών, άλλως σιωπηρή αποδοχή','Α΄147/2016','{"ν. 4782/2021 άρθρο 67"}','2021-03-09'),
('N4412/147/6',   'ν. 4412/2016','147', '6',  'Παράταση με ή χωρίς αναθεώρηση — καταλογισμός ευθύνης','Α΄147/2016',null,'2021-03-09'),
('N4412/147/7',   'ν. 4412/2016','147', '7',  'Ανωτέρα βία — αίτημα σε 10 ημέρες, απόφαση σε 10 ημέρες','Α΄147/2016',null,'2021-03-09'),
('N4412/148',     'ν. 4412/2016','148', null, 'Ποινικές ρήτρες για παραβίαση προθεσμιών','Α΄147/2016',null,'2021-03-09'),
('N4412/149',     'ν. 4412/2016','149', null, 'Ρήτρα πρόσθετης καταβολής (πριμ)','Α΄147/2016',null,'2021-03-09'),
('N4412/150',     'ν. 4412/2016','150', null, 'Προκαταβολές — έως 15% της αξίας της σύμβασης','Α΄147/2016','{"ν. 4782/2021 άρθρο 69"}','2021-03-09'),
('N4412/151/1',   'ν. 4412/2016','151', '1',  'Επιμετρήσεις — δήλωση αληθείας, διάκριση συμβατικών/εκτός σύμβασης ποσοτήτων','Α΄147/2016','{"ν. 4782/2021 άρθρο 70"}','2021-03-09'),
('N4412/151/2',   'ν. 4412/2016','151', '2',  'Υποβολή επιμετρήσεων ανά τμηματική προθεσμία ή μηνιαίως — προϋπόθεση πληρωμής','Α΄147/2016','{"ν. 4782/2021 άρθρο 70"}','2021-03-09'),
('N4412/151/3',   'ν. 4412/2016','151', '3',  'Υποχρεωτικός δειγματοληπτικός έλεγχος στο 40% ή σε τουλάχιστον 4 επιμετρήσεις','Α΄147/2016','{"ν. 4782/2021 άρθρο 70"}','2021-03-09'),
('N4412/151/4',   'ν. 4412/2016','151', '4',  'Ανακριβείς επιμετρήσεις — διόρθωση και πλήρης έλεγχος','Α΄147/2016',null,'2021-03-09'),
('N4412/151/5',   'ν. 4412/2016','151', '5',  'Ψευδείς επιμετρήσεις — κυρώσεις, έκπτωση, κατάπτωση εγγύησης','Α΄147/2016',null,'2021-03-09'),
('N4412/151/7',   'ν. 4412/2016','151', '7',  'Αφανείς εργασίες — δήλωση γνωστοποίησης, έλεγχος εντός 3 ημερών, ψηφιακές φωτογραφίες, εγκριτική πράξη εντός 30 ημερών, υπερημερία κυρίου του έργου','Α΄147/2016','{"ν. 4782/2021 άρθρο 70"}','2021-03-09'),
('N4412/151/9',   'ν. 4412/2016','151', '9',  'Τελική επιμέτρηση — 2 μήνες ανάδοχος, 2 μήνες επιβλέπων, 2 μήνες έγκριση Δ.Υ.','Α΄147/2016','{"ν. 4782/2021 άρθρο 70"}','2021-03-09'),
('N4412/151/10',  'ν. 4412/2016','151', '10', 'Ποινική ρήτρα 2‰ ανά μήνα καθυστέρησης τελικής επιμέτρησης (έως 6 μήνες)','Α΄147/2016',null,'2021-03-09'),
('N4412/152',     'ν. 4412/2016','152', null, 'Λογαριασμοί — έλεγχος και έγκριση εντός 1 μηνός, σιωπηρή έγκριση, κρατήσεις 5%','Α΄147/2016','{"ν. 4782/2021 άρθρο 71"}','2021-03-09'),
('N4412/153',     'ν. 4412/2016','153', null, 'Αναθεωρητική περίοδος για τις βασικές τιμές','Α΄147/2016',null,'2021-03-09'),
('N4412/154',     'ν. 4412/2016','154', null, 'Απολογιστικές εργασίες','Α΄147/2016',null,'2021-03-09'),
('N4412/155',     'ν. 4412/2016','155', null, 'Επείγουσες και απρόβλεπτες πρόσθετες εργασίες','Α΄147/2016',null,'2021-03-09'),
('N4412/156/1',   'ν. 4412/2016','156', '1',  'Τροποποίηση σύμβασης — ανώτατο σωρευτικό όριο 50% της αρχικής αξίας','Α΄147/2016','{"ν. 4782/2021 άρθρο 72"}','2021-03-09'),
('N4412/156/1e',  'ν. 4412/2016','156', '1ε', 'Υποχρεωτική γνωμοδότηση Τεχνικού Συμβουλίου πριν τη συμπληρωματική σύμβαση','Α΄147/2016',null,'2021-03-09'),
('N4412/156/2',   'ν. 4412/2016','156', '2',  'Ανακεφαλαιωτικός Πίνακας Εργασιών (ΑΠΕ) — περιεχόμενο','Α΄147/2016',null,'2021-03-09'),
('N4412/156/3a',  'ν. 4412/2016','156', '3α', 'Τροποποίηση έως 15% της αρχικής αξίας και κάτω των ορίων του άρθρου 5','Α΄147/2016',null,'2021-03-09'),
('N4412/156/3b',  'ν. 4412/2016','156', '3β', 'Απρόβλεπτες δαπάνες: 9% για έργα ίσα/άνω του ορίου, 15% για μικρότερα','Α΄147/2016',null,'2021-03-09'),
('N4412/156/3c',  'ν. 4412/2016','156', '3γ', 'Επί έλασσον δαπάνες: έως 20% ανά ομάδα εργασιών και έως 10% της αρχικής σύμβασης — απαγόρευση νέων άρθρων — γνωμοδότηση Τεχνικού Συμβουλίου','Α΄147/2016',null,'2021-03-09'),
('N4412/156/5',   'ν. 4412/2016','156', '5',  'Π.Κ.Τ.Μ.Ν.Ε. — ιεράρχηση πηγών τιμών, τριμελής επιτροπή με τον επιβλέποντα','Α΄147/2016',null,'2021-03-09'),
('N4412/156/6',   'ν. 4412/2016','156', '6',  'Συντελεστής σ και εφαρμογή της τεκμαρτής έκπτωσης στις νέες τιμές','Α΄147/2016',null,'2021-03-09'),
('N4412/156/7',   'ν. 4412/2016','156', '7',  'Υπογραφή ΑΠΕ από τον ανάδοχο — ανεπιφύλακτα ή με επιφύλαξη — έγκριση','Α΄147/2016',null,'2021-03-09'),
('N4412/157',     'ν. 4412/2016','157', null, 'Βλάβες στα έργα — αποζημιώσεις','Α΄147/2016',null,'2021-03-09'),
('N4412/158',     'ν. 4412/2016','158', null, 'Ποιότητα στα δημόσια έργα — Πρόγραμμα Ποιότητας Έργου','Α΄147/2016',null,'2021-03-09'),
('N4412/159',     'ν. 4412/2016','159', null, 'Ακαταλληλότητα υλικών — ελαττώματα — παράλειψη συντήρησης','Α΄147/2016',null,'2021-03-09'),
('N4412/160',     'ν. 4412/2016','160', null, 'Έκπτωση αναδόχου','Α΄147/2016',null,'2021-03-09'),
('N4412/168/1',   'ν. 4412/2016','168', '1',  'Έγγραφη αναφορά επιβλέποντος περί περαίωσης εντός 30 ημερών','Α΄147/2016','{"ν. 4782/2021"}','2021-03-09'),
('N4412/168/2',   'ν. 4412/2016','168', '2',  'Έκδοση Βεβαίωσης Περάτωσης εντός 10 ημερών — τεκμήριο έκδοσης μετά από όχληση','Α΄147/2016','{"ν. 4782/2021"}','2021-03-09'),
('N4412/168/3',   'ν. 4412/2016','168', '3',  'Επουσιώδη ελαττώματα — προθεσμία αποκατάστασης','Α΄147/2016',null,'2021-03-09'),
('N4412/168/4',   'ν. 4412/2016','168', '4',  'Ουσιώδη ελαττώματα — εφαρμογή άρθρων 159 και 160','Α΄147/2016',null,'2021-03-09'),
('N4412/169',     'ν. 4412/2016','169', null, 'Διοικητική παραλαβή για χρήση','Α΄147/2016',null,'2021-03-09'),
('N4412/170',     'ν. 4412/2016','170', null, 'Ενιαίο Σύστημα Τεχνικών Προδιαγραφών και Τιμολόγησης — Μητρώο Έργου','Α΄147/2016',null,'2021-03-09'),
('N4412/171',     'ν. 4412/2016','171', null, 'Χρόνος υποχρεωτικής συντήρησης — γενικά 15 μήνες από την επομένη της Βεβαίωσης Περάτωσης','Α΄147/2016',null,'2021-03-09'),
('N4412/172',     'ν. 4412/2016','172', null, 'Παραλαβή — εντός 3 μηνών από τη λήξη της συντήρησης, πενταμελής επιτροπή, αυτοδίκαιη παραλαβή','Α΄147/2016','{"ν. 4782/2021"}','2021-03-09'),
('N4412/173',     'ν. 4412/2016','173', null, 'Απόσβεση δικαιωμάτων αναδόχου','Α΄147/2016',null,'2021-03-09'),
('N4412/174',     'ν. 4412/2016','174', null, 'Διοικητική επίλυση συμβατικών διαφορών — ένσταση σε 15 ημέρες, απόφαση σε 60 ημέρες','Α΄147/2016','{"ν. 4782/2021"}','2021-03-09'),
('YA38107/2017',  'Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466','—',null,'Καθορισμός «Ομάδων εργασιών» ανά κατηγορία έργων','Β΄1956/07.06.2017',null,'2017-06-07'),
('PD305/1996',    'π.δ. 305/1996','—',  null, 'Ελάχιστες προδιαγραφές ασφάλειας — ΣΑΥ/ΦΑΥ, γνωστοποίηση έναρξης εργασιών','Α΄212/1996',null,'1996-08-29'),
('N4727/2020',    'ν. 4727/2020','76',  null, 'Πρόγραμμα ΔΙΑΥΓΕΙΑ — υποχρέωση ανάρτησης πράξεων','Α΄184/2020',null,'2020-09-23')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 13.2 ΟΜΑΔΕΣ ΕΡΓΑΣΙΩΝ (ενδεικτικό σύνολο — συμπληρώνεται από τη Δ/νση
--      σύμφωνα με την Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017)
-- ---------------------------------------------------------------------
insert into public.work_groups (category, code, title, legal_ref_id) values
('odopoiia','A','Χωματουργικά - Καθαιρέσεις','YA38107/2017'),
('odopoiia','B','Τεχνικά έργα','YA38107/2017'),
('odopoiia','C','Ασφαλτικά','YA38107/2017'),
('odopoiia','D','Σήμανση - Ασφάλιση','YA38107/2017'),
('oikodomika','A','Χωματουργικά - Καθαιρέσεις','YA38107/2017'),
('oikodomika','B','Σκυροδέματα','YA38107/2017'),
('oikodomika','C','Τοιχοποιίες - Επιχρίσματα','YA38107/2017'),
('oikodomika','D','Επενδύσεις - Επιστρώσεις','YA38107/2017'),
('oikodomika','E','Κουφώματα - Υαλουργικά','YA38107/2017'),
('oikodomika','F','Χρωματισμοί - Λοιπές τελειώσεις','YA38107/2017'),
('ydraulika','A','Χωματουργικά','YA38107/2017'),
('ydraulika','B','Σωληνώσεις - Δίκτυα','YA38107/2017'),
('ydraulika','C','Τεχνικά έργα - Φρεάτια','YA38107/2017'),
('ydraulika','D','Ηλεκτρομηχανολογικά','YA38107/2017'),
('hlektromichanologika','A','Ηλεκτρικές εγκαταστάσεις ισχυρών ρευμάτων','YA38107/2017'),
('hlektromichanologika','B','Ηλεκτρικές εγκαταστάσεις ασθενών ρευμάτων','YA38107/2017'),
('hlektromichanologika','C','Εγκαταστάσεις θέρμανσης - κλιματισμού - αερισμού','YA38107/2017'),
('hlektromichanologika','D','Υδραυλικές εγκαταστάσεις κτιρίων','YA38107/2017'),
('hlektromichanologika','E','Πυρόσβεση - Πυρανίχνευση','YA38107/2017'),
('prasino','A','Χωματουργικά - Προετοιμασία εδάφους','YA38107/2017'),
('prasino','B','Φυτεύσεις','YA38107/2017'),
('prasino','C','Άρδευση','YA38107/2017')
on conflict (category, code) do nothing;

-- ---------------------------------------------------------------------
-- 13.3 Ο ΟΔΗΓΟΣ — ΣΤΑΔΙΑ ΕΠΙΒΛΕΨΗΣ
-- ---------------------------------------------------------------------
insert into public.workflow_stages
 (code, phase, ordinal, title, purpose, responsible, approver, recurrence,
  legal_ref_id, deadline_days, deadline_months, deadline_basis, tacit_approval,
  tacit_effect, applies_when, guard_fn, risk_note) values

-- ΦΑΣΗ 0 — ΣΥΣΤΑΣΗ ΦΑΚΕΛΟΥ & ΑΝΑΛΗΨΗ ΚΑΘΗΚΟΝΤΩΝ ----------------------
('S00_FAKELOS','f0_systasi',0,'Σύσταση φακέλου έργου & καταχώριση σύμβασης',
 'Καταχώριση όλων των στοιχείων της σύμβασης που τροφοδοτούν κάθε μετέπειτα έλεγχο: ανάδοχος, ποσά, έκπτωση, απρόβλεπτα, προθεσμίες, ΑΔΑΜ/ΑΔΑ.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','once','N4412/135',null,null,'ypografi_symvasis',false,null,null,null,
 'Λανθασμένη αρχική καταχώριση αλλοιώνει όλους τους ελέγχους ορίων (50%, 15%, 9%/15%, 10%).'),

('S01_ORISMOS','f0_systasi',1,'Ορισμός Επιβλέποντος / ομάδας επίβλεψης',
 'Ρητή απόφαση της Διευθύνουσας Υπηρεσίας για τον ορισμό επιβλέποντος, βοηθών και συντονιστή, με σαφή κατανομή καθηκόντων.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','once','N4412/136/2',null,null,'ypografi_symvasis',false,null,null,null,
 'Χωρίς νόμιμο ορισμό, οι πράξεις επίβλεψης πάσχουν αρμοδιότητας.'),

('S01B_IFE','f0_systasi',2,'Σύμβαση Ιδιωτικού Φορέα Επίβλεψης (Ι.Φ.Ε.)',
 'Έλεγχος πιστοποίησης, σύναψη σύμβασης Ι.Φ.Ε. και οριοθέτηση των υπηρεσιακών ελέγχων της Δ.Υ.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','once','N4412/136/3',null,null,'ypografi_symvasis',false,null,
 '{"supervision_mode":"ife"}'::jsonb,null,
 'Η αμοιβή του Ι.Φ.Ε. βαρύνει αποκλειστικά τον ανάδοχο· η Δ.Υ. διατηρεί δικαίωμα εναντίωσης σε 15 ημέρες.'),

('S02_GNOSTOPOIHSH','f0_systasi',3,'Γνωστοποίηση ορισμού & στοιχείων επικοινωνίας',
 'Κοινοποίηση στον ανάδοχο του ορισμού επίβλεψης και των στοιχείων επικοινωνίας — αφετηρία εγκύρων κοινοποιήσεων.',
 'dieuthynousa_ypiresia',null,'once','N4412/143',null,null,'ypografi_symvasis',false,null,null,null,
 'Άκυρη κοινοποίηση = μη έναρξη προθεσμιών ένστασης και υποβολών.'),

-- ΦΑΣΗ 1 — ΕΓΚΑΤΑΣΤΑΣΗ ------------------------------------------------
('S03_EGGYHSEIS','f1_egkatastasi',4,'Έλεγχος & καταχώριση εγγυητικών επιστολών',
 'Επαλήθευση γνησιότητας, ποσού (5%) και ισχύος της εγγύησης καλής εκτέλεσης· καταχώριση πρόσθετων εγγυήσεων.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','once','N4412/72/4',null,null,'ypografi_symvasis',false,null,null,
 'app.guard_guarantees',
 'Η μη κατάθεση/ανεπάρκεια εγγύησης θέτει σε κίνδυνο την εξασφάλιση του κυρίου του έργου.'),

('S04_TEXNIKOI','f1_egkatastasi',5,'Δήλωση τεχνικών αναδόχου & τηρούντος το ημερολόγιο',
 'Γνωστοποίηση προϊσταμένου εργοταξίου, τεχνικού ασφαλείας και του τεχνικού που τηρεί καθημερινά το ημερολόγιο.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/139',null,null,'ypografi_symvasis',false,null,null,null,
 'Χωρίς ορισμένο τηρούντα δεν υπάρχει νόμιμο ημερολόγιο — γεννάται ποινική ρήτρα.'),

('S05_ELEGXOS_MELETHS','f1_egkatastasi',6,'Έλεγχος της μελέτης δημοπράτησης από τον ανάδοχο',
 'Ο ανάδοχος ελέγχει τη μελέτη και γνωστοποιεί σφάλματα/παραλείψεις εντός της τασσόμενης προθεσμίας (20-60 ημέρες).',
 'anadochos','dieuthynousa_ypiresia','once','N4412/138/2',60,null,'ypografi_symvasis',true,
 'Η σιωπή του αναδόχου εκλαμβάνεται ως αποδοχή της μελέτης.',null,null,
 'Παράλειψη γνωστοποίησης αποκλείει μεταγενέστερες αξιώσεις για σφάλματα μελέτης (άρθρο 138 §18).'),

('S06_XRONODIAGRAMMA','f1_egkatastasi',7,'Υποβολή & έγκριση χρονοδιαγράμματος κατασκευής',
 'Υποβολή από τον ανάδοχο εντός 15-30 ημερών· έγκριση από τη Δ.Υ. εντός 15 ημερών, άλλως τεκμαίρεται εγκεκριμένο.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/145/1',30,null,'ypografi_symvasis',true,
 'Άπρακτη πάροδος 15 ημερών χωρίς έγκριση ή αίτημα διευκρινίσεων = τεκμήριο έγκρισης.',null,
 'app.guard_schedule',
 'Το εγκεκριμένο χρονοδιάγραμμα αποτελεί συμβατικό στοιχείο και βάση των τμηματικών προθεσμιών και των ρητρών.'),

('S07_ORGANOGRAMMA','f1_egkatastasi',8,'Οργανόγραμμα εργοταξίου',
 'Υποβολή οργανογράμματος με προσωπικό, εξοπλισμό και μηχανήματα του εργοταξίου.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/145/4',null,1,'ypografi_symvasis',false,null,null,null,
 'Ελλιπής στελέχωση τεκμηριώνει υπαιτιότητα αναδόχου σε καθυστερήσεις.'),

('S08_PPE','f1_egkatastasi',9,'Πρόγραμμα Ποιότητας Έργου (ΠΠΕ)',
 'Σύνταξη, υποβολή και έγκριση του ΠΠΕ και των σχεδίων ελέγχων/δοκιμών.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/158',null,null,'ypografi_symvasis',false,null,null,null,
 'Χωρίς ΠΠΕ δεν τεκμηριώνεται η ποιοτική συμμόρφωση κατά την παραλαβή.'),

('S09_SAY_FAY','f1_egkatastasi',10,'ΣΑΥ / ΦΑΥ & μέτρα ασφάλειας',
 'Επικαιροποίηση ΣΑΥ/ΦΑΥ, ορισμός τεχνικού ασφαλείας, εκ των προτέρων γνωστοποίηση έναρξης εργασιών.',
 'anadochos','dieuthynousa_ypiresia','once','PD305/1996',null,null,'ypografi_symvasis',false,null,null,null,
 'Παράλειψη επισύρει διοικητικές και ποινικές ευθύνες και διακοπή εργασιών.'),

('S10_EGKATASTASH','f1_egkatastasi',11,'Εγκατάσταση εργοταξίου & έναρξη εργασιών',
 'Παράδοση χώρου, εγκατάσταση εργοταξίου και έναρξη εργασιών — το αργότερο 30 ημέρες από την υπογραφή.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/145/2',30,null,'ypografi_symvasis',false,null,null,null,
 'Καθυστέρηση έναρξης από υπαιτιότητα αναδόχου συνιστά λόγο έκπτωσης.'),

('S11_PROKATAVOLH','f1_egkatastasi',12,'Χορήγηση προκαταβολής (προαιρετικό)',
 'Έγκριση προκαταβολής έως 15%, κατάθεση ισόποσης εγγυητικής και ορισμός τρόπου απόσβεσης.',
 'anadochos','dieuthynousa_ypiresia','conditional','N4412/150',null,null,'ypografi_symvasis',false,null,null,null,
 'Χορήγηση χωρίς εγγυητική επιστολή είναι παράνομη· η μη απόσβεση δημιουργεί δημοσιονομική ζημία.'),

-- ΦΑΣΗ 2 — ΕΚΤΕΛΕΣΗ ---------------------------------------------------
('S12_HMEROLOGIO','f2_ektelesi',13,'Τήρηση & έλεγχος ημερολογίου έργου',
 'Καθημερινή ηλεκτρονική τήρηση από τον ανάδοχο· έλεγχος και διόρθωση από τον επιβλέποντα εντός 2 εργασίμων ημερών· έγκριση από τον προϊστάμενο Δ.Υ.',
 'anadochos','dieuthynousa_ypiresia','continuous','N4412/146',null,null,'enarxi_ergasion',false,null,
 '{"diary_mode":"imerisio"}'::jsonb,'app.guard_diary',
 'Κάθε ημέρα χωρίς εγγραφή γεννά ειδική ποινική ρήτρα 100-500 € και αποδυναμώνει την απόδειξη πραγματικών περιστατικών.'),

('S13_YLIKA','f2_ektelesi',14,'Έγκριση υλικών & πηγών λήψης',
 'Υποβολή δειγμάτων/πιστοποιητικών CE και έγκριση πηγών λήψης εντός 30 ημερών από τη γνωστοποίηση.',
 'anadochos','dieuthynousa_ypiresia','repeating','N4412/138/12',30,null,'ypovoli_eggrafou',false,null,null,null,
 'Ενσωμάτωση μη εγκεκριμένων υλικών οδηγεί σε καθαίρεση με δαπάνη του αναδόχου (άρθρο 159).'),

('S14_POIOTIKOI','f2_ektelesi',15,'Ποιοτικοί & εργαστηριακοί έλεγχοι',
 'Δειγματοληψίες και δοκιμές κατά ΕΤΕΠ/ΕΛΟΤ, καταγραφή αποτελεσμάτων και συσχέτιση με το ημερολόγιο.',
 'epivlepon','dieuthynousa_ypiresia','repeating','N4412/158',null,null,'enarxi_ergasion',false,null,null,null,
 'Ελλιπείς έλεγχοι καθιστούν αδύνατη την τεκμηρίωση ποιότητας στην παραλαβή.'),

('S15_PPAE','f2_ektelesi',16,'Αφανείς εργασίες — δήλωση, έλεγχος & εγκριτική πράξη (ΠΠΑΕ)',
 'Ο ανάδοχος δηλώνει τις αφανείς εργασίες και καλεί τον επιβλέποντα ΠΡΙΝ την επικάλυψη· έλεγχος εντός 3 ημερών με ψηφιακές φωτογραφίες· εγκριτική πράξη Δ.Υ. εντός 30 ημερών.',
 'anadochos','dieuthynousa_ypiresia','repeating','N4412/151/7',3,null,'koinopoiisi_praxis',false,null,null,
 'app.guard_hidden_works',
 'Επικάλυψη χωρίς έλεγχο καθιστά αδύνατη την επιμέτρηση· παράλειψη ελέγχου εντός 3 ημερών συνιστά υπερημερία του κυρίου του έργου.'),

('S16_EPIMETRHSEIS','f2_ektelesi',17,'Τμηματικές επιμετρήσεις & δειγματοληπτικός έλεγχος',
 'Υποβολή επιμετρήσεων ανά τμηματική προθεσμία ή μηνιαίως, με δήλωση αληθείας και επιμετρητικά σχέδια· υποχρεωτικός δειγματοληπτικός έλεγχος 40% (ή ≥4).',
 'anadochos','dieuthynousa_ypiresia','repeating','N4412/151/2',30,null,'ypovoli_eggrafou',false,null,null,
 'app.guard_measurements',
 'Η επιμέτρηση είναι προϋπόθεση πληρωμής· ανακριβείς/ψευδείς επιμετρήσεις οδηγούν σε έκπτωση και κατάπτωση εγγύησης.'),

('S17_LOGARIASMOI','f2_ektelesi',18,'Λογαριασμοί — έλεγχος & έγκριση',
 'Υποβολή λογαριασμού με τα προβλεπόμενα συνημμένα· έλεγχος, διόρθωση και έγκριση από τη Δ.Υ. εντός ενός μηνός.',
 'anadochos','dieuthynousa_ypiresia','repeating','N4412/152',null,1,'ypovoli_eggrafou',true,
 'Άπρακτη πάροδος ενός μηνός: ο λογαριασμός θεωρείται εγκεκριμένος και καθίσταται πληρωτέος.',null,null,
 'Η άπρακτη πάροδος δημιουργεί πληρωτέο λογαριασμό χωρίς έλεγχο — κίνδυνος αχρεωστήτως καταβληθέντων.'),

('S18_TRIMHNIAIES','f2_ektelesi',19,'Τριμηνιαίες εκθέσεις πορείας',
 'Σύνταξη τριμηνιαίας έκθεσης από τη Δ.Υ. με εντοπισμό σφαλμάτων προμέτρησης και απρόβλεπτων περιστάσεων· αντίστοιχη αναφορά αναδόχου.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','repeating','N4412/136/10',null,3,'enarxi_ergasion',false,null,null,null,
 'Η μη τήρηση συνιστά ΠΕΙΘΑΡΧΙΚΟ ΠΑΡΑΠΤΩΜΑ των αρμοδίων οργάνων.'),

('S19_APE','f2_ektelesi',20,'Ανακεφαλαιωτικοί Πίνακες Εργασιών & ΠΚΤΜΝΕ',
 'Σύνταξη ΑΠΕ με έλεγχο των ορίων 50% / 9%-15% / 20% ανά ομάδα / 10% συνολικά· κανονισμός νέων τιμών· γνωμοδότηση Τεχνικού Συμβουλίου όπου απαιτείται.',
 'dieuthynousa_ypiresia','proistameni_arxi','repeating','N4412/156/2',null,null,'custom',false,null,null,
 'app.guard_ape_stage',
 'Υπέρβαση ορίων ή παράλειψη γνωμοδότησης καθιστά την τροποποίηση παράνομη και μη πληρωτέα.'),

('S20_PARATASEIS','f2_ektelesi',21,'Παρατάσεις προθεσμιών',
 'Υποβολή αιτήματος πριν τη λήξη της προθεσμίας· απόφαση εντός 30 ημερών· καταλογισμός ευθύνης και χαρακτηρισμός «με/χωρίς αναθεώρηση».',
 'anadochos','proistameni_arxi','conditional','N4412/147/5',30,null,'ypovoli_eggrafou',true,
 'Άπρακτη πάροδος 30 ημερών: η παράταση θεωρείται εγκριθείσα αναδρομικά.',null,null,
 'Λήξη προθεσμίας χωρίς παράταση οδηγεί σε ποινικές ρήτρες και, μετά την οριακή, σε λύση της σύμβασης.'),

('S21_ANWTERA_BIA','f2_ektelesi',22,'Αναστολή προθεσμιών λόγω ανωτέρας βίας',
 'Αίτημα εντός 10 ημερών από το γεγονός· απόφαση εντός 10 ημερών· τήρηση του ανώτατου ορίου αναστολής.',
 'anadochos','dieuthynousa_ypiresia','conditional','N4412/147/7',10,null,'custom',true,
 'Άπρακτη πάροδος 10 ημερών: το αίτημα θεωρείται αποδεκτό.',null,null,
 'Εκπρόθεσμο αίτημα απορρίπτεται και ο χρόνος προσμετράται εις βάρος του αναδόχου.'),

('S22_POINIKES','f2_ektelesi',23,'Ποινικές ρήτρες & πρόστιμα',
 'Υπολογισμός και επιβολή ρητρών υπέρβασης προθεσμιών, παράλειψης ημερολογίου και καθυστέρησης τελικής επιμέτρησης· παρακράτηση στον επόμενο λογαριασμό.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','conditional','N4412/148',null,null,'custom',false,null,null,null,
 'Μη επιβολή οφειλόμενων ρητρών συνιστά παράβαση καθήκοντος και δημοσιονομική ζημία.'),

('S23_ENSTASEIS','f2_ektelesi',24,'Ενστάσεις — διοικητική επίλυση διαφορών',
 'Παραλαβή ένστασης εντός 15 ημερών από την κοινοποίηση· εισήγηση, γνωμοδότηση Τεχνικού Συμβουλίου, απόφαση εντός 60 ημερών.',
 'anadochos','proistameni_arxi','conditional','N4412/174',60,null,'koinopoiisi_praxis',true,
 'Άπρακτη πάροδος 60 ημερών: τεκμαίρεται σιωπηρή αποδοχή της γνωμοδότησης.',null,null,
 'Παράλειψη τήρησης της διαδικασίας γεννά ακυρότητες και δικαστικές διαφορές.'),

-- ΦΑΣΗ 3 — ΠΕΡΑΙΩΣΗ ---------------------------------------------------
('S24_DHLWSH_PERAIWSHS','f3_peraiosi',25,'Δήλωση περαίωσης / λήξη εγκεκριμένου χρόνου',
 'Καταγραφή της δήλωσης περαίωσης του αναδόχου ή της λήξης του εγκεκριμένου χρόνου περαίωσης.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/168/1',null,null,'lixi_prothesmias',false,null,null,null,
 'Λανθασμένη ημερομηνία περαίωσης μετατοπίζει όλες τις επόμενες προθεσμίες (συντήρηση, παραλαβή).'),

('S25_EKTHESI_EPIVL','f3_peraiosi',26,'Έκθεση επιβλέποντος περί περαίωσης',
 'Έγγραφη αναφορά στη Δ.Υ. εντός 30 ημερών από τη λήξη του εγκεκριμένου χρόνου: ολοκλήρωση εργασιών, δοκιμές, ελαττώματα.',
 'epivlepon','dieuthynousa_ypiresia','once','N4412/168/1',30,null,'lixi_prothesmias',false,null,null,
 'app.guard_completion',
 'Η καθυστέρηση της έκθεσης επισύρει πειθαρχική ευθύνη (άρθρο 141 §3).'),

('S26_BEBAIWSH','f3_peraiosi',27,'Έκδοση Βεβαίωσης Περάτωσης Εργασιών',
 'Έκδοση από τον προϊστάμενο της Δ.Υ. εντός 10 ημερών από τη λήψη της έκθεσης, με αναγραφή της πραγματικής ημερομηνίας περαίωσης.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','once','N4412/168/2',10,null,'ypovoli_eggrafou',true,
 'Αν δεν εκδοθεί, τεκμαίρεται εκδοθείσα 30 ημέρες μετά την έγγραφη όχληση του αναδόχου.',null,null,
 'Η Βεβαίωση εκκινεί τον χρόνο υποχρεωτικής συντήρησης και δεσμεύει το χρονοδιάγραμμα παραλαβής.'),

('S27_TELIKH_EPIM','f3_peraiosi',28,'Τελική επιμέτρηση',
 'Υποβολή τελικής επιμέτρησης εντός 2 μηνών από την περαίωση· έκθεση επιβλέποντος εντός 2 μηνών· έγκριση Δ.Υ. εντός 2 μηνών.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/151/9',null,2,'bebaiosi_peratosis',false,null,null,null,
 'Καθυστέρηση επισύρει ποινική ρήτρα 2‰/μήνα (έως 6 μήνες) και δυνατότητα σύνταξης από την υπηρεσία σε βάρος του αναδόχου.'),

('S28_MEIWSH_EGG','f3_peraiosi',29,'Μείωση εγγύησης καλής εκτέλεσης κατά 70%',
 'Έκδοση πράξης μείωσης της εγγύησης καλής εκτέλεσης κατά 70%, αμέσως μετά την έγκριση της τελικής επιμέτρησης.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','once','N4412/72/14b',null,null,'custom',false,null,null,
 'app.guard_guarantee_reduction',
 'Πρόωρη μείωση εκθέτει τον κύριο του έργου· καθυστερημένη μείωση επιβαρύνει αδικαιολόγητα τον ανάδοχο.'),

-- ΦΑΣΗ 4 — ΣΥΝΤΗΡΗΣΗ & ΠΑΡΑΛΑΒΗ --------------------------------------
('S29_SYNTHRHSH','f4_paralavi',30,'Χρόνος υποχρεωτικής συντήρησης',
 'Παρακολούθηση της υποχρεωτικής συντήρησης (γενικά 15 μήνες) με περιοδικές επιθεωρήσεις και αποκατάσταση ελαττωμάτων.',
 'anadochos','epivlepon','continuous','N4412/171',null,15,'bebaiosi_peratosis',false,null,null,null,
 'Παράλειψη συντήρησης ενεργοποιεί το άρθρο 159 (έκπτωση/εκτέλεση σε βάρος του αναδόχου).'),

('S30_EPITROPH','f4_paralavi',31,'Ορισμός Επιτροπής Παραλαβής',
 'Ορισμός πενταμελούς επιτροπής (με δύο εκπροσώπους ΤΕΕ/ΓΕΩΤΕΕ) τουλάχιστον 3 μήνες πριν τη λήξη της συντήρησης.',
 'proistameni_arxi','proistameni_arxi','once','N4412/172',null,null,'lixi_syntirisis',false,null,null,null,
 'Καθυστερημένος ορισμός οδηγεί σε αυτοδίκαιη παραλαβή χωρίς ουσιαστικό έλεγχο.'),

('S31_PARALABH','f4_paralavi',32,'Παραλαβή έργου & πρωτόκολλο',
 'Διενέργεια παραλαβής εντός 3 μηνών από τη λήξη της συντήρησης και σύνταξη/έγκριση πρωτοκόλλου.',
 'epitropi','proistameni_arxi','once','N4412/172',null,3,'lixi_syntirisis',true,
 'Αν η επιτροπή δεν ενεργήσει εντός 3 μηνών, η παραλαβή θεωρείται αυτοδικαίως συντελεσμένη.',null,
 'app.guard_acceptance',
 'Η αυτοδίκαιη παραλαβή στερεί από την υπηρεσία τη δυνατότητα καταγραφής ελαττωμάτων.'),

('S32_TELIKOS_LOG','f4_paralavi',33,'Τελικός λογαριασμός & εκκαθάριση',
 'Υποβολή και έγκριση τελικού λογαριασμού μετά την παραλαβή — εκκαθάριση των εκατέρωθεν απαιτήσεων.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/152',null,1,'ypovoli_eggrafou',true,
 'Άπρακτη πάροδος ενός μηνός: ο τελικός λογαριασμός θεωρείται εγκεκριμένος.',null,null,
 'Χωρίς εγκεκριμένο τελικό λογαριασμό δεν επιτρέπεται η επιστροφή των εγγυήσεων.'),

('S33_APODESMEVSH','f4_paralavi',34,'Επιστροφή εγγυητικών επιστολών',
 'Ολική επιστροφή των εγγυήσεων καλής εκτέλεσης μετά την έγκριση του πρωτοκόλλου παραλαβής και του τελικού λογαριασμού.',
 'dieuthynousa_ypiresia','dieuthynousa_ypiresia','once','N4412/72/14b',null,null,'custom',false,null,null,null,
 'Πρόωρη επιστροφή αποστερεί τον κύριο του έργου από κάθε εξασφάλιση.'),

('S34_MHTRWO','f4_paralavi',35,'Μητρώο Έργου & αρχειοθέτηση',
 'Ολοκλήρωση του Μητρώου Έργου (σχέδια «as built», φωτογραφικό υλικό αφανών, εγχειρίδια λειτουργίας & συντήρησης) και οριστική αρχειοθέτηση.',
 'anadochos','dieuthynousa_ypiresia','once','N4412/170',null,null,'custom',false,null,null,null,
 'Ελλιπές Μητρώο καθιστά αδύνατη τη μελλοντική συντήρηση και τεκμηρίωση του έργου.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- 13.4 ΠΡΟΑΠΑΙΤΟΥΜΕΝΑ (checkpoints)
-- ---------------------------------------------------------------------
insert into public.stage_prerequisites (stage_code, requires_code, is_hard, rationale) values
('S01_ORISMOS','S00_FAKELOS',true,'Ο ορισμός προϋποθέτει καταχωρημένη σύμβαση.'),
('S01B_IFE','S00_FAKELOS',true,null),
('S02_GNOSTOPOIHSH','S01_ORISMOS',true,'Κοινοποιείται ο νόμιμος ορισμός.'),
('S03_EGGYHSEIS','S00_FAKELOS',true,null),
('S04_TEXNIKOI','S02_GNOSTOPOIHSH',true,null),
('S05_ELEGXOS_MELETHS','S02_GNOSTOPOIHSH',false,null),
('S06_XRONODIAGRAMMA','S03_EGGYHSEIS',true,'Δεν εγκρίνεται χρονοδιάγραμμα χωρίς κατατεθειμένη εγγύηση καλής εκτέλεσης.'),
('S06_XRONODIAGRAMMA','S04_TEXNIKOI',true,null),
('S07_ORGANOGRAMMA','S06_XRONODIAGRAMMA',true,null),
('S08_PPE','S06_XRONODIAGRAMMA',true,null),
('S09_SAY_FAY','S04_TEXNIKOI',true,null),
('S10_EGKATASTASH','S06_XRONODIAGRAMMA',true,'Η έναρξη εργασιών προϋποθέτει εγκεκριμένο χρονοδιάγραμμα.'),
('S10_EGKATASTASH','S09_SAY_FAY',true,'Δεν αρχίζουν εργασίες χωρίς ΣΑΥ/ΦΑΥ και μέτρα ασφάλειας.'),
('S11_PROKATAVOLH','S03_EGGYHSEIS',true,'Απαιτείται εγγύηση προκαταβολής.'),
('S12_HMEROLOGIO','S10_EGKATASTASH',true,null),
('S13_YLIKA','S10_EGKATASTASH',true,null),
('S14_POIOTIKOI','S08_PPE',true,null),
('S15_PPAE','S12_HMEROLOGIO',true,'Οι αφανείς τεκμηριώνονται και μέσω του ημερολογίου.'),
('S16_EPIMETRHSEIS','S15_PPAE',true,'Οι αφανείς εργασίες πρέπει να έχουν ελεγχθεί πριν επιμετρηθούν.'),
('S17_LOGARIASMOI','S16_EPIMETRHSEIS',true,'Η επιμέτρηση αποτελεί προϋπόθεση πληρωμής (άρθρο 151 §2).'),
('S18_TRIMHNIAIES','S10_EGKATASTASH',true,null),
('S19_APE','S16_EPIMETRHSEIS',true,'Ο ΑΠΕ βασίζεται σε επιμετρημένες ποσότητες.'),
('S20_PARATASEIS','S06_XRONODIAGRAMMA',true,null),
('S22_POINIKES','S12_HMEROLOGIO',false,null),
('S24_DHLWSH_PERAIWSHS','S10_EGKATASTASH',true,null),
('S25_EKTHESI_EPIVL','S24_DHLWSH_PERAIWSHS',true,null),
('S25_EKTHESI_EPIVL','S12_HMEROLOGIO',false,'Η τεκμηρίωση της περαίωσης στηρίζεται στο ημερολόγιο.'),
('S26_BEBAIWSH','S25_EKTHESI_EPIVL',true,'Η Βεβαίωση εκδίδεται επί τη βάσει της έκθεσης του επιβλέποντος.'),
('S27_TELIKH_EPIM','S26_BEBAIWSH',true,null),
('S27_TELIKH_EPIM','S16_EPIMETRHSEIS',true,null),
('S28_MEIWSH_EGG','S27_TELIKH_EPIM',true,'Η μείωση 70% προϋποθέτει ΕΓΚΕΚΡΙΜΕΝΗ τελική επιμέτρηση (άρθρο 72 §14β).'),
('S29_SYNTHRHSH','S26_BEBAIWSH',true,'Ο χρόνος συντήρησης αρχίζει την επομένη της Βεβαίωσης.'),
('S30_EPITROPH','S29_SYNTHRHSH',true,null),
('S31_PARALABH','S30_EPITROPH',true,null),
('S31_PARALABH','S29_SYNTHRHSH',true,null),
('S32_TELIKOS_LOG','S31_PARALABH',true,'Ο τελικός λογαριασμός έπεται της παραλαβής.'),
('S32_TELIKOS_LOG','S19_APE',false,'Τακτοποίηση τυχόν εκκρεμών ΑΠΕ.'),
('S33_APODESMEVSH','S32_TELIKOS_LOG',true,'Επιστροφή εγγυήσεων μετά την έγκριση τελικού λογαριασμού.'),
('S33_APODESMEVSH','S31_PARALABH',true,null),
('S34_MHTRWO','S31_PARALABH',true,null)
on conflict do nothing;

-- >>>>>>>>>>>>>>>>>>>> 0014_seed_tasks_documents.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Migration 0014 : Λίστες ελέγχου ανά στάδιο (ΔΙΑΧΩΡΙΣΜΟΣ ΡΟΛΩΝ)
--                  και υποχρεωτικά παραγόμενα έγγραφα
-- =====================================================================

insert into public.stage_tasks
 (stage_code, ordinal, party, title, detail, legal_ref_id, is_mandatory, needs_evidence) values

-- S00 ------------------------------------------------------------------
('S00_FAKELOS',1,'dieuthynousa_ypiresia','Καταχώριση στοιχείων σύμβασης','Αριθμός & ημερομηνία σύμβασης, ΑΔΑΜ/ΑΔΑ, ανάδοχος, ΑΦΜ, νόμιμος εκπρόσωπος.','N4412/135',true,true),
('S00_FAKELOS',2,'dieuthynousa_ypiresia','Καταχώριση οικονομικών στοιχείων','Δαπάνη εργασιών, ΓΕ&ΟΕ 18%, απρόβλεπτα (9% ή 15%), αναθεώρηση, ΦΠΑ, μέση τεκμαρτή έκπτωση.','N4412/156/3b',true,false),
('S00_FAKELOS',3,'dieuthynousa_ypiresia','Καταχώριση προθεσμιών','Συνολική προθεσμία, τμηματικές (αποκλειστικές/ενδεικτικές), υπολογισμός οριακής προθεσμίας.','N4412/147/1',true,false),
('S00_FAKELOS',4,'dieuthynousa_ypiresia','Εισαγωγή προϋπολογισμού & τιμολογίου','Άρθρα, μονάδες, τιμές μονάδος, ποσότητες και αντιστοίχιση σε Ομάδες Εργασιών.','YA38107/2017',true,true),
('S00_FAKELOS',5,'dieuthynousa_ypiresia','Επιβεβαίωση καταχώρισης στο Κ.Η.Μ.ΔΗ.Σ.','Ανάρτηση συμφωνητικού και λήψη ΑΔΑΜ.','N4412/38',true,true),

-- S01 ------------------------------------------------------------------
('S01_ORISMOS',1,'dieuthynousa_ypiresia','Έκδοση απόφασης ορισμού επιβλέποντος','Ορισμός επιβλέποντος, βοηθών και —εφόσον συγκροτείται ομάδα— συντονιστή, με σαφή κατανομή καθηκόντων.','N4412/136/2',true,true),
('S01_ORISMOS',2,'dieuthynousa_ypiresia','Έλεγχος καταλληλότητας προσόντων','Αντιστοιχία ειδικότητας/κατηγορίας με τη φύση του έργου.','N4412/136/2',true,false),
('S01_ORISMOS',3,'dieuthynousa_ypiresia','Ανάρτηση απόφασης στη ΔΙΑΥΓΕΙΑ','Λήψη ΑΔΑ.','N4727/2020',true,true),

-- S01B -----------------------------------------------------------------
('S01B_IFE',1,'anadochos','Δήλωση Ιδιωτικού Φορέα Επίβλεψης','Δηλώνεται με την προσφορά· σε απόρριψη προτείνεται νέος εντός της τασσόμενης προθεσμίας.','N4412/136/3',true,true),
('S01B_IFE',2,'dieuthynousa_ypiresia','Έλεγχος πιστοποίησης & ασυμβιβάστων','Επαλήθευση εγγραφής στο μητρώο πιστοποιημένων φορέων και ανεξαρτησίας.','N4412/136/3',true,true),
('S01B_IFE',3,'dieuthynousa_ypiresia','Έλεγχος σχεδίου σύμβασης Ι.Φ.Ε.','Η αμοιβή βαρύνει αποκλειστικά τον ανάδοχο.','N4412/136/3',true,false),

-- S02 ------------------------------------------------------------------
('S02_GNOSTOPOIHSH',1,'dieuthynousa_ypiresia','Κοινοποίηση ορισμού επίβλεψης στον ανάδοχο','Έγγραφη/ηλεκτρονική κοινοποίηση με αποδεικτικό.','N4412/143',true,true),
('S02_GNOSTOPOIHSH',2,'anadochos','Δήλωση αντικλήτου & στοιχείων επικοινωνίας','Ορισμός εκπροσώπου και διεύθυνσης επιδόσεων.','N4412/143',true,true),

-- S03 ------------------------------------------------------------------
('S03_EGGYHSEIS',1,'anadochos','Κατάθεση εγγύησης καλής εκτέλεσης','Ποσοστό 5% επί της εκτιμώμενης αξίας, πριν την υπογραφή του συμφωνητικού.','N4412/72/4',true,true),
('S03_EGGYHSEIS',2,'dieuthynousa_ypiresia','Επαλήθευση γνησιότητας εγγυητικής','Επιβεβαίωση από τον εκδότη (τράπεζα/ΤΜΕΔΕ).','N4412/72/4',true,true),
('S03_EGGYHSEIS',3,'dieuthynousa_ypiresia','Έλεγχος πρόσθετης εγγύησης λόγω έκπτωσης','Όπου προβλέπεται όριο ποσοστού έκπτωσης με απόφαση Υπουργού Υποδομών & Μεταφορών.','N4412/72/4',false,false),

-- S04 ------------------------------------------------------------------
('S04_TEXNIKOI',1,'anadochos','Γνωστοποίηση προϊσταμένου εργοταξίου','Στοιχεία, ειδικότητα και δήλωση αποδοχής.','N4412/139',true,true),
('S04_TEXNIKOI',2,'anadochos','Ορισμός τεχνικού τήρησης ημερολογίου','Ο τεχνικός υπογράφει ψηφιακά το ημερολόγιο.','N4412/146',true,true),
('S04_TEXNIKOI',3,'anadochos','Ορισμός τεχνικού ασφαλείας / συντονιστή ασφάλειας','Κατά τις κείμενες διατάξεις ασφάλειας & υγείας.','PD305/1996',true,true),
('S04_TEXNIKOI',4,'epivlepon','Έλεγχος επάρκειας τεχνικού προσωπικού','Αντιστοιχία με το ελάχιστο απαιτούμενο των τευχών.','N4412/138/10',true,false),

-- S05 ------------------------------------------------------------------
('S05_ELEGXOS_MELETHS',1,'anadochos','Έλεγχος μελέτης & γνωστοποίηση ευρημάτων','Εντός της τασσόμενης προθεσμίας (20-60 ημέρες)· η σιωπή ισοδυναμεί με αποδοχή.','N4412/138/2',true,true),
('S05_ELEGXOS_MELETHS',2,'epivlepon','Αξιολόγηση ευρημάτων αναδόχου','Εισήγηση για διόρθωση μελέτης ή απόρριψη ισχυρισμών.','N4412/138/2',true,true),

-- S06 ------------------------------------------------------------------
('S06_XRONODIAGRAMMA',1,'anadochos','Υποβολή χρονοδιαγράμματος','Εντός της συμβατικής προθεσμίας (15-30 ημέρες από την υπογραφή), σε έντυπη και ηλεκτρονική μορφή.','N4412/145/1',true,true),
('S06_XRONODIAGRAMMA',2,'anadochos','Δικτυωτή ανάλυση (έργα > 1.000.000 €)','Υποχρεωτική μέθοδος για έργα άνω του ορίου.','N4412/145/3',false,true),
('S06_XRONODIAGRAMMA',3,'epivlepon','Έλεγχος αλληλουχίας & μεθοδολογίας','Έλεγχος ρεαλιστικότητας, τμηματικών προθεσμιών και τετραγωνικού πίνακα ποσοτήτων.','N4412/145/2',true,false),
('S06_XRONODIAGRAMMA',4,'dieuthynousa_ypiresia','Έγκριση ή αίτημα διευκρινίσεων εντός 15 ημερών','Άπρακτη πάροδος = τεκμήριο έγκρισης· απαιτείται ρητή καταχώριση της σιωπηρής έγκρισης.','N4412/145/2',true,true),

-- S07-S09 --------------------------------------------------------------
('S07_ORGANOGRAMMA',1,'anadochos','Υποβολή οργανογράμματος εργοταξίου','Προσωπικό, εξοπλισμός, μηχανήματα.','N4412/145/4',true,true),
('S07_ORGANOGRAMMA',2,'epivlepon','Έλεγχος επάρκειας μέσων','Συσχέτιση με το εγκεκριμένο χρονοδιάγραμμα.','N4412/145/4',true,false),
('S08_PPE',1,'anadochos','Υποβολή Προγράμματος Ποιότητας Έργου','Σχέδια ελέγχων και δοκιμών, υπεύθυνοι ποιότητας.','N4412/158',true,true),
('S08_PPE',2,'epivlepon','Έλεγχος & εισήγηση έγκρισης ΠΠΕ','Συμβατότητα με ΕΤΕΠ/ΕΛΟΤ και τη μελέτη.','N4412/158',true,true),
('S09_SAY_FAY',1,'anadochos','Επικαιροποίηση ΣΑΥ & ΦΑΥ','Προσαρμογή στις πραγματικές συνθήκες του εργοταξίου.','PD305/1996',true,true),
('S09_SAY_FAY',2,'anadochos','Εκ των προτέρων γνωστοποίηση έναρξης εργασιών','Υποβολή στην αρμόδια Επιθεώρηση Εργασίας.','PD305/1996',true,true),
('S09_SAY_FAY',3,'epivlepon','Έλεγχος μέτρων ασφάλειας & σήμανσης','Καταγραφή στο ημερολόγιο.','N4412/138/9',true,false),

-- S10-S11 --------------------------------------------------------------
('S10_EGKATASTASH',1,'dieuthynousa_ypiresia','Παράδοση χώρου εκτέλεσης εργασιών','Πρωτόκολλο παράδοσης-παραλαβής χώρου.','N4412/137',true,true),
('S10_EGKATASTASH',2,'anadochos','Εγκατάσταση εργοταξίου & έναρξη εργασιών','Το αργότερο 30 ημέρες από την υπογραφή της σύμβασης.','N4412/145/2',true,true),
('S10_EGKATASTASH',3,'epivlepon','Καταγραφή ημερομηνίας έναρξης','Πρώτη εγγραφή στο ημερολόγιο έργου.','N4412/146',true,false),
('S11_PROKATAVOLH',1,'anadochos','Αίτημα προκαταβολής & κατάθεση εγγυητικής','Ισόποση εγγυητική επιστολή προκαταβολής.','N4412/72/7',true,true),
('S11_PROKATAVOLH',2,'dieuthynousa_ypiresia','Έλεγχος ορίων & έγκριση','Έως 15% συνολικά (έως 5%/7% εγκατάστασης, έως 10% υλικών).','N4412/150',true,true),
('S11_PROKATAVOLH',3,'dieuthynousa_ypiresia','Ορισμός τρόπου απόσβεσης & τόκων','Παρακράτηση σε κάθε επόμενο λογαριασμό.','N4412/150',true,false),

-- S12-S14 --------------------------------------------------------------
('S12_HMEROLOGIO',1,'anadochos','Καθημερινή συμπλήρωση ημερολογίου','Καιρικές συνθήκες, προσωπικό ανά ειδικότητα, μηχανήματα, εργασίες, δοκιμές, συμβάντα, εντολές.','N4412/146',true,false),
('S12_HMEROLOGIO',2,'anadochos','Ηλεκτρονική αποστολή σε επιβλέποντα & προϊστάμενο Δ.Υ.','Με ψηφιακή υπογραφή του τηρούντος.','N4412/146',true,false),
('S12_HMEROLOGIO',3,'epivlepon','Έλεγχος & διόρθωση εντός 2 εργασίμων ημερών','Υποβολή προς έγκριση στον προϊστάμενο της Δ.Υ.','N4412/146',true,false),
('S12_HMEROLOGIO',4,'dieuthynousa_ypiresia','Επιβολή ειδικής ποινικής ρήτρας επί παραλείψεων','100-500 € ανά ημέρα, αναλόγως του μεγέθους της σύμβασης.','N4412/146',false,true),
('S13_YLIKA',1,'anadochos','Υποβολή πηγών λήψης & πιστοποιητικών','Δείγματα, δηλώσεις επιδόσεων, σήμανση CE.','N4412/138/12',true,true),
('S13_YLIKA',2,'epivlepon','Έλεγχος συμμόρφωσης με ΕΤΕΠ/ΕΛΟΤ','Εισήγηση έγκρισης ή απόρριψης.','N4412/158',true,true),
('S13_YLIKA',3,'dieuthynousa_ypiresia','Απόφαση εντός 30 ημερών','Όταν η πηγή αποκλίνει από τη μελέτη.','N4412/138/12',true,true),
('S14_POIOTIKOI',1,'epivlepon','Πρόγραμμα δειγματοληψιών & δοκιμών','Σύμφωνα με το εγκεκριμένο ΠΠΕ.','N4412/158',true,false),
('S14_POIOTIKOI',2,'anadochos','Διενέργεια εργαστηριακών ελέγχων','Υποβολή εκθέσεων δοκιμών.','N4412/158',true,true),
('S14_POIOTIKOI',3,'epivlepon','Αξιολόγηση αποτελεσμάτων & εντολές συμμόρφωσης','Επί μη συμμόρφωσης εφαρμόζεται το άρθρο 159.','N4412/159',true,true),

-- S15 ΠΠΑΕ -------------------------------------------------------------
('S15_PPAE',1,'anadochos','Δήλωση γνωστοποίησης αφανών εργασιών','Διακριτή επιμέτρηση με δήλωση αληθείας, υπογεγραμμένη και από τους τεχνικούς του άρθρου 139.','N4412/151/7',true,true),
('S15_PPAE',2,'anadochos','Πρόσκληση επιβλέποντος πριν την επικάλυψη','Ημερομηνία ελέγχου που δεν απέχει περισσότερο από 3 ημέρες από την κοινοποίηση.','N4412/151/7',true,true),
('S15_PPAE',3,'epivlepon','Αυτοψία & έλεγχος αφανών εργασιών','Υποχρεωτική ανταπόκριση· η παράλειψη συνιστά υπερημερία του κυρίου του έργου.','N4412/151/7',true,false),
('S15_PPAE',4,'epivlepon','Σύνταξη έκθεσης με ψηφιακές φωτογραφίες','Επαρκής αριθμός φωτογραφιών, οι οποίες εντάσσονται στο Μητρώο του Έργου.','N4412/151/7',true,true),
('S15_PPAE',5,'dieuthynousa_ypiresia','Εγκριτική πράξη επιμέτρησης αφανών εντός 30 ημερών','Η έκθεση δεν προσβάλλεται αυτοτελώς, παρά μόνο μαζί με την εγκριτική πράξη.','N4412/151/7',true,true),

-- S16 ------------------------------------------------------------------
('S16_EPIMETRHSEIS',1,'anadochos','Λήψη επιτόπιων επιμετρητικών στοιχείων','Υποβολή στον επιβλέποντα με δήλωση περί της αλήθειας των στοιχείων.','N4412/151/1',true,true),
('S16_EPIMETRHSEIS',2,'anadochos','Σύνταξη επιμέτρησης ανά διακριτό τμήμα','Περιγραφή εργασιών, άρθρα τιμολογίου, επιμετρητικά σχέδια· έντυπη & ηλεκτρονική μορφή.','N4412/151/2',true,true),
('S16_EPIMETRHSEIS',3,'anadochos','Διάκριση συμβατικών & εκτός σύμβασης ποσοτήτων','Ρητή επισήμανση ποσοτήτων πέραν των συμβατικών.','N4412/151/1',true,false),
('S16_EPIMETRHSEIS',4,'epivlepon','Έλεγχος & θεώρηση επιμέτρησης','Διασταύρωση με ημερολόγιο, ΠΠΑΕ και εγκεκριμένο χρονοδιάγραμμα.','N4412/151/2',true,false),
('S16_EPIMETRHSEIS',5,'dieuthynousa_ypiresia','Δειγματοληπτικός έλεγχος 40% (ή ≥4)','Υποχρεωτικός έλεγχος του 40% των υποβληθεισών ή τουλάχιστον τεσσάρων, αν είναι λιγότερες από δέκα.','N4412/151/3',true,true),
('S16_EPIMETRHSEIS',6,'dieuthynousa_ypiresia','Χειρισμός ανακριβειών','Εντολή διόρθωσης, πλήρης έλεγχος, και επί ψευδών δηλώσεων εφαρμογή κυρώσεων.','N4412/151/5',false,true),

-- S17 ------------------------------------------------------------------
('S17_LOGARIASMOI',1,'anadochos','Υποβολή λογαριασμού','Με βάση εγκεκριμένες επιμετρήσεις και δηλώσεις αφανών εργασιών.','N4412/152',true,true),
('S17_LOGARIASMOI',2,'anadochos','Επισύναψη ανακεφαλαιωτικού συνοπτικού πίνακα επιμετρήσεων','Υποχρεωτικό συνοδευτικό.','N4412/152',true,true),
('S17_LOGARIASMOI',3,'anadochos','Επισύναψη υπολογισμού αναθεώρησης & δικαιολογητικών απολογιστικών','Όπου συντρέχει περίπτωση.','N4412/153',false,true),
('S17_LOGARIASMOI',4,'epivlepon','Έλεγχος ποσοτήτων, τιμών & κρατήσεων','Έλεγχος απόσβεσης προκαταβολής, ρητρών και κρατήσεων 5%.','N4412/152',true,false),
('S17_LOGARIASMOI',5,'dieuthynousa_ypiresia','Έλεγχος, διόρθωση & έγκριση εντός 1 μηνός','Επί ελλείψεων επιστρέφεται για συμπλήρωση και η προθεσμία εκκινεί εκ νέου.','N4412/152',true,true),

-- S18 ------------------------------------------------------------------
('S18_TRIMHNIAIES',1,'anadochos','Τριμηνιαία συνοπτική αναφορά προόδου','Υποβάλλεται μέσω της Δ.Υ. στην Προϊσταμένη Αρχή.','N4412/138/17',true,true),
('S18_TRIMHNIAIES',2,'dieuthynousa_ypiresia','Σύνταξη τριμηνιαίας έκθεσης πορείας','Εντοπισμός σφαλμάτων προμέτρησης και απρόβλεπτων περιστάσεων· η μη τήρηση είναι πειθαρχικό παράπτωμα.','N4412/136/10',true,true),

-- S19 ------------------------------------------------------------------
('S19_APE',1,'epivlepon','Τεκμηρίωση αναγκαιότητας μεταβολών','Αιτιολόγηση βάσει επιμετρήσεων, σφαλμάτων προμέτρησης ή απρόβλεπτων περιστάσεων.','N4412/156/2',true,true),
('S19_APE',2,'dieuthynousa_ypiresia','Σύνταξη ΑΠΕ','Αρχικός, προηγούμενος και νέος προϋπολογισμός, απρόβλεπτα, αναθεώρηση, ΦΠΑ.','N4412/156/2',true,true),
('S19_APE',3,'epitropi','Σύνταξη Π.Κ.Τ.Μ.Ν.Ε. για νέες εργασίες','Τριμελής επιτροπή με συμμετοχή του επιβλέποντος· ιεράρχηση πηγών τιμών και εφαρμογή τεκμαρτής έκπτωσης.','N4412/156/5',false,true),
('S19_APE',4,'dieuthynousa_ypiresia','Έλεγχος ορίων','50% σωρευτικά, 9%/15% απρόβλεπτα, 20% ανά ομάδα και 10% συνολικά για επί έλασσον.','N4412/156/3c',true,false),
('S19_APE',5,'techniko_symvoulio','Γνωμοδότηση Τεχνικού Συμβουλίου','Υποχρεωτική για συμπληρωματική σύμβαση και για χρήση επί έλασσον δαπανών.','N4412/156/1e',false,true),
('S19_APE',6,'anadochos','Υπογραφή ΑΠΕ (ανεπιφύλακτα ή με επιφύλαξη)','Σε άρνηση υπογραφής, κοινοποιείται κατ'' άρθρο 143.','N4412/156/7',true,true),
('S19_APE',7,'proistameni_arxi','Έγκριση ΑΠΕ','Λαμβάνονται υπόψη οι τυχόν επιφυλάξεις/ενστάσεις του αναδόχου.','N4412/156/7',true,true),

-- S20-S23 --------------------------------------------------------------
('S20_PARATASEIS',1,'anadochos','Υποβολή αιτήματος παράτασης','ΠΡΙΝ τη λήξη της ισχύουσας προθεσμίας, με τεκμηρίωση.','N4412/147/5',true,true),
('S20_PARATASEIS',2,'epivlepon','Εισήγηση με καταλογισμό ευθύνης','Προσδιορισμός υπαιτιότητας — άλλως βαρύνει αποκλειστικά τον ανάδοχο.','N4412/147/6',true,true),
('S20_PARATASEIS',3,'proistameni_arxi','Απόφαση εντός 30 ημερών','Άπρακτη πάροδος = σιωπηρή αποδοχή με αναδρομική ισχύ.','N4412/147/5',true,true),
('S21_ANWTERA_BIA',1,'anadochos','Αίτημα αναστολής εντός 10 ημερών','Από την επέλευση του γεγονότος ανωτέρας βίας.','N4412/147/7',true,true),
('S21_ANWTERA_BIA',2,'dieuthynousa_ypiresia','Απόφαση εντός 10 ημερών','Άπρακτη πάροδος = αποδοχή· τήρηση ανώτατου ορίου αναστολής.','N4412/147/7',true,true),
('S22_POINIKES',1,'epivlepon','Υπολογισμός ρητρών','Υπέρβαση προθεσμιών, παράλειψη ημερολογίου, καθυστέρηση τελικής επιμέτρησης.','N4412/148',true,true),
('S22_POINIKES',2,'dieuthynousa_ypiresia','Απόφαση επιβολής & κοινοποίηση','Παρακράτηση στον αμέσως επόμενο λογαριασμό.','N4412/148',true,true),
('S23_ENSTASEIS',1,'anadochos','Άσκηση ένστασης εντός 15 ημερών','Ανατρεπτική προθεσμία από την κοινοποίηση της πράξης.','N4412/174',true,true),
('S23_ENSTASEIS',2,'dieuthynousa_ypiresia','Διαβίβαση με αιτιολογημένη εισήγηση','Προς την Προϊσταμένη Αρχή και το Τεχνικό Συμβούλιο.','N4412/174',true,true),
('S23_ENSTASEIS',3,'proistameni_arxi','Απόφαση εντός 60 ημερών','Άπρακτη πάροδος = σιωπηρή αποδοχή της γνωμοδότησης.','N4412/174',true,true),

-- S24-S26 ΠΕΡΑΙΩΣΗ -----------------------------------------------------
('S24_DHLWSH_PERAIWSHS',1,'anadochos','Δήλωση περαίωσης εργασιών','Δύναται να υποβληθεί και πριν τη λήξη, εφόσον οι εργασίες έχουν ολοκληρωθεί.','N4412/168/2',true,true),
('S24_DHLWSH_PERAIWSHS',2,'epivlepon','Επιβεβαίωση ολοκλήρωσης συμβατικών δοκιμών','Καταγραφή αποτελεσμάτων.','N4412/168/1',true,true),
('S25_EKTHESI_EPIVL',1,'epivlepon','Σύνταξη έκθεσης περαίωσης εντός 30 ημερών','Δήλωση αν οι εργασίες περατώθηκαν και αν υπάρχουν ελαττώματα.','N4412/168/1',true,true),
('S25_EKTHESI_EPIVL',2,'epivlepon','Χαρακτηρισμός ελαττωμάτων','Επουσιώδη (δεν θίγουν λειτουργικότητα/ασφάλεια/αδειοδότηση) ή ουσιώδη.','N4412/168/1',true,false),
('S25_EKTHESI_EPIVL',3,'dieuthynousa_ypiresia','Εντολή αποκατάστασης επουσιωδών ελαττωμάτων','Τάσσεται εύλογη προθεσμία· ο χρόνος αποκατάστασης δεν προσμετράται.','N4412/168/3',false,true),
('S26_BEBAIWSH',1,'dieuthynousa_ypiresia','Έκδοση Βεβαίωσης Περάτωσης εντός 10 ημερών','Από τη λήψη της έκθεσης του επιβλέποντος.','N4412/168/2',true,true),
('S26_BEBAIWSH',2,'dieuthynousa_ypiresia','Αναγραφή πραγματικής ημερομηνίας περαίωσης','Χωρίς προσμέτρηση του χρόνου αποκατάστασης επουσιωδών ελαττωμάτων.','N4412/168/3',true,false),
('S26_BEBAIWSH',3,'dieuthynousa_ypiresia','Κοινοποίηση στον ανάδοχο','Αφετηρία του χρόνου υποχρεωτικής συντήρησης.','N4412/143',true,true),

-- S27-S28 --------------------------------------------------------------
('S27_TELIKH_EPIM',1,'anadochos','Υποβολή τελικής επιμέτρησης εντός 2 μηνών','Ανακεφαλαίωση όλων των επιμετρήσεων του έργου.','N4412/151/9',true,true),
('S27_TELIKH_EPIM',2,'epivlepon','Έκθεση επί της τελικής επιμέτρησης εντός 2 μηνών','Έλεγχος και εισήγηση έγκρισης.','N4412/151/9',true,true),
('S27_TELIKH_EPIM',3,'dieuthynousa_ypiresia','Έγκριση τελικής επιμέτρησης εντός 2 μηνών','Πράξη έγκρισης — προϋπόθεση για τη μείωση της εγγύησης.','N4412/151/9',true,true),
('S27_TELIKH_EPIM',4,'dieuthynousa_ypiresia','Επιβολή ρήτρας καθυστέρησης 2‰/μήνα','Έως έξι (6) μήνες· δυνατότητα σύνταξης από την υπηρεσία σε βάρος του αναδόχου.','N4412/151/10',false,true),
('S28_MEIWSH_EGG',1,'dieuthynousa_ypiresia','Έκδοση πράξης μείωσης εγγύησης κατά 70%','Αμέσως μετά την έγκριση της τελικής επιμέτρησης.','N4412/72/14b',true,true),
('S28_MEIWSH_EGG',2,'dieuthynousa_ypiresia','Ενημέρωση εκδότη εγγυητικής','Κοινοποίηση της πράξης μείωσης.','N4412/72/14b',true,true),

-- S29-S34 ΣΥΝΤΗΡΗΣΗ & ΠΑΡΑΛΑΒΗ ---------------------------------------
('S29_SYNTHRHSH',1,'anadochos','Τακτικές επιθεωρήσεις & συντήρηση','Διατήρηση του έργου σε ικανοποιητική κατάσταση καθ'' όλη τη διάρκεια.','N4412/171',true,false),
('S29_SYNTHRHSH',2,'anadochos','Αποκατάσταση ελαττωμάτων κατασκευής','Ελαττώματα οφειλόμενα σε πλημμελή εκτέλεση.','N4412/171',true,true),
('S29_SYNTHRHSH',3,'epivlepon','Περιοδικοί έλεγχοι συντήρησης','Καταγραφή ευρημάτων· επί παράλειψης εφαρμόζεται το άρθρο 159.','N4412/159',true,true),
('S30_EPITROPH',1,'proistameni_arxi','Ορισμός πενταμελούς επιτροπής παραλαβής','Τρεις τεχνικοί υπάλληλοι και δύο εκπρόσωποι ΤΕΕ (ή ΓΕΩΤΕΕ σε γεωτεχνικά έργα).','N4412/172',true,true),
('S30_EPITROPH',2,'proistameni_arxi','Ορισμός τουλάχιστον 3 μήνες πριν τη λήξη συντήρησης','Αποφυγή αυτοδίκαιης παραλαβής.','N4412/172',true,false),
('S30_EPITROPH',3,'anadochos','Ορισμός παρατηρητή (χωρίς δικαίωμα ψήφου)','Προαιρετικό δικαίωμα του αναδόχου.','N4412/172',false,false),
('S31_PARALABH',1,'epitropi','Διενέργεια παραλαβής εντός 3 μηνών','Ποσοτικός και ποιοτικός έλεγχος, δοκιμές.','N4412/172',true,true),
('S31_PARALABH',2,'epitropi','Σύνταξη & υπογραφή πρωτοκόλλου','Υπογράφεται από όλα τα μέλη, τον επιβλέποντα και τον ανάδοχο.','N4412/172',true,true),
('S31_PARALABH',3,'proistameni_arxi','Έγκριση πρωτοκόλλου παραλαβής','Ή έκδοση βεβαιωτικής πράξης επί αυτοδίκαιης παραλαβής.','N4412/172',true,true),
('S32_TELIKOS_LOG',1,'anadochos','Υποβολή τελικού λογαριασμού','Μετά την παραλαβή και την έγκριση του πρωτοκόλλου.','N4412/152',true,true),
('S32_TELIKOS_LOG',2,'dieuthynousa_ypiresia','Έλεγχος & έγκριση εντός 1 μηνός','Εκκαθάριση των εκατέρωθεν απαιτήσεων από τη σύμβαση εκτέλεσης.','N4412/152',true,true),
('S33_APODESMEVSH',1,'dieuthynousa_ypiresia','Επιστροφή εγγυήσεων καλής εκτέλεσης','Μετά την έγκριση του πρωτοκόλλου παραλαβής και του τελικού λογαριασμού.','N4412/72/14b',true,true),
('S33_APODESMEVSH',2,'dieuthynousa_ypiresia','Επιστροφή εγγύησης προκαταβολής','Εφόσον έχει αποσβεστεί πλήρως η προκαταβολή.','N4412/72/7',false,true),
('S34_MHTRWO',1,'anadochos','Παράδοση Μητρώου Έργου','Σχέδια «as built», φωτογραφικό υλικό αφανών εργασιών, ψηφιακή τεκμηρίωση σταδίων.','N4412/170',true,true),
('S34_MHTRWO',2,'anadochos','Εγχειρίδια λειτουργίας & συντήρησης','Οδηγίες και προϋπολογισμός συντήρησης.','N4412/172',true,true),
('S34_MHTRWO',3,'dieuthynousa_ypiresia','Οριστική αρχειοθέτηση φακέλου','Πλήρης ψηφιακός φάκελος με όλα τα έγγραφα και τις πράξεις.','N4412/170',true,false)
on conflict (stage_code, ordinal) do nothing;

-- ---------------------------------------------------------------------
-- ΥΠΟΧΡΕΩΤΙΚΑ ΠΑΡΑΓΟΜΕΝΑ ΕΓΓΡΑΦΑ ΑΝΑ ΣΤΑΔΙΟ
-- (τα doc_code αντιστοιχίζονται στα πρότυπα .docx/.xlsx της Υπηρεσίας)
-- ---------------------------------------------------------------------
insert into public.stage_documents (stage_code, doc_code, title, produced_by, is_mandatory, legal_ref_id) values
('S01_ORISMOS','APOFASI_ORISMOU','Απόφαση ορισμού επιβλέποντος','dieuthynousa_ypiresia',true,'N4412/136/2'),
('S02_GNOSTOPOIHSH','GNOSTOPOIHSH_EPIVL','Έγγραφο γνωστοποίησης επίβλεψης','dieuthynousa_ypiresia',true,'N4412/143'),
('S06_XRONODIAGRAMMA','XRONODIAGRAMMA','Χρονοδιάγραμμα κατασκευής','anadochos',true,'N4412/145/1'),
('S06_XRONODIAGRAMMA','EGKRISI_XRONOD','Απόφαση έγκρισης χρονοδιαγράμματος','dieuthynousa_ypiresia',true,'N4412/145/2'),
('S07_ORGANOGRAMMA','ORGANOGRAMMA','Οργανόγραμμα εργοταξίου','anadochos',true,'N4412/145/4'),
('S08_PPE','PPE','Πρόγραμμα Ποιότητας Έργου','anadochos',true,'N4412/158'),
('S09_SAY_FAY','SAY_FAY','ΣΑΥ - ΦΑΥ','anadochos',true,'PD305/1996'),
('S10_EGKATASTASH','PRWT_PARADOSIS_XWROU','Πρωτόκολλο παράδοσης χώρου εργασιών','dieuthynousa_ypiresia',true,'N4412/137'),
('S12_HMEROLOGIO','HMEROLOGIO','Ημερολόγιο έργου','anadochos',true,'N4412/146'),
('S15_PPAE','PPAE','Πρωτόκολλο / έκθεση παραλαβής αφανών εργασιών','epivlepon',true,'N4412/151/7'),
('S16_EPIMETRHSEIS','ANAL_EPIMETRISI','Αναλυτική επιμέτρηση','anadochos',true,'N4412/151/2'),
('S16_EPIMETRHSEIS','PRAKTIKO_DEIGM_ELEGXOU','Πρακτικό δειγματοληπτικού ελέγχου επιμετρήσεων','dieuthynousa_ypiresia',true,'N4412/151/3'),
('S17_LOGARIASMOI','LOGARIASMOS','Λογαριασμός - Πιστοποίηση','anadochos',true,'N4412/152'),
('S17_LOGARIASMOI','ANAK_PINAKAS_EPIM','Ανακεφαλαιωτικός συνοπτικός πίνακας επιμετρήσεων','anadochos',true,'N4412/152'),
('S18_TRIMHNIAIES','TRIMHNIAIA_EKTHESI','Τριμηνιαία έκθεση πορείας έργου','dieuthynousa_ypiresia',true,'N4412/136/10'),
('S19_APE','APE','Ανακεφαλαιωτικός Πίνακας Εργασιών','dieuthynousa_ypiresia',true,'N4412/156/2'),
('S19_APE','PKTMNE','Πρωτόκολλο Κανονισμού Τιμών Μονάδος Νέων Εργασιών','epitropi',false,'N4412/156/5'),
('S20_PARATASEIS','APOFASI_PARATASIS','Απόφαση παράτασης προθεσμίας','proistameni_arxi',true,'N4412/147/5'),
('S25_EKTHESI_EPIVL','EKTHESI_PERAIWSHS','Έκθεση επιβλέποντος περί περαίωσης','epivlepon',true,'N4412/168/1'),
('S26_BEBAIWSH','BEBAIOSI_PERATOSIS','Βεβαίωση Περάτωσης Εργασιών','dieuthynousa_ypiresia',true,'N4412/168/2'),
('S27_TELIKH_EPIM','TELIKH_EPIMETRISI','Τελική επιμέτρηση','anadochos',true,'N4412/151/9'),
('S27_TELIKH_EPIM','EGKRISI_TELIKHS_EPIM','Πράξη έγκρισης τελικής επιμέτρησης','dieuthynousa_ypiresia',true,'N4412/151/9'),
('S28_MEIWSH_EGG','PRAXH_MEIWSHS_EGG','Πράξη μείωσης εγγύησης καλής εκτέλεσης κατά 70%','dieuthynousa_ypiresia',true,'N4412/72/14b'),
('S30_EPITROPH','APOFASI_EPITROPHS','Απόφαση ορισμού επιτροπής παραλαβής','proistameni_arxi',true,'N4412/172'),
('S31_PARALABH','PRWT_PARALAVIS','Πρωτόκολλο παραλαβής έργου','epitropi',true,'N4412/172'),
('S32_TELIKOS_LOG','TELIKOS_LOGARIASMOS','Τελικός λογαριασμός','anadochos',true,'N4412/152'),
('S33_APODESMEVSH','PRAXH_APODESMEVSHS','Πράξη επιστροφής εγγυητικών επιστολών','dieuthynousa_ypiresia',true,'N4412/72/14b'),
('S34_MHTRWO','MHTRWO_ERGOU','Μητρώο Έργου','anadochos',true,'N4412/170')
on conflict (stage_code, doc_code) do nothing;

-- >>>>>>>>>>>>>>>>>>>> 0015_auth_grants_rpc.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0015_auth_grants_rpc.sql — Σύνδεση με το Supabase Auth, RPC, δικαιώματα
-- ---------------------------------------------------------------------
--  • ξένο κλειδί profiles → auth.users
--  • αυτόματη δημιουργία profile σε κάθε νέο χρήστη
--  • security_invoker στα views (ώστε να εφαρμόζονται τα RLS του καλούντος)
--  • δημόσια περιτυλίγματα (RPC) των συναρτήσεων του σχήματος app
--  • grants σε authenticated / service_role
-- =====================================================================

-- ---- 1. profiles ↔ auth.users --------------------------------------
alter table public.profiles
  drop constraint if exists profiles_auth_fk;
alter table public.profiles
  add constraint profiles_auth_fk
  foreign key (id) references auth.users (id) on delete cascade;

create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare v_org uuid;
begin
  select id into v_org from public.organizations order by created_at limit 1;
  if v_org is null then return new; end if;
  insert into public.profiles (id, org_id, full_name, email, specialty)
  values (new.id, v_org,
          coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
          new.email, new.raw_user_meta_data->>'specialty')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists trg_handle_new_user on auth.users;
create trigger trg_handle_new_user
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- ΚΡΙΣΙΜΟ: η υπηρεσία Auth εκτελείται με τον ρόλο supabase_auth_admin. Για να
-- μπορεί να πυροδοτήσει το παραπάνω trigger χρειάζεται USAGE στο σχήμα app και
-- EXECUTE στη συνάρτηση. Χωρίς αυτά, ΚΑΘΕ ενέργεια στον auth.users — ακόμη και
-- απλή σύνδεση — αποτυγχάνει με «Database error querying schema».
--
-- Η συνάρτηση είναι SECURITY DEFINER, οπότε δεν απαιτούνται δικαιώματα στους
-- πίνακες profiles/organizations: αρκεί να μπορεί να κληθεί.
grant usage on schema app to supabase_auth_admin;
grant execute on function app.handle_new_user() to supabase_auth_admin;

-- ---- 2. Views με δικαιώματα του καλούντος ---------------------------
-- Χωρίς security_invoker τα views εκτελούνται με τα δικαιώματα του
-- ιδιοκτήτη τους και παρακάμπτουν τα RLS των υποκείμενων πινάκων.
alter view public.v_ape_limits            set (security_invoker = on);
alter view public.v_deadline_watch        set (security_invoker = on);
alter view public.v_diary_missing_days    set (security_invoker = on);
alter view public.v_hidden_works_alerts   set (security_invoker = on);
alter view public.v_project_financials    set (security_invoker = on);
alter view public.v_stage_board           set (security_invoker = on);

-- ---- 3. RPC περιτυλίγματα ------------------------------------------
-- Το σχήμα app δεν εκτίθεται μέσω PostgREST· εκθέτουμε μόνο ό,τι
-- χρειάζεται το front-end, με ρητό έλεγχο δικαιωμάτων.
create or replace function public.stage_blockers(p_project_stage_id uuid)
returns table (code text, message text, severity text, legal_ref text)
language sql
stable
security definer
set search_path = public, app
as $$
  select b.code, b.message, b.severity, b.legal_ref
  from app.stage_blockers(p_project_stage_id) b
  where exists (select 1 from public.project_stages ps
                where ps.id = p_project_stage_id and app.can_read_project(ps.project_id));
$$;

comment on function public.stage_blockers(uuid) is
  'Εμπόδια μετάβασης ενός σταδίου. SECURITY DEFINER με εσωτερικό έλεγχο app.can_read_project().';

create or replace function public.instantiate_workflow(p_project_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if not app.can_approve(p_project_id) and not app.can_supervise(p_project_id) then
    raise exception 'Δεν έχετε δικαίωμα δημιουργίας ροής για το έργο αυτό.';
  end if;
  return app.instantiate_workflow(p_project_id);
end $$;

comment on function public.instantiate_workflow(uuid) is
  'Δημιουργία στιγμιοτύπου ροής εργασιών για έργο. SECURITY DEFINER με εσωτερικό έλεγχο app.can_approve()/can_supervise().';

-- ---- 4. Δικαιώματα --------------------------------------------------
grant usage on schema public to authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all sequences in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;

revoke all on function public.stage_blockers(uuid)       from public, anon;
revoke all on function public.instantiate_workflow(uuid) from public, anon;
grant execute on function public.stage_blockers(uuid)       to authenticated, service_role;
grant execute on function public.instantiate_workflow(uuid) to authenticated, service_role;
grant execute on function public.required_audit_count(uuid) to authenticated, service_role;

-- Τα καθαρά αναγνωστικά μητρώα είναι ορατά σε κάθε συνδεδεμένο χρήστη.
grant select on public.legal_refs, public.workflow_stages, public.stage_prerequisites,
                public.stage_tasks, public.stage_documents, public.work_groups
  to authenticated;

-- >>>>>>>>>>>>>>>>>>>> 0016_rls_child_tables_hardening.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0016_rls_child_tables_hardening.sql — Θωράκιση RLS θυγατρικών πινάκων
-- ---------------------------------------------------------------------
-- Ο γεννήτορας πολιτικών του 0012 παρακάμπτει τους πίνακες που ΔΕΝ έχουν
-- στήλη project_id. Έτσι δέκα θυγατρικοί πίνακες έμεναν ΧΩΡΙΣ RLS —
-- σοβαρό κενό: μέσω PostgREST ήταν αναγνώσιμοι από κάθε συνδεδεμένο
-- χρήστη. Εδώ ενεργοποιείται RLS και ορίζονται πολιτικές που αντλούν το
-- δικαίωμα από τον γονικό πίνακα.
--
-- Επιπλέον:
--  • καθηλώνεται το search_path σε όλες τις SECURITY DEFINER συναρτήσεις
--    (προστασία από search_path hijacking)
--  • αφαιρείται το δικαίωμα εκτέλεσης των RPC από τον ρόλο anon
--  • οι επεκτάσεις μεταφέρονται εκτός του σχήματος public
-- =====================================================================

-- ---- 1. Ενεργοποίηση RLS -------------------------------------------
alter table public.private_supervisors        enable row level security;
alter table public.new_price_items            enable row level security;
alter table public.schedule_activities        enable row level security;
alter table public.schedule_periods           enable row level security;
alter table public.measurement_audits         enable row level security;
alter table public.measurement_lines          enable row level security;
alter table public.ape_lines                  enable row level security;
alter table public.hidden_work_photos         enable row level security;
alter table public.payment_certificate_lines  enable row level security;
alter table public.project_stage_tasks        enable row level security;

-- ---- 2. Πολιτικές αντλούμενες από τον γονέα -------------------------

-- private_supervisors: μητρώο Ι.Φ.Ε. — ανάγνωση από κάθε χρήστη της
-- υπηρεσίας, μεταβολή μόνο από τη Δ.Υ./Προϊσταμένη Αρχή.
drop policy if exists ps_sel on public.private_supervisors;
create policy ps_sel on public.private_supervisors
  for select using (app.uid() is not null);
drop policy if exists ps_mod on public.private_supervisors;
create policy ps_mod on public.private_supervisors
  for all using (app.is_service_wide());

-- new_price_items → new_price_protocols
drop policy if exists npi_sel on public.new_price_items;
create policy npi_sel on public.new_price_items
  for select using (exists (select 1 from public.new_price_protocols p
    where p.id = new_price_items.protocol_id and app.can_read_project(p.project_id)));
drop policy if exists npi_mod on public.new_price_items;
create policy npi_mod on public.new_price_items
  for all using (exists (select 1 from public.new_price_protocols p
    where p.id = new_price_items.protocol_id
      and (app.can_supervise(p.project_id) or app.can_approve(p.project_id))));

-- schedule_activities → schedules  (ο ανάδοχος συντάσσει το χρονοδιάγραμμα)
drop policy if exists sa_sel on public.schedule_activities;
create policy sa_sel on public.schedule_activities
  for select using (exists (select 1 from public.schedules s
    where s.id = schedule_activities.schedule_id and app.can_read_project(s.project_id)));
drop policy if exists sa_mod on public.schedule_activities;
create policy sa_mod on public.schedule_activities
  for all using (exists (select 1 from public.schedules s
    where s.id = schedule_activities.schedule_id
      and (app.can_supervise(s.project_id) or app.can_approve(s.project_id)
           or app.is_contractor_of(s.project_id))));

-- schedule_periods → schedules
drop policy if exists sp_sel on public.schedule_periods;
create policy sp_sel on public.schedule_periods
  for select using (exists (select 1 from public.schedules s
    where s.id = schedule_periods.schedule_id and app.can_read_project(s.project_id)));
drop policy if exists sp_mod on public.schedule_periods;
create policy sp_mod on public.schedule_periods
  for all using (exists (select 1 from public.schedules s
    where s.id = schedule_periods.schedule_id
      and (app.can_supervise(s.project_id) or app.can_approve(s.project_id)
           or app.is_contractor_of(s.project_id))));

-- measurement_audits → measurements
-- Ο δειγματοληπτικός έλεγχος (άρθρο 151 §3) δεν είναι ορατός στον ανάδοχο.
drop policy if exists ma_sel on public.measurement_audits;
create policy ma_sel on public.measurement_audits
  for select using (exists (select 1 from public.measurements m
    where m.id = measurement_audits.measurement_id
      and (app.can_supervise(m.project_id) or app.can_approve(m.project_id))));
drop policy if exists ma_mod on public.measurement_audits;
create policy ma_mod on public.measurement_audits
  for all using (exists (select 1 from public.measurements m
    where m.id = measurement_audits.measurement_id
      and (app.can_supervise(m.project_id) or app.can_approve(m.project_id))));

-- measurement_lines → measurements
-- Ο ανάδοχος συντάσσει την επιμέτρηση, αλλά μόνο όσο είναι σε 'draft'.
drop policy if exists ml_sel on public.measurement_lines;
create policy ml_sel on public.measurement_lines
  for select using (exists (select 1 from public.measurements m
    where m.id = measurement_lines.measurement_id and app.can_read_project(m.project_id)));
drop policy if exists ml_mod on public.measurement_lines;
create policy ml_mod on public.measurement_lines
  for all using (exists (select 1 from public.measurements m
    where m.id = measurement_lines.measurement_id
      and (app.can_supervise(m.project_id) or app.can_approve(m.project_id)
           or (app.is_contractor_of(m.project_id) and m.status = 'draft'))));

-- ape_lines → ape
drop policy if exists al_sel on public.ape_lines;
create policy al_sel on public.ape_lines
  for select using (exists (select 1 from public.ape a
    where a.id = ape_lines.ape_id and app.can_read_project(a.project_id)));
drop policy if exists al_mod on public.ape_lines;
create policy al_mod on public.ape_lines
  for all using (exists (select 1 from public.ape a
    where a.id = ape_lines.ape_id
      and (app.can_supervise(a.project_id) or app.can_approve(a.project_id))));

-- hidden_work_photos → hidden_work_notices
-- Ο ανάδοχος ανεβάζει τις ψηφιακές φωτογραφίες (άρθρο 151 §7).
drop policy if exists hwp_sel on public.hidden_work_photos;
create policy hwp_sel on public.hidden_work_photos
  for select using (exists (select 1 from public.hidden_work_notices h
    where h.id = hidden_work_photos.notice_id and app.can_read_project(h.project_id)));
drop policy if exists hwp_mod on public.hidden_work_photos;
create policy hwp_mod on public.hidden_work_photos
  for all using (exists (select 1 from public.hidden_work_notices h
    where h.id = hidden_work_photos.notice_id
      and (app.can_supervise(h.project_id) or app.can_approve(h.project_id)
           or app.is_contractor_of(h.project_id))));

-- payment_certificate_lines → payment_certificates
drop policy if exists pcl_sel on public.payment_certificate_lines;
create policy pcl_sel on public.payment_certificate_lines
  for select using (exists (select 1 from public.payment_certificates p
    where p.id = payment_certificate_lines.certificate_id and app.can_read_project(p.project_id)));
drop policy if exists pcl_mod on public.payment_certificate_lines;
create policy pcl_mod on public.payment_certificate_lines
  for all using (exists (select 1 from public.payment_certificates p
    where p.id = payment_certificate_lines.certificate_id
      and (app.can_supervise(p.project_id) or app.can_approve(p.project_id)
           or (app.is_contractor_of(p.project_id) and p.status = 'draft'))));

-- project_stage_tasks → project_stages
-- Οι εσωτερικές εργασίες του οδηγού δεν είναι ορατές στον ανάδοχο.
drop policy if exists pst_sel on public.project_stage_tasks;
create policy pst_sel on public.project_stage_tasks
  for select using (exists (select 1 from public.project_stages ps
    where ps.id = project_stage_tasks.project_stage_id
      and (app.can_supervise(ps.project_id) or app.can_approve(ps.project_id))));
drop policy if exists pst_mod on public.project_stage_tasks;
create policy pst_mod on public.project_stage_tasks
  for all using (exists (select 1 from public.project_stages ps
    where ps.id = project_stage_tasks.project_stage_id
      and (app.can_supervise(ps.project_id) or app.can_approve(ps.project_id))));

-- ---- 3. Καθήλωση search_path στις SECURITY DEFINER συναρτήσεις ------
do $$
declare r record;
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('app','public')
       and p.prokind = 'f'
       and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c
                        where c like 'search_path=%')
  loop
    execute format('alter function %I.%I(%s) set search_path = public, app',
                   r.nspname, r.proname, r.args);
  end loop;
end $$;

-- ---- 4. Αφαίρεση δικαιωμάτων από τον ρόλο anon ----------------------
revoke execute on function public.stage_blockers(uuid)       from anon;
revoke execute on function public.instantiate_workflow(uuid) from anon;
revoke execute on function public.required_audit_count(uuid) from anon;
revoke all on all tables in schema public from anon;

-- ---- 5. Επεκτάσεις εκτός του σχήματος public ------------------------
create schema if not exists extensions;
alter extension btree_gist set schema extensions;
alter extension unaccent   set schema extensions;

-- >>>>>>>>>>>>>>>>>>>> 0017_storage_and_org.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0017_storage_and_org.sql — Φορέας, αποθηκευτικοί κάδοι, πρωτόκολλο
-- ---------------------------------------------------------------------
--  • εγγραφή του φορέα (Δήμος Ρόδου) με στοιχεία επιστολόχαρτου
--  • τρεις κάδοι Supabase Storage: templates / documents / photos
--  • πολιτικές πρόσβασης στα αντικείμενα κάθε κάδου
--  • μετρητής αριθμού πρωτοκόλλου ανά φορέα και έτος
-- =====================================================================

-- ---- 1. Φορέας ------------------------------------------------------
insert into public.organizations (id, name, unit, afm, address, phone, email, letterhead_html)
values ('00000000-0000-0000-0000-0000000000d1',
        'Δήμος Ρόδου',
        'Διεύθυνση Τεχνικών Έργων & Υποδομών',
        '997654321',
        'Πλατεία Ελευθερίας 1, 851 00 Ρόδος',
        '2241361300',
        'texniki@rhodes.gr',
        '<div class="letterhead"><div class="emblem">ΕΛΛΗΝΙΚΗ ΔΗΜΟΚΡΑΤΙΑ</div>' ||
        '<div class="org">ΔΗΜΟΣ ΡΟΔΟΥ</div>' ||
        '<div class="unit">Δ/ΝΣΗ ΤΕΧΝΙΚΩΝ ΕΡΓΩΝ &amp; ΥΠΟΔΟΜΩΝ</div></div>')
on conflict (id) do nothing;

-- ---- 2. Κάδοι αποθήκευσης ------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('templates', 'templates', false, 20971520, array[
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'text/html']),
  ('documents', 'documents', false, 52428800, null),
  ('photos',    'photos',    false, 26214400, array[
      'image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;

-- ---- 3. Πολιτικές αντικειμένων --------------------------------------
-- templates: ανάγνωση από κάθε συνδεδεμένο χρήστη, ανέβασμα/τροποποίηση
-- μόνο από τη Δ.Υ./Προϊσταμένη Αρχή (τα πρότυπα είναι υπηρεσιακά έντυπα).
drop policy if exists templates_read   on storage.objects;
create policy templates_read on storage.objects
  for select using (bucket_id = 'templates' and app.uid() is not null);

drop policy if exists templates_write  on storage.objects;
create policy templates_write on storage.objects
  for insert with check (bucket_id = 'templates' and app.is_service_wide());

drop policy if exists templates_update on storage.objects;
create policy templates_update on storage.objects
  for update using (bucket_id = 'templates' and app.is_service_wide());

-- documents: κάθε παραγόμενο έγγραφο ακολουθεί τα δικαιώματα του έργου
-- του, μέσω της αντίστοιχης εγγραφής public.documents.
drop policy if exists documents_read  on storage.objects;
create policy documents_read on storage.objects
  for select using (
    bucket_id = 'documents'
    and exists (select 1 from public.documents d
                 where d.storage_path = storage.objects.name
                   and app.can_read_project(d.project_id)));

drop policy if exists documents_write on storage.objects;
create policy documents_write on storage.objects
  for insert with check (bucket_id = 'documents' and app.uid() is not null);

-- photos: ψηφιακές φωτογραφίες αφανών εργασιών (άρθρο 151 §7)
drop policy if exists photos_read  on storage.objects;
create policy photos_read on storage.objects
  for select using (bucket_id = 'photos' and app.uid() is not null);

drop policy if exists photos_write on storage.objects;
create policy photos_write on storage.objects
  for insert with check (bucket_id = 'photos' and app.uid() is not null);

-- ---- 4. Μετρητής πρωτοκόλλου ----------------------------------------
create table if not exists public.protocol_counters (
  org_id   uuid    not null references public.organizations(id) on delete cascade,
  year     integer not null,
  last_no  integer not null default 0,
  primary key (org_id, year)
);

alter table public.protocol_counters enable row level security;

drop policy if exists protocol_counters_sel on public.protocol_counters;
create policy protocol_counters_sel on public.protocol_counters
  for select using (org_id = app.my_org());

create or replace function public.next_protocol_no(p_org uuid)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare v_year integer := extract(year from current_date)::int; v_no integer;
begin
  -- Ο αριθμός πρωτοκόλλου αποδίδεται ΜΟΝΟ για τον φορέα του χρήστη· έτσι
  -- η συνάρτηση δεν μπορεί να χρησιμοποιηθεί για κατανάλωση της σειράς
  -- πρωτοκόλλου άλλου φορέα.
  if p_org is distinct from app.my_org() then
    raise exception 'Δεν έχετε δικαίωμα απόδοσης αριθμού πρωτοκόλλου για τον φορέα αυτόν.';
  end if;

  insert into public.protocol_counters (org_id, year, last_no)
  values (p_org, v_year, 1)
  on conflict (org_id, year) do update set last_no = public.protocol_counters.last_no + 1
  returning last_no into v_no;
  return v_no;
end $$;

comment on function public.next_protocol_no(uuid) is
  'Επόμενος αύξων αριθμός πρωτοκόλλου του φορέα για το τρέχον έτος (ατομική πράξη).';

revoke all on function public.next_protocol_no(uuid) from public, anon;
grant execute on function public.next_protocol_no(uuid) to authenticated, service_role;

-- >>>>>>>>>>>>>>>>>>>> 0018_template_bodies_and_seed.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0018_template_bodies_and_seed.sql — Ενσωματωμένα πρότυπα εγγράφων
-- ---------------------------------------------------------------------
-- Η Υπηρεσία μπορεί να ανεβάσει τα δικά της .docx στον κάδο «templates».
-- Μέχρι τότε, κάθε πρότυπο μπορεί να φέρει ενσωματωμένο σώμα HTML, ώστε
-- η εφαρμογή να παράγει άμεσα διοικητικά ορθά έγγραφα.
--
-- Τα κείμενα είναι συντεταγμένα κατά τα πρότυπα της διοικητικής πρακτικής
-- (σκεπτικό «Έχοντας υπόψη», αποφασιστικό, κοινοποίηση) και φέρουν ρητή
-- παραπομπή στη διάταξη που τα θεμελιώνει.
-- =====================================================================

alter table public.document_templates
  add column if not exists body_html        text,
  add column if not exists signatories      jsonb,
  add column if not exists subject_template text;

alter table public.document_templates
  alter column storage_path drop not null;

comment on column public.document_templates.body_html is
  'Ενσωματωμένο σώμα HTML με placeholders {{diadromi.pediou}}. Χρησιμοποιείται όταν δεν υπάρχει αρχείο .docx στο storage_path.';
comment on column public.document_templates.signatories is
  'Πίνακας υπογραφόντων: [{label, name, capacity}] — τα name/capacity δέχονται placeholders. '
  'Το label (π.χ. «Ο Προϊστάμενος…») προσαρμόζεται από την Υπηρεσία στο γένος και τον τίτλο του υπογράφοντος.';

-- ---- Πρότυπα --------------------------------------------------------
insert into public.document_templates
  (org_id, doc_code, title, category, file_type, storage_path, stage_code,
   legal_ref_id, numbering_scheme, requires_ada, subject_template, signatories, body_html)
values

-- 1. Απόφαση ορισμού επιβλέποντος — άρθρο 136 §2 -----------------------
('00000000-0000-0000-0000-0000000000d1', 'APOFASI_ORISMOU',
 'Απόφαση ορισμού επιβλέποντος', 'orismos', 'html', null, 'S01_ORISMOS',
 'N4412/136/2', '{ΕΤΟΣ}/{ΑΑ}', true,
 'Ορισμός επιβλέποντος μηχανικού του έργου «{{ergo.titlos}}»',
 '[{"label":"Ο Προϊστάμενος της Διευθύνουσας Υπηρεσίας","name":"{{proistamenos.full_name}}","capacity":"{{proistamenos.specialty}}"}]'::jsonb,
$T$<p class="intro">Έχοντας υπόψη:</p>
<ol class="grounds">
  <li>Τις διατάξεις του άρθρου 136 του ν. 4412/2016, όπως αντικαταστάθηκε με το άρθρο 57 του ν. 4782/2021, περί διοίκησης, παρακολούθησης και επίβλεψης δημοσίων έργων.</li>
  <li>Τη με αριθμό {{symvasi.arithmos}} σύμβαση εκτέλεσης του έργου, που υπογράφηκε την {{symvasi.imerominia_ypografis}}.</li>
  <li>Τις υπηρεσιακές ανάγκες και τα προσόντα του τεχνικού προσωπικού της Υπηρεσίας.</li>
</ol>
<p class="declare">Α Π Ο Φ Α Σ Ι Ζ Ο Υ Μ Ε</p>
<p>Ορίζουμε ως <strong>επιβλέποντα</strong> του έργου <strong>«{{ergo.titlos}}»</strong>, αναδόχου {{anadoxos.epwnymia}}, τον/την <strong>{{epivlepon.full_name}}</strong>, {{epivlepon.specialty}}, υπάλληλο της Διεύθυνσης Τεχνικών Έργων &amp; Υποδομών του Δήμου Ρόδου.</p>
<p>Ο επιβλέπων ασκεί τα καθήκοντα που προβλέπονται στα άρθρα 136 επ. του ν. 4412/2016 και ιδίως: την παρακολούθηση και τον έλεγχο της ποιότητας και ποσότητας των εργασιών, την τήρηση των όρων της σύμβασης, τον έλεγχο του ημερολογίου του έργου (άρθρο 146), τον έλεγχο των αφανών εργασιών πριν από την επικάλυψή τους (άρθρο 151 §7), τον έλεγχο και τη θεώρηση των επιμετρήσεων και των λογαριασμών, καθώς και τη σύνταξη των προβλεπόμενων εκθέσεων.</p>
<p class="note">Η παρούσα κοινοποιείται στον ανάδοχο σύμφωνα με το άρθρο 143 του ν. 4412/2016 και αναρτάται στο πρόγραμμα ΔΙΑΥΓΕΙΑ.</p>$T$),

-- 2. Έγκριση χρονοδιαγράμματος — άρθρο 145 §2 -------------------------
('00000000-0000-0000-0000-0000000000d1', 'EGKRISI_XRONOD',
 'Απόφαση έγκρισης χρονοδιαγράμματος', 'xronodiagramma', 'html', null, 'S06_XRONODIAGRAMMA',
 'N4412/145/2', '{ΕΤΟΣ}/{ΑΑ}', true,
 'Έγκριση χρονοδιαγράμματος κατασκευής του έργου «{{ergo.titlos}}»',
 '[{"label":"Ο Προϊστάμενος της Διευθύνουσας Υπηρεσίας","name":"{{proistamenos.full_name}}","capacity":"{{proistamenos.specialty}}"}]'::jsonb,
$T$<p class="intro">Έχοντας υπόψη:</p>
<ol class="grounds">
  <li>Το άρθρο 145 του ν. 4412/2016, όπως αντικαταστάθηκε με το άρθρο 65 του ν. 4782/2021.</li>
  <li>Τη με αριθμό {{symvasi.arithmos}} σύμβαση εκτέλεσης του έργου, που υπογράφηκε την {{symvasi.imerominia_ypografis}}, με συνολική προθεσμία {{symvasi.prothesmia_imeres}} ημερών.</li>
  <li>Το με ημερομηνία {{xronodiagramma.imerominia_ypovolis}} υποβληθέν από τον ανάδοχο χρονοδιάγραμμα κατασκευής.</li>
  <li>Την εισήγηση του επιβλέποντος μηχανικού επί της αλληλουχίας των εργασιών, της μεθοδολογίας κατασκευής και της τήρησης των συμβατικών οροσήμων.</li>
</ol>
<p class="declare">Α Π Ο Φ Α Σ Ι Ζ Ο Υ Μ Ε</p>
<p>Εγκρίνουμε το χρονοδιάγραμμα κατασκευής του έργου <strong>«{{ergo.titlos}}»</strong>, αναδόχου <strong>{{anadoxos.epwnymia}}</strong>, με λήξη της συνολικής προθεσμίας την <strong>{{symvasi.lixi_prothesmias}}</strong>.</p>
<p>Το εγκεκριμένο χρονοδιάγραμμα αποτελεί συμβατικό στοιχείο του έργου. Κάθε αναπροσαρμογή του εγκρίνεται όταν μεταβάλλονται οι προθεσμίες, το αντικείμενο ή οι ποσότητες των εργασιών.</p>
<p class="note">Η παρούσα κοινοποιείται στον ανάδοχο σύμφωνα με το άρθρο 143 του ν. 4412/2016.</p>$T$),

-- 3. Έκθεση Παραλαβής Αφανών Εργασιών — άρθρο 151 §7 -------------------
('00000000-0000-0000-0000-0000000000d1', 'PPAE',
 'Έκθεση Παραλαβής Αφανών Εργασιών (Π.Π.Α.Ε.)', 'epimetrisi', 'html', null, 'S15_PPAE',
 'N4412/151/7', '{ΕΤΟΣ}/{ΑΑ}', false,
 'Έκθεση παραλαβής αφανών εργασιών Νο {{afaneis.aa}} — «{{ergo.titlos}}»',
 '[{"label":"Ο Επιβλέπων Μηχανικός","name":"{{epivlepon.full_name}}","capacity":"{{epivlepon.specialty}}"},
   {"label":"Για τον Ανάδοχο","name":"{{anadoxos.epwnymia}}","capacity":"Ο νόμιμος εκπρόσωπος"}]'::jsonb,
$T$<p>Σήμερα, {{afaneis.imerominia_elegxou_pliris}}, ο υπογράφων επιβλέπων μηχανικός του έργου <strong>«{{ergo.titlos}}»</strong>, ύστερα από τη με ημερομηνία {{afaneis.imerominia_prosklisis}} πρόσκληση του αναδόχου <strong>{{anadoxos.epwnymia}}</strong>, μετέβη επιτόπου και προέβη στον έλεγχο των κατωτέρω αφανών εργασιών <strong>πριν από την επικάλυψή τους</strong>, σύμφωνα με την παρ. 7 του άρθρου 151 του ν. 4412/2016.</p>
<table class="data">
  <tr><th>Περιγραφή εργασιών</th><td>{{afaneis.perigrafi}}</td></tr>
  <tr><th>Θέση</th><td>{{afaneis.thesi}}</td></tr>
  <tr><th>Ημερομηνία πρόσκλησης</th><td>{{afaneis.imerominia_prosklisis}}</td></tr>
  <tr><th>Προθεσμία ελέγχου (3 ημέρες)</th><td>{{afaneis.prothesmia_elegxou}}</td></tr>
  <tr><th>Ημερομηνία ελέγχου</th><td>{{afaneis.imerominia_elegxou}}</td></tr>
  <tr><th>Ψηφιακές φωτογραφίες</th><td>{{afaneis.plithos_fotografion}} — εντάσσονται στο Μητρώο του Έργου</td></tr>
</table>
<p class="declare">Δ Ι Α Π Ι Σ Τ Ω Θ Η Κ Ε</p>
<p>ότι οι ανωτέρω εργασίες εκτελέστηκαν σύμφωνα με τη μελέτη, τις ισχύουσες τεχνικές προδιαγραφές (ΕΤΕΠ/ΕΛΟΤ) και τους όρους της σύμβασης, στις ποσότητες που αναγράφονται στη συνοδευτική διακριτή επιμέτρηση αφανών εργασιών, η οποία συνοδεύεται από δήλωση του αναδόχου περί της αλήθειας των στοιχείων.</p>
<p class="note">Η παρούσα έκθεση συνοδεύει υποχρεωτικά την επιμέτρηση των αφανών εργασιών, δεν έχει εκτελεστό χαρακτήρα και δεν προσβάλλεται αυτοτελώς, παρά μόνο από κοινού με την εγκριτική πράξη της επιμέτρησης, που εκδίδει η Διευθύνουσα Υπηρεσία εντός προθεσμίας τριάντα (30) ημερών από την υποβολή της.</p>$T$),

-- 4. Αναλυτική επιμέτρηση — άρθρο 151 §2 ------------------------------
('00000000-0000-0000-0000-0000000000d1', 'ANAL_EPIMETRISI',
 'Αναλυτική επιμέτρηση', 'epimetrisi', 'html', null, 'S16_EPIMETRHSEIS',
 'N4412/151/2', '{ΕΤΟΣ}/{ΑΑ}', false,
 'Αναλυτική επιμέτρηση Νο {{epimetrisi.aa}} — «{{ergo.titlos}}»',
 '[{"label":"Ο Ανάδοχος","name":"{{anadoxos.epwnymia}}","capacity":"Δήλωση περί της αλήθειας των στοιχείων"},
   {"label":"Ο Επιβλέπων Μηχανικός","name":"{{epivlepon.full_name}}","capacity":"{{epivlepon.specialty}}"}]'::jsonb,
$T$<table class="data">
  <tr><th>Α/Α επιμέτρησης</th><td>{{epimetrisi.aa}}</td><th>Περίοδος</th><td>{{epimetrisi.periodos}}</td></tr>
  <tr><th>Τμήμα έργου</th><td>{{epimetrisi.tmima}}</td><th>Ημ/νία υποβολής</th><td>{{epimetrisi.imerominia_ypovolis}}</td></tr>
</table>
<table class="grid">
  <thead>
    <tr><th>Α/Α</th><th>Άρθρο</th><th>Περιγραφή εργασίας</th><th>Μον.</th>
        <th class="num">Τιμή</th><th class="num">Ποσότητα</th><th class="num">Δαπάνη</th></tr>
  </thead>
  <tbody>
    <tr>{{#each grammes}}<td>{{grammes.aa}}</td><td>{{grammes.arthro}}</td><td>{{grammes.perigrafi}}</td>
        <td>{{grammes.monada}}</td><td class="num">{{grammes.timi}}</td>
        <td class="num">{{grammes.posotita}}</td><td class="num">{{grammes.dapani}}</td></tr>
  </tbody>
  <tfoot>
    <tr><td colspan="6">Σύνολο συμβατικών εργασιών</td><td class="num">{{epimetrisi.synolo_symvatikwn}}</td></tr>
    <tr><td colspan="6">Εργασίες πέραν των συμβατικών ποσοτήτων</td><td class="num">{{epimetrisi.synolo_ektos}}</td></tr>
    <tr class="total"><td colspan="6">ΓΕΝΙΚΟ ΣΥΝΟΛΟ</td><td class="num">{{epimetrisi.geniko_synolo}}</td></tr>
  </tfoot>
</table>
<p class="note">Η παρούσα συνοδεύεται από τα επιτόπια επιμετρητικά στοιχεία και τα επιμετρητικά σχέδια, και υποβάλλεται σε έντυπη και ηλεκτρονική μορφή σύμφωνα με την παρ. 2 του άρθρου 151 του ν. 4412/2016. Ο ανάδοχος δηλώνει υπεύθυνα ότι τα αναγραφόμενα στοιχεία είναι αληθή.</p>$T$),

-- 5. Βεβαίωση Περάτωσης Εργασιών — άρθρο 168 §2 ------------------------
('00000000-0000-0000-0000-0000000000d1', 'BEBAIOSI_PERATOSIS',
 'Βεβαίωση Περάτωσης Εργασιών', 'peraiosi', 'html', null, 'S26_BEBAIWSH',
 'N4412/168/2', '{ΕΤΟΣ}/{ΑΑ}', true,
 'Βεβαίωση περάτωσης των εργασιών του έργου «{{ergo.titlos}}»',
 '[{"label":"Ο Προϊστάμενος της Διευθύνουσας Υπηρεσίας","name":"{{proistamenos.full_name}}","capacity":"{{proistamenos.specialty}}"}]'::jsonb,
$T$<p class="intro">Έχοντας υπόψη:</p>
<ol class="grounds">
  <li>Τις διατάξεις του ν. 4412/2016 «Δημόσιες Συμβάσεις Έργων, Προμηθειών και Υπηρεσιών» (Α΄ 147), όπως ισχύει μετά τον ν. 4782/2021 (Α΄ 36), και ιδίως το άρθρο 168.</li>
  <li>Τη με αριθμό {{symvasi.arithmos}} σύμβαση εκτέλεσης του έργου, που υπογράφηκε την {{symvasi.imerominia_ypografis}}, συνολικής δαπάνης {{symvasi.aksia}} (χωρίς Φ.Π.Α.).</li>
  <li>Το εγκεκριμένο χρονοδιάγραμμα κατασκευής και τις χορηγηθείσες παρατάσεις, βάσει των οποίων ο εγκεκριμένος χρόνος περαίωσης έληγε την {{peraiosi.egkekrimenos_xronos}}.</li>
  <li>Τη με ημερομηνία {{peraiosi.ekthesi_epivleponta}} έγγραφη αναφορά του επιβλέποντος μηχανικού, η οποία υποβλήθηκε εντός της τριακονθήμερης προθεσμίας της παρ. 1 του άρθρου 168 και βεβαιώνει ότι οι εργασίες περατώθηκαν και ότι διενεργήθηκαν οι προβλεπόμενες από τη σύμβαση δοκιμές.</li>
</ol>
<p class="declare">Β Ε Β Α Ι Ω Ν Ο Υ Μ Ε</p>
<p>ότι οι εργασίες του έργου <strong>«{{ergo.titlos}}»</strong>, αναδόχου <strong>{{anadoxos.epwnymia}}</strong>, <strong>περατώθηκαν την {{peraiosi.pragmatiki_imerominia}}</strong>, εμπροθέσμως και σύμφωνα με τους όρους της σύμβασης και τα εγκεκριμένα σχέδια και τεύχη.</p>
<p>Στον χρόνο περαίωσης δεν προσμετράται ο χρόνος που απαιτήθηκε για την αποκατάσταση τυχόν επουσιωδών ελαττωμάτων, σύμφωνα με την παρ. 3 του άρθρου 168.</p>
<p>Ο χρόνος υποχρεωτικής συντήρησης του έργου, διάρκειας <strong>{{symvasi.mines_syntirisis}} μηνών</strong>, αρχίζει από την επομένη της έκδοσης της παρούσας, ήτοι την <strong>{{peraiosi.enarksi_syntirisis}}</strong>, σύμφωνα με το άρθρο 171 του ν. 4412/2016.</p>
<p class="note">Η παρούσα κοινοποιείται στον ανάδοχο κατά το άρθρο 143 του ν. 4412/2016.</p>$T$),

-- 6. Πράξη μείωσης εγγύησης 70% — άρθρο 72 §14 περ. β΄ ----------------
('00000000-0000-0000-0000-0000000000d1', 'PRAXH_MEIWSHS_EGG',
 'Πράξη μείωσης εγγύησης καλής εκτέλεσης κατά 70%', 'eggyiseis', 'html', null, 'S28_MEIWSH_EGG',
 'N4412/72/14b', '{ΕΤΟΣ}/{ΑΑ}', true,
 'Μείωση εγγυητικής επιστολής καλής εκτέλεσης του έργου «{{ergo.titlos}}»',
 '[{"label":"Ο Προϊστάμενος της Διευθύνουσας Υπηρεσίας","name":"{{proistamenos.full_name}}","capacity":"{{proistamenos.specialty}}"}]'::jsonb,
$T$<p class="intro">Έχοντας υπόψη:</p>
<ol class="grounds">
  <li>Την περ. β΄ της παρ. 14 του άρθρου 72 του ν. 4412/2016, κατά την οποία η εγγύηση καλής εκτέλεσης μειώνεται κατά ποσοστό εβδομήντα τοις εκατό (70%) της συνολικής αξίας της, αμέσως μετά την έγκριση της τελικής επιμέτρησης.</li>
  <li>Την παρ. 9 του άρθρου 151 του ν. 4412/2016 περί τελικής επιμέτρησης.</li>
  <li>Τη με ημερομηνία {{teliki.imerominia_egkrisis}} πράξη έγκρισης της τελικής επιμέτρησης του έργου.</li>
</ol>
<p class="declare">Α Π Ο Φ Α Σ Ι Ζ Ο Υ Μ Ε</p>
<p>Τη μείωση κατά εβδομήντα τοις εκατό (70%) της υπ’ αριθμ. <strong>{{eggyisi.arithmos}}</strong> εγγυητικής επιστολής καλής εκτέλεσης, εκδόσεως <strong>{{eggyisi.ekdotis}}</strong>, του αναδόχου <strong>{{anadoxos.epwnymia}}</strong>, για το έργο «{{ergo.titlos}}».</p>
<table class="data">
  <tr><th>Αρχικό ποσό εγγύησης</th><td class="num">{{eggyisi.arxiko_poso}}</td></tr>
  <tr><th>Ποσοστό μείωσης</th><td class="num">70%</td></tr>
  <tr><th>Ποσό μείωσης</th><td class="num">{{eggyisi.poso_meiosis}}</td></tr>
  <tr><th>Υπόλοιπο εγγύησης μετά τη μείωση</th><td class="num"><strong>{{eggyisi.ypoloipo}}</strong></td></tr>
</table>
<p>Το υπόλοιπο της εγγύησης επιστρέφεται στο σύνολό του μετά την έγκριση του πρωτοκόλλου παραλαβής του έργου και του τελικού λογαριασμού.</p>
<p class="note">Η παρούσα κοινοποιείται στον εκδότη της εγγυητικής επιστολής και στον ανάδοχο.</p>$T$)

on conflict do nothing;

-- >>>>>>>>>>>>>>>>>>>> 0019_template_fields.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0019_template_fields.sql — Δηλωτική χαρτογράφηση placeholder → πηγή
-- ---------------------------------------------------------------------
-- Κάθε placeholder ενός προτύπου αντιστοιχίζεται σε ΔΙΑΔΡΟΜΗ μέσα στο
-- αντικείμενο περιβάλλοντος που συνθέτει η Edge Function — ποτέ σε
-- αυθαίρετο SQL. Έτσι η προσθήκη νέου πεδίου σε πρότυπο δεν απαιτεί
-- ανάπτυξη κώδικα, και ταυτόχρονα δεν ανοίγει επιφάνεια επίθεσης.
--
--  source_kind: 'field'    → στήλη πίνακα           (π.χ. contracts.signed_at)
--               'query'    → παράγωγο αντικείμενο   (π.χ. supervisor.full_name)
--               'computed' → υπολογισμένη τιμή      (π.χ. maintenance_start)
--               'manual'   → συμπληρώνεται από τον χρήστη
--  data_type:   text | number | currency | quantity | date | date_long |
--               boolean | table
-- =====================================================================

-- ---- 1. Κοινά πεδία σε ΟΛΑ τα πρότυπα -------------------------------
insert into public.template_fields
  (template_id, placeholder, label, source_kind, source_path, data_type, is_required)
select t.id, f.placeholder, f.label, f.source_kind, f.source_path, f.data_type, f.is_required
from public.document_templates t
cross join (values
  ('{{ergo.titlos}}',                 'Τίτλος έργου',                    'field', 'projects.title',              'text',     true),
  ('{{ergo.kodikos}}',                'Κωδικός έργου',                   'field', 'projects.code',               'text',     true),
  ('{{symvasi.arithmos}}',            'Αριθμός σύμβασης',                'field', 'contracts.contract_no',       'text',     true),
  ('{{symvasi.imerominia_ypografis}}','Ημερομηνία υπογραφής',            'field', 'contracts.signed_at',         'date',     true),
  ('{{symvasi.aksia}}',               'Αξία αρχικής σύμβασης',           'field', 'contracts.initial_value_net', 'currency', true),
  ('{{anadoxos.epwnymia}}',           'Επωνυμία αναδόχου',               'field', 'contractors.name',            'text',     true),
  ('{{epivlepon.full_name}}',         'Ονοματεπώνυμο επιβλέποντος',      'query', 'supervisor.full_name',        'text',     true),
  ('{{epivlepon.specialty}}',         'Ειδικότητα επιβλέποντος',         'query', 'supervisor.specialty',        'text',     false),
  ('{{proistamenos.full_name}}',      'Ονοματεπώνυμο Προϊσταμένου Δ.Υ.', 'query', 'head.full_name',              'text',     true),
  ('{{proistamenos.specialty}}',      'Ειδικότητα Προϊσταμένου Δ.Υ.',    'query', 'head.specialty',              'text',     false)
) as f(placeholder, label, source_kind, source_path, data_type, is_required)
where t.is_active
on conflict do nothing;

-- ---- 2. Ειδικά πεδία ανά πρότυπο ------------------------------------
insert into public.template_fields
  (template_id, placeholder, label, source_kind, source_path, data_type, is_required)
select t.id, f.placeholder, f.label, f.source_kind, f.source_path, f.data_type, f.is_required
from public.document_templates t
join (values
  -- Έγκριση χρονοδιαγράμματος (άρθρο 145)
  ('EGKRISI_XRONOD', '{{symvasi.prothesmia_imeres}}',           'Συνολική προθεσμία (ημέρες)',           'field',    'contracts.total_duration_days', 'number', true),
  ('EGKRISI_XRONOD', '{{symvasi.lixi_prothesmias}}',            'Λήξη συνολικής προθεσμίας',             'field',    'contracts.current_end_date',    'date',   true),
  ('EGKRISI_XRONOD', '{{xronodiagramma.imerominia_ypovolis}}',  'Ημερομηνία υποβολής χρονοδιαγράμματος', 'field',    'schedules.submitted_at',        'date',   true),

  -- Π.Π.Α.Ε. (άρθρο 151 §7)
  ('PPAE', '{{afaneis.aa}}',                        'Α/Α δήλωσης αφανών',             'field',    'hidden_work_notices.serial_no',          'number', true),
  ('PPAE', '{{afaneis.perigrafi}}',                 'Περιγραφή αφανών εργασιών',      'field',    'hidden_work_notices.work_description',   'text',   true),
  ('PPAE', '{{afaneis.thesi}}',                     'Θέση',                           'field',    'hidden_work_notices.location',           'text',   true),
  ('PPAE', '{{afaneis.imerominia_prosklisis}}',     'Ημερομηνία πρόσκλησης',          'field',    'hidden_work_notices.invitation_sent_at', 'date',   true),
  ('PPAE', '{{afaneis.prothesmia_elegxou}}',        'Προθεσμία ελέγχου (3 ημέρες)',   'field',    'hidden_work_notices.inspection_due',     'date',   true),
  ('PPAE', '{{afaneis.imerominia_elegxou}}',        'Ημερομηνία ελέγχου',             'field',    'hidden_work_notices.inspected_at',       'date',   true),
  ('PPAE', '{{afaneis.imerominia_elegxou_pliris}}', 'Ημερομηνία ελέγχου (ολογράφως)', 'computed', 'inspection_date_long',                   'text',   true),
  ('PPAE', '{{afaneis.plithos_fotografion}}',       'Πλήθος ψηφιακών φωτογραφιών',    'field',    'hidden_work_notices.photos_count',       'number', true),

  -- Αναλυτική επιμέτρηση (άρθρο 151 §2)
  ('ANAL_EPIMETRISI', '{{epimetrisi.aa}}',                 'Α/Α επιμέτρησης',        'field',    'measurements.serial_no',          'number',   true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.periodos}}',           'Περίοδος',               'computed', 'measurement_period',              'text',     false),
  ('ANAL_EPIMETRISI', '{{epimetrisi.tmima}}',              'Τμήμα έργου',            'field',    'measurements.work_section',       'text',     false),
  ('ANAL_EPIMETRISI', '{{epimetrisi.imerominia_ypovolis}}','Ημερομηνία υποβολής',    'field',    'measurements.submitted_at',       'date',     true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.synolo_symvatikwn}}',  'Σύνολο συμβατικών',      'field',    'measurements.contractual_amount', 'currency', true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.synolo_ektos}}',       'Σύνολο εκτός σύμβασης',  'field',    'measurements.extra_amount',       'currency', true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.geniko_synolo}}',      'Γενικό σύνολο',          'field',    'measurements.total_amount',       'currency', true),
  ('ANAL_EPIMETRISI', '{{#each grammes}}',                 'Γραμμές επιμέτρησης (επαναλαμβανόμενη σειρά)', 'query', 'measurement_lines', 'table', true),

  -- Βεβαίωση περάτωσης (άρθρο 168)
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.egkekrimenos_xronos}}',  'Εγκεκριμένος χρόνος περαίωσης',   'field',    'completions.approved_completion_date', 'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.ekthesi_epivleponta}}',  'Ημ/νία έκθεσης επιβλέποντος',     'field',    'completions.supervisor_report_at',     'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.pragmatiki_imerominia}}','Πραγματική ημερομηνία περαίωσης', 'field',    'completions.actual_completion_date',   'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.enarksi_syntirisis}}',   'Έναρξη χρόνου συντήρησης',        'computed', 'maintenance_start',                   'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{symvasi.mines_syntirisis}}',      'Μήνες υποχρεωτικής συντήρησης',   'field',    'contracts.maintenance_months',        'number', true),

  -- Πράξη μείωσης εγγύησης (άρθρο 72 §14 περ. β΄)
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.arithmos}}',            'Αριθμός εγγυητικής',                 'field',    'guarantees.guarantee_no',    'text',     true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.ekdotis}}',             'Εκδότης εγγυητικής',                 'field',    'guarantees.issuer',          'text',     true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.arxiko_poso}}',         'Αρχικό ποσό εγγύησης',               'field',    'guarantees.current_amount',  'currency', true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.poso_meiosis}}',        'Ποσό μείωσης (70%)',                 'computed', 'guarantee_reduction',        'currency', true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.ypoloipo}}',            'Υπόλοιπο μετά τη μείωση',            'computed', 'guarantee_remaining',        'currency', true),
  ('PRAXH_MEIWSHS_EGG', '{{teliki.imerominia_egkrisis}}',  'Ημ/νία έγκρισης τελικής επιμέτρησης','field',    'final_measurement.approved_at','date',    true)
) as f(doc_code, placeholder, label, source_kind, source_path, data_type, is_required)
  on f.doc_code = t.doc_code
where t.is_active
on conflict do nothing;

-- >>>>>>>>>>>>>>>>>>>> 0021_nightly_jobs.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0021_nightly_jobs.sql — Νυχτερινή αυτοματοποίηση προθεσμιών
-- ---------------------------------------------------------------------
-- Οι προθεσμίες του ν. 4412/2016 τρέχουν είτε τις παρακολουθεί κανείς είτε
-- όχι. Η εργασία αυτή εκτελείται κάθε νύχτα και αποτυπώνει στη βάση ό,τι
-- ΕΧΕΙ ΗΔΗ επέλθει από τον νόμο:
--
--   • σιωπηρές εγκρίσεις εκεί — και ΜΟΝΟ εκεί — όπου ο νόμος τις ορίζει
--   • σήμανση υπερημερίας επιβλέποντος και εκπρόθεσμων σταδίων
--   • υπολογισμό της ειδικής ποινικής ρήτρας ημερολογίου
--
-- ΣΗΜΑΝΤΙΚΗ ΔΙΑΚΡΙΣΗ: η εργασία ΔΕΝ επιβάλλει κυρώσεις. Οι ρήτρες
-- καταχωρίζονται ως ΥΠΟΛΟΓΙΣΜΟΣ, χωρίς αριθμό/ημερομηνία απόφασης· η
-- επιβολή παραμένει πράξη της Διευθύνουσας Υπηρεσίας.
--
-- Οι τμηματικές επιμετρήσεις ΔΕΝ εγκρίνονται σιωπηρά: ο ν. 4412/2016
-- προβλέπει τεκμήριο έγκρισης για το χρονοδιάγραμμα (145 §2), τις αφανείς
-- εργασίες (151 §7), τους λογαριασμούς (152) και τις παρατάσεις (147 §5).
-- Οι επιμετρήσεις απλώς σημαίνονται ως εκπρόθεσμες προς έλεγχο.
-- =====================================================================

-- Το pg_cron παρέχεται από το Supabase. Σε σκέτη PostgreSQL απλώς δεν
-- υπάρχει· η συνάρτηση εγκαθίσταται κανονικά και προγραμματίζεται εξωτερικά.
do $ext$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron μη διαθέσιμο — προγραμματίστε εξωτερικά την app.run_nightly_jobs().';
end $ext$;

-- ---- 1. Μητρώο εκτελέσεων -------------------------------------------
create table if not exists app.nightly_runs (
  id          bigint generated always as identity primary key,
  ran_at      timestamptz not null default now(),
  result      jsonb       not null,
  duration_ms integer
);

comment on table app.nightly_runs is
  'Ιστορικό εκτελέσεων της νυχτερινής εργασίας προθεσμιών — τι μεταβλήθηκε και πότε.';

-- ---- 2. Η εργασία ----------------------------------------------------
create or replace function app.run_nightly_jobs()
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  t0            timestamptz := clock_timestamp();
  v_sched       integer := 0;
  v_hidden      integer := 0;
  v_pay         integer := 0;
  v_ext         integer := 0;
  v_sup_overdue integer := 0;
  v_meas_late   integer := 0;
  v_stages      integer := 0;
  v_penalties   integer := 0;
  v_from        date := date_trunc('month', current_date - interval '1 month')::date;
  v_to          date := (date_trunc('month', current_date) - interval '1 day')::date;
  v_result      jsonb;
begin
  -- 2.1 Χρονοδιάγραμμα — τεκμήριο έγκρισης (άρθρο 145 §2)
  update public.schedules s
     set deemed_approved = true
   where s.submitted_at is not null
     and s.approved_at is null
     and s.deemed_approved = false
     and s.approval_due_date is not null
     and s.approval_due_date < current_date;
  get diagnostics v_sched = row_count;

  -- 2.2 Αφανείς εργασίες — εγκριτική πράξη εντός 30 ημερών (άρθρο 151 §7)
  update public.hidden_work_notices h
     set deemed_approved = true,
         status = 'approved'
   where h.approval_due is not null
     and h.approval_due < current_date
     and h.approved_at is null
     and h.deemed_approved = false
     and h.status <> 'rejected';
  get diagnostics v_hidden = row_count;

  -- 2.3 Λογαριασμοί — σιωπηρή έγκριση (άρθρο 152)
  update public.payment_certificates p
     set deemed_approved = true,
         status = 'deemed_approved'
   where p.approval_due is not null
     and p.approval_due < current_date
     and p.approved_at is null
     and p.deemed_approved = false
     and p.status in ('submitted', 'under_review');
  get diagnostics v_pay = row_count;

  -- 2.4 Παρατάσεις — σιωπηρή αποδοχή (άρθρο 147 §5)
  update public.time_extensions e
     set deemed_accepted = true,
         outcome = 'deemed_accepted'
   where e.decision_due is not null
     and e.decision_due < current_date
     and e.decided_at is null
     and e.deemed_accepted = false
     and e.outcome = 'pending';
  get diagnostics v_ext = row_count;

  -- 2.5 Υπερημερία επιβλέποντος στον έλεγχο αφανών (άρθρο 151 §7, 3 ημέρες)
  update public.hidden_work_notices h
     set supervisor_overdue = true
   where h.inspection_due is not null
     and h.inspection_due < current_date
     and h.inspected_at is null
     and h.supervisor_overdue = false;
  get diagnostics v_sup_overdue = row_count;

  -- 2.6 Επιμετρήσεις εκπρόθεσμες προς έλεγχο — ΣΗΜΑΝΣΗ, όχι έγκριση
  select count(*) into v_meas_late
    from public.measurements m
   where m.approval_due is not null
     and m.approval_due < current_date
     and m.approved_at is null
     and m.deemed_approved = false
     and m.status in ('submitted', 'sampled', 'under_check');

  -- 2.7 Εκπρόθεσμα στάδια του οδηγού
  update public.project_stages ps
     set status = 'overdue'
   where ps.due_date is not null
     and ps.due_date < current_date
     and ps.status in ('available', 'in_progress', 'pending_approval');
  get diagnostics v_stages = row_count;

  -- 2.8 Ειδική ποινική ρήτρα ημερολογίου (άρθρο 146) — ΥΠΟΛΟΓΙΣΜΟΣ
  --     Μία εγγραφή ανά έργο και ανά ημερολογιακό μήνα, ιδεμποτικά.
  with missing as (
    select v.project_id, count(*)::int as days
      from public.v_diary_missing_days v
     where v.missing_date between v_from and v_to
     group by v.project_id
  )
  insert into public.penalties
    (project_id, kind, period_from, period_to, days_count,
     rate_description, base_amount, amount, reason, legal_ref_id)
  select m.project_id,
         'eidiki_ritra_imerologiou',
         v_from, v_to, m.days,
         format('%s ημέρες × %s €/ημέρα', m.days, c.diary_penalty_per_day),
         c.diary_penalty_per_day,
         round(m.days * c.diary_penalty_per_day, 2),
         format('Αυτόματος υπολογισμός ειδικής ποινικής ρήτρας για %s εργάσιμες '
                'ημέρες χωρίς καταχώριση ημερολογίου (%s έως %s), κατά το άρθρο 146 '
                'του ν. 4412/2016. ΑΠΑΙΤΕΙΤΑΙ ΑΠΟΦΑΣΗ ΤΗΣ ΔΙΕΥΘΥΝΟΥΣΑΣ ΥΠΗΡΕΣΙΑΣ '
                'για την επιβολή — η παρούσα εγγραφή αποτελεί υπολογισμό, όχι κύρωση.',
                m.days, to_char(v_from, 'DD/MM/YYYY'), to_char(v_to, 'DD/MM/YYYY')),
         'N4412/146'
    from missing m
    join public.contracts c on c.project_id = m.project_id
   where m.days > 0
     and not exists (
       select 1 from public.penalties p
        where p.project_id = m.project_id
          and p.kind = 'eidiki_ritra_imerologiou'
          and p.period_from = v_from
          and p.period_to = v_to);
  get diagnostics v_penalties = row_count;

  v_result := jsonb_build_object(
    'xronodiagrammata_sioipiri_egkrisi', v_sched,
    'afaneis_egkritiki_praxi',           v_hidden,
    'logariasmoi_sioipiri_egkrisi',      v_pay,
    'paratasseis_sioipiri_apodoxi',      v_ext,
    'ypermeria_epivleponta',             v_sup_overdue,
    'epimetriseis_ekprothesmes',         v_meas_late,
    'stadia_ekprothesma',                v_stages,
    'ritres_imerologiou_ypologistikan',  v_penalties,
    'periodos_ritras', jsonb_build_object('apo', v_from, 'eos', v_to)
  );

  insert into app.nightly_runs (result, duration_ms)
  values (v_result,
          extract(milliseconds from clock_timestamp() - t0)::int);

  return v_result;
end $$;

comment on function app.run_nightly_jobs() is
  'Νυχτερινή αποτύπωση προθεσμιών ν. 4412/2016: σιωπηρές εγκρίσεις (145 §2, '
  '151 §7, 152, 147 §5), σήμανση υπερημερίας και εκπρόθεσμων σταδίων, '
  'υπολογισμός ρήτρας ημερολογίου (146). Δεν επιβάλλει κυρώσεις.';

revoke all on function app.run_nightly_jobs() from public, anon, authenticated;

-- ---- 3. Χρονοπρογραμματισμός ----------------------------------------
-- Κάθε βράδυ στις 02:15 UTC (≈ 04:15/05:15 ώρα Ελλάδας).
do $sched$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('epivlepsi-nightly');
    exception when others then
      null; -- δεν υπάρχει ακόμη
    end;
    perform cron.schedule('epivlepsi-nightly', '15 2 * * *',
                          'select app.run_nightly_jobs();');
    raise notice 'Η νυχτερινή εργασία προγραμματίστηκε (02:15 UTC).';
  else
    raise notice 'Χωρίς pg_cron: εκτελέστε την app.run_nightly_jobs() από εξωτερικό χρονοπρογραμματιστή.';
  end if;
end $sched$;

-- >>>>>>>>>>>>>>>>>>>> 0022_create_project_rpc.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0022_create_project_rpc.sql — Έναρξη επίβλεψης νέου έργου
-- ---------------------------------------------------------------------
-- Μία και μόνη συναλλαγή που δημιουργεί:
--   ανάδοχο → έργο → σύμβαση → ορισμούς επίβλεψης → εγγύηση →
--   ολόκληρη τη ροή των 36 σταδίων του οδηγού.
--
-- Γιατί σε μία RPC και όχι με πέντε κλήσεις από τον browser: αν
-- αποτύχει το τέταρτο βήμα, τα τρία πρώτα έχουν ήδη γραφτεί και το
-- μητρώο μένει με μισοτελειωμένο έργο. Εδώ ή γίνονται όλα ή κανένα.
--
-- ΑΡΜΟΔΙΟΤΗΤΑ: το έργο το ανοίγει η Διευθύνουσα Υπηρεσία, η οποία
-- ορίζει και τον επιβλέποντα (άρθρο 136 §2 ν. 4412/2016). Ο επιβλέπων
-- δεν αυτο-ορίζεται· γι' αυτό απαιτείται ρόλος υπηρεσιακής εμβέλειας.
-- =====================================================================

-- ---- 1. Κατάλογοι για τις λίστες επιλογής της φόρμας ----------------
-- Τα profiles έχουν ήδη policy «ίδιος φορέας → ορατό», όμως το
-- front-end χρειάζεται και τους ρόλους καθενός για να προτείνει σωστά.
create or replace function public.org_people()
returns table (id uuid, full_name text, email text, specialty text,
               grade text, registry_no text, roles text[])
language sql
stable
security definer
set search_path = public, app
as $$
  select p.id, p.full_name, p.email, p.specialty, p.grade, p.registry_no,
         coalesce(array_agg(r.role::text order by r.role)
                    filter (where r.role is not null), '{}')
    from public.profiles p
    left join public.org_roles r
           on r.profile_id = p.id
          and (r.valid_to is null or r.valid_to >= current_date)
   where p.org_id = app.my_org()
     and p.is_active
   group by p.id, p.full_name, p.email, p.specialty, p.grade, p.registry_no
   order by p.full_name;
$$;

comment on function public.org_people() is
  'Το ενεργό προσωπικό του φορέα του καλούντος, με τους υπηρεσιακούς του ρόλους.';

-- ---- 2. Η δημιουργία -------------------------------------------------
create or replace function public.create_project_full(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_org         uuid := app.my_org();
  v_me          uuid := app.uid();
  j_project     jsonb := payload -> 'project';
  j_contractor  jsonb := payload -> 'contractor';
  j_contract    jsonb := payload -> 'contract';
  j_assign      jsonb := payload -> 'assignments';
  j_guarantee   jsonb := payload -> 'guarantee';

  v_contractor  uuid;
  v_project     uuid;
  v_code        text;
  v_signed      date;
  v_days        integer;
  v_orig_end    date;
  v_oriaki      date;

  v_budget_works numeric;   -- δαπάνη εργασιών κατά τη μελέτη, χωρίς ΓΕ&ΟΕ
  v_discount     numeric;
  v_geoe_pct     numeric;
  v_cont_pct     numeric;
  v_revision     numeric;
  v_works        numeric;   -- μετά την έκπτωση
  v_geoe         numeric;
  v_cont         numeric;
  v_initial      numeric;
  v_study_total  numeric;

  v_epivlepon   uuid;
  v_proistam    uuid;
  v_helper      uuid;
  v_stages      integer;
  v_guarantee   uuid;
begin
  ------------------------------------------------------------------
  -- 2.1 Αρμοδιότητα
  ------------------------------------------------------------------
  if v_me is null then
    raise exception 'Δεν υπάρχει ενεργή συνεδρία.';
  end if;
  if v_org is null then
    raise exception 'Ο λογαριασμός σας δεν έχει συνδεθεί με φορέα. Απευθυνθείτε στον διαχειριστή.';
  end if;
  if not app.is_service_wide() then
    raise exception 'Η δημιουργία έργου ανήκει στη Διευθύνουσα Υπηρεσία, η οποία ορίζει και '
                    'τον επιβλέποντα (άρθρο 136 §2 ν. 4412/2016). Ο λογαριασμός σας δεν φέρει '
                    'ρόλο υπηρεσιακής εμβέλειας.';
  end if;

  ------------------------------------------------------------------
  -- 2.2 Ανάδοχος — υπάρχων ή νέος
  ------------------------------------------------------------------
  v_contractor := nullif(j_contractor ->> 'id', '')::uuid;

  if v_contractor is null then
    -- Ίδιο ΑΦΜ στον ίδιο φορέα σημαίνει ίδιος ανάδοχος: ενημερώνουμε
    -- αντί να σκάσουμε στο μοναδικό ευρετήριο.
    insert into public.contractors
      (org_id, name, legal_form, afm, doy, gemi, meep_mieedde,
       legal_rep_name, legal_rep_afm, address, email, phone, is_joint_venture)
    values
      (v_org,
       j_contractor ->> 'name',
       nullif(j_contractor ->> 'legal_form', ''),
       j_contractor ->> 'afm',
       nullif(j_contractor ->> 'doy', ''),
       nullif(j_contractor ->> 'gemi', ''),
       nullif(j_contractor ->> 'meep_mieedde', ''),
       nullif(j_contractor ->> 'legal_rep_name', ''),
       nullif(j_contractor ->> 'legal_rep_afm', ''),
       nullif(j_contractor ->> 'address', ''),
       j_contractor ->> 'email',
       nullif(j_contractor ->> 'phone', ''),
       coalesce((j_contractor ->> 'is_joint_venture')::boolean, false))
    on conflict (org_id, afm) do update
       set name           = excluded.name,
           email          = excluded.email,
           phone          = coalesce(excluded.phone, public.contractors.phone),
           legal_rep_name = coalesce(excluded.legal_rep_name, public.contractors.legal_rep_name)
    returning id into v_contractor;
  else
    perform 1 from public.contractors
     where id = v_contractor and org_id = v_org;
    if not found then
      raise exception 'Ο ανάδοχος που επιλέξατε δεν ανήκει στον φορέα σας.';
    end if;
  end if;

  ------------------------------------------------------------------
  -- 2.3 Οικονομικά μεγέθη — υπολογίζονται εδώ, όχι στον browser
  ------------------------------------------------------------------
  v_budget_works := (j_contract ->> 'budget_works_net')::numeric;
  v_discount     := coalesce((j_contract ->> 'discount_pct')::numeric, 0);
  v_geoe_pct     := coalesce((j_contract ->> 'ge_oe_pct')::numeric, 18);
  v_cont_pct     := coalesce((j_contract ->> 'contingency_pct')::numeric, 15);
  v_revision     := coalesce((j_contract ->> 'revision_amount')::numeric, 0);

  if v_budget_works is null or v_budget_works <= 0 then
    raise exception 'Η δαπάνη εργασιών του προϋπολογισμού μελέτης πρέπει να είναι θετική.';
  end if;
  if v_cont_pct not in (9, 15) then
    raise exception 'Το ποσοστό απροβλέπτων ορίζεται σε 9%% για έργα ίσα ή άνω των ορίων '
                    'του άρθρου 5 και σε 15%% για τα μικρότερα (άρθρο 156 §3β ν. 4412/2016).';
  end if;

  v_works   := round(v_budget_works * (1 - v_discount / 100), 2);
  v_geoe    := round(v_works * v_geoe_pct / 100, 2);
  v_cont    := round((v_works + v_geoe) * v_cont_pct / 100, 2);
  v_initial := round(v_works + v_geoe + v_cont + v_revision, 2);

  -- Προϋπολογισμός μελέτης: τα ίδια μεγέθη χωρίς την έκπτωση.
  v_study_total := round(
      v_budget_works
    + v_budget_works * v_geoe_pct / 100
    + (v_budget_works + v_budget_works * v_geoe_pct / 100) * v_cont_pct / 100
    + v_revision, 2);

  ------------------------------------------------------------------
  -- 2.4 Προθεσμίες (άρθρο 147)
  ------------------------------------------------------------------
  v_signed := (j_contract ->> 'signed_at')::date;
  v_days   := (j_contract ->> 'total_duration_days')::integer;

  if v_signed is null then raise exception 'Λείπει η ημερομηνία υπογραφής της σύμβασης.'; end if;
  if v_days is null or v_days <= 0 then
    raise exception 'Η συνολική προθεσμία πρέπει να είναι θετικός αριθμός ημερών (άρθρο 147 §1).';
  end if;

  -- §2: οι προθεσμίες αρχίζουν από την υπογραφή της σύμβασης.
  v_orig_end := v_signed + v_days;
  -- §4: οριακή προθεσμία = το ήμισυ της αρχικής, όχι λιγότερο από 3 μήνες.
  v_oriaki   := v_orig_end + greatest((v_days / 2)::integer, 90);

  ------------------------------------------------------------------
  -- 2.5 Έργο
  ------------------------------------------------------------------
  v_code := trim(j_project ->> 'code');
  if v_code is null or v_code = '' then
    raise exception 'Ο κωδικός του έργου είναι υποχρεωτικός.';
  end if;
  if exists (select 1 from public.projects
              where org_id = v_org and code = v_code) then
    raise exception 'Υπάρχει ήδη έργο με κωδικό «%» στον φορέα σας.', v_code;
  end if;

  insert into public.projects
    (org_id, code, title, category, cpv, ka_budget_code, funding_source, mis_code,
     study_budget_net, estimated_value_net, vat_rate,
     tender_publication_at, adam_tender, award_decision_ada, location, created_by)
  values
    (v_org, v_code,
     j_project ->> 'title',
     (j_project ->> 'category')::public.project_category,
     nullif(j_project ->> 'cpv', ''),
     nullif(j_project ->> 'ka_budget_code', ''),
     nullif(j_project ->> 'funding_source', ''),
     nullif(j_project ->> 'mis_code', ''),
     coalesce(nullif(j_project ->> 'study_budget_net', '')::numeric, v_study_total),
     coalesce(nullif(j_project ->> 'estimated_value_net', '')::numeric, v_study_total),
     coalesce((j_project ->> 'vat_rate')::numeric, 24),
     nullif(j_project ->> 'tender_publication_at', '')::date,
     nullif(j_project ->> 'adam_tender', ''),
     nullif(j_project ->> 'award_decision_ada', ''),
     nullif(j_project ->> 'location', ''),
     v_me)
  returning id into v_project;

  ------------------------------------------------------------------
  -- 2.6 Ορισμοί επίβλεψης — ΠΡΙΝ από τη σύμβαση, ώστε ο επιβλέπων να
  --     βλέπει το έργο του από την πρώτη στιγμή (άρθρο 136 §2).
  ------------------------------------------------------------------
  v_epivlepon := nullif(j_assign ->> 'epivlepon', '')::uuid;
  v_proistam  := nullif(j_assign ->> 'proistamenos_dy', '')::uuid;

  if v_epivlepon is null then
    raise exception 'Πρέπει να οριστεί επιβλέπων μηχανικός (άρθρο 136 §2 ν. 4412/2016).';
  end if;
  perform 1 from public.profiles where id = v_epivlepon and org_id = v_org;
  if not found then
    raise exception 'Ο επιβλέπων που επιλέξατε δεν ανήκει στον φορέα σας.';
  end if;

  insert into public.project_assignments
    (project_id, profile_id, role, is_coordinator, duties,
     decision_no, decision_ada, decision_date, valid_from, legal_ref_id)
  values
    (v_project, v_epivlepon, 'epivlepon',
     coalesce((j_assign ->> 'epivlepon_is_coordinator')::boolean, false),
     nullif(j_assign ->> 'duties', ''),
     nullif(j_assign ->> 'decision_no', ''),
     nullif(j_assign ->> 'decision_ada', ''),
     nullif(j_assign ->> 'decision_date', '')::date,
     coalesce(nullif(j_assign ->> 'decision_date', '')::date, v_signed),
     'N4412/136/2');

  -- Βοηθοί επιβλέποντες (προαιρετικά, ίδια απόφαση ορισμού)
  for v_helper in
    select value::uuid
      from jsonb_array_elements_text(coalesce(j_assign -> 'voithoi', '[]'::jsonb))
     where value <> ''
  loop
    if exists (select 1 from public.profiles where id = v_helper and org_id = v_org)
       and v_helper <> v_epivlepon then
      insert into public.project_assignments
        (project_id, profile_id, role, decision_no, decision_ada, decision_date,
         valid_from, legal_ref_id)
      values
        (v_project, v_helper, 'voithos_epivlepon',
         nullif(j_assign ->> 'decision_no', ''),
         nullif(j_assign ->> 'decision_ada', ''),
         nullif(j_assign ->> 'decision_date', '')::date,
         coalesce(nullif(j_assign ->> 'decision_date', '')::date, v_signed),
         'N4412/136/2');
    end if;
  end loop;

  -- Προϊστάμενος Διευθύνουσας Υπηρεσίας
  if v_proistam is not null
     and exists (select 1 from public.profiles where id = v_proistam and org_id = v_org) then
    insert into public.project_assignments
      (project_id, profile_id, role, valid_from, legal_ref_id)
    values (v_project, v_proistam, 'proistamenos_dy', v_signed, 'N4412/136');
  end if;

  -- Ο ανάδοχος ως συμβαλλόμενο μέρος του έργου
  insert into public.project_assignments
    (project_id, contractor_id, role, valid_from, legal_ref_id)
  values (v_project, v_contractor, 'anadochos', v_signed, 'N4412/138');

  ------------------------------------------------------------------
  -- 2.7 Σύμβαση
  ------------------------------------------------------------------
  insert into public.contracts
    (project_id, contractor_id, regime, supervision_mode,
     contract_no, signed_at, adam_contract, ada_contract,
     discount_pct, works_value_net, ge_oe_pct, ge_oe_amount,
     contingency_pct, contingency_amount, revision_amount, initial_value_net,
     estimated_guarantee_base, vat_rate,
     total_duration_days, works_start_deadline, schedule_submit_days,
     original_end_date, current_end_date, oriaki_end_date,
     maintenance_months, has_prim_clause, daily_penalty_basis,
     diary_mode, diary_penalty_per_day, status)
  values
    (v_project, v_contractor,
     coalesce((j_contract ->> 'regime')::public.contract_regime, 'n4412_meta_n4782'),
     coalesce((j_contract ->> 'supervision_mode')::public.supervision_mode, 'ypiresiaki'),
     j_contract ->> 'contract_no',
     v_signed,
     nullif(j_contract ->> 'adam_contract', ''),
     nullif(j_contract ->> 'ada_contract', ''),
     v_discount, v_works, v_geoe_pct, v_geoe,
     v_cont_pct, v_cont, v_revision, v_initial,
     v_initial, coalesce((j_contract ->> 'vat_rate')::numeric, 24),
     v_days,
     nullif(j_contract ->> 'works_start_deadline', '')::date,
     coalesce((j_contract ->> 'schedule_submit_days')::integer, 15),
     v_orig_end, v_orig_end, v_oriaki,
     coalesce((j_contract ->> 'maintenance_months')::integer, 15),
     coalesce((j_contract ->> 'has_prim_clause')::boolean, false),
     nullif(j_contract ->> 'daily_penalty_basis', '')::numeric,
     coalesce((j_contract ->> 'diary_mode')::public.diary_mode, 'imerisio'),
     coalesce((j_contract ->> 'diary_penalty_per_day')::numeric, 100),
     'active');

  ------------------------------------------------------------------
  -- 2.8 Εγγύηση καλής εκτέλεσης (άρθρο 72 §4) — προαιρετική εδώ:
  --     αν δεν έχει κατατεθεί ακόμη, καταχωρίζεται εκκρεμής ώστε το
  --     στάδιο εγκατάστασης να μπλοκάρει μέχρι να προσκομιστεί.
  ------------------------------------------------------------------
  if j_guarantee is not null and jsonb_typeof(j_guarantee) = 'object'
     and coalesce(j_guarantee ->> 'guarantee_no', '') <> '' then
    insert into public.guarantees
      (project_id, gtype, issuer, guarantee_no, issued_at, valid_to,
       original_amount, current_amount, pct_of_contract, status, legal_ref_id)
    values
      (v_project, 'kalis_ektelesis',
       j_guarantee ->> 'issuer',
       j_guarantee ->> 'guarantee_no',
       coalesce(nullif(j_guarantee ->> 'issued_at', '')::date, v_signed),
       nullif(j_guarantee ->> 'valid_to', '')::date,
       (j_guarantee ->> 'original_amount')::numeric,
       (j_guarantee ->> 'original_amount')::numeric,
       round((j_guarantee ->> 'original_amount')::numeric / nullif(v_initial, 0) * 100, 3),
       'energi', 'N4412/72/4')
    returning id into v_guarantee;
  end if;

  ------------------------------------------------------------------
  -- 2.9 Η ροή του οδηγού
  ------------------------------------------------------------------
  v_stages := app.instantiate_workflow(v_project);

  return jsonb_build_object(
    'project_id',      v_project,
    'contractor_id',   v_contractor,
    'guarantee_id',    v_guarantee,
    'stages_created',  v_stages,
    'code',            v_code,
    'oikonomika', jsonb_build_object(
      'works_value_net',     v_works,
      'ge_oe_amount',        v_geoe,
      'contingency_amount',  v_cont,
      'initial_value_net',   v_initial,
      'study_budget_net',    v_study_total),
    'prothesmies', jsonb_build_object(
      'signed_at',         v_signed,
      'original_end_date', v_orig_end,
      'oriaki_end_date',   v_oriaki)
  );
end $$;

comment on function public.create_project_full(jsonb) is
  'Ατομική δημιουργία έργου: ανάδοχος, έργο, ορισμοί επίβλεψης (136 §2), σύμβαση, '
  'εγγύηση (72 §4) και στιγμιότυπο ροής 36 σταδίων. Απαιτεί ρόλο υπηρεσιακής εμβέλειας.';

revoke all on function public.create_project_full(jsonb) from public, anon;
revoke all on function public.org_people()             from public, anon;
grant execute on function public.create_project_full(jsonb) to authenticated, service_role;
grant execute on function public.org_people()               to authenticated, service_role;

-- >>>>>>>>>>>>>>>>>>>> 0023_stage_due_dates.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0023_stage_due_dates.sql — Διόρθωση αφετηρίας των προθεσμιών σταδίου
-- ---------------------------------------------------------------------
-- ΤΟ ΠΡΟΒΛΗΜΑ
-- Η app.compute_stage_due() αναγνώριζε τρεις μόνο αφετηρίες και για κάθε
-- άλλη έπεφτε σιωπηλά στην ημερομηνία υπογραφής της σύμβασης. Έτσι στάδια
-- που κατά τον νόμο μετρούν από γεγονός που ΔΕΝ έχει ακόμη επέλθει —
-- υποβολή εγγράφου, κοινοποίηση πράξης, Βεβαίωση Περάτωσης, λήξη
-- συντήρησης — έπαιρναν ημερομηνία 10 ή 30 ημερών από την υπογραφή και
-- εμφανίζονταν ως ΕΚΠΡΟΘΕΣΜΑ σε έργο που μόλις ξεκίνησε.
--
-- Ένας επιβλέπων που βλέπει «Έκδοση Βεβαίωσης Περάτωσης — εκπρόθεσμο 145
-- ημέρες» σε έργο υπό εκτέλεση μαθαίνει να αγνοεί τις ειδοποιήσεις. Ένα
-- σύστημα ελέγχου που παράγει ψευδείς συναγερμούς είναι χειρότερο από
-- κανένα.
--
-- Η ΔΙΟΡΘΩΣΗ
-- Η προθεσμία υπολογίζεται μόνο όταν υπάρχει η αφετηρία της. Αλλιώς
-- επιστρέφεται NULL: το στάδιο απλώς δεν έχει ακόμη προθεσμία.
--
--   ypografi_symvasis   → ημερομηνία υπογραφής                (147 §2)
--   enarxi_ergasion     → προθεσμία έναρξης εργασιών          (145 §2)
--   lixi_prothesmias    → τρέχουσα λήξη συνολικής προθεσμίας  (147 §1)
--   bebaiosi_peratosis  → έκδοση Βεβαίωσης Περάτωσης          (168 §2)
--   lixi_syntirisis     → λήξη υποχρεωτικής συντήρησης        (171)
--   ypovoli_eggrafou    ┐ ανά έγγραφο/γεγονός: οι προθεσμίες αυτές
--   koinopoiisi_praxis  ├ τηρούνται στην ίδια την εγγραφή (approval_due,
--   custom              ┘ inspection_due, decision_due) — όχι στο στάδιο.
-- =====================================================================

create or replace function app.compute_stage_due(p_project_id uuid, p_stage_code text)
returns date
language plpgsql
stable
set search_path = public, app
as $$
declare
  s      public.workflow_stages%rowtype;
  v_base date;
begin
  select * into s from public.workflow_stages where code = p_stage_code;
  if not found then return null; end if;
  if s.deadline_days is null and s.deadline_months is null then return null; end if;

  case s.deadline_basis
    when 'ypografi_symvasis' then
      select c.signed_at into v_base from public.contracts c where c.project_id = p_project_id;

    when 'enarxi_ergasion' then
      select c.works_start_deadline into v_base from public.contracts c where c.project_id = p_project_id;

    when 'lixi_prothesmias' then
      select c.current_end_date into v_base from public.contracts c where c.project_id = p_project_id;

    when 'bebaiosi_peratosis' then
      -- Άρθρο 168 §2: μετρά από την έκδοση της Βεβαίωσης — ή από τον χρόνο
      -- που αυτή τεκμαίρεται εκδοθείσα μετά την όχληση του αναδόχου.
      select coalesce(cm.certificate_issued_at,
                      case when cm.deemed_issued then cm.certificate_due end)
        into v_base
        from public.completions cm where cm.project_id = p_project_id;

    when 'lixi_syntirisis' then
      -- Άρθρο 171: η παραλαβή μετρά από τη λήξη του χρόνου συντήρησης.
      select mp.ends_on into v_base
        from public.maintenance_periods mp
       where mp.project_id = p_project_id
       order by mp.ends_on desc nulls last limit 1;

    else
      -- ypovoli_eggrafou / koinopoiisi_praxis / custom: η αφετηρία είναι
      -- συγκεκριμένο έγγραφο ή πράξη. Χωρίς αυτό δεν υπάρχει προθεσμία —
      -- και δεν επινοούμε καμία.
      v_base := null;
  end case;

  if v_base is null then return null; end if;

  if s.deadline_months is not null then
    v_base := v_base + (s.deadline_months || ' months')::interval;
  end if;
  if s.deadline_days is not null then
    v_base := v_base + s.deadline_days;
  end if;
  return v_base;
end $$;

comment on function app.compute_stage_due(uuid, text) is
  'Προθεσμία σταδίου με βάση την αφετηρία που ορίζει ο νόμος. Επιστρέφει NULL όσο '
  'η αφετηρία δεν έχει επέλθει — ποτέ πλασματική ημερομηνία.';

-- ---------------------------------------------------------------------
-- Επανυπολογισμός όταν εμφανιστεί μια αφετηρία
-- ---------------------------------------------------------------------
create or replace function app.recompute_stage_dues(p_project_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare v_n integer;
begin
  update public.project_stages ps
     set due_date = app.compute_stage_due(p_project_id, ps.stage_code)
   where ps.project_id = p_project_id
     and ps.status not in ('completed', 'not_applicable')
     and ps.due_date is distinct from app.compute_stage_due(p_project_id, ps.stage_code);
  get diagnostics v_n = row_count;

  -- Ένα στάδιο που είχε χαρακτηριστεί εκπρόθεσμο επειδή έφερε πλασματική
  -- ημερομηνία επιστρέφει στην κανονική του κατάσταση.
  update public.project_stages ps
     set status = 'available'
   where ps.project_id = p_project_id
     and ps.status = 'overdue'
     and (ps.due_date is null or ps.due_date >= current_date);

  return v_n;
end $$;

comment on function app.recompute_stage_dues(uuid) is
  'Επαναϋπολογισμός των προθεσμιών των σταδίων ενός έργου όταν επέλθει νέα αφετηρία '
  '(Βεβαίωση Περάτωσης, έναρξη εργασιών, παράταση, λήξη συντήρησης).';

revoke all on function app.recompute_stage_dues(uuid) from public, anon;

create or replace function app.trg_recompute_stage_dues()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  perform app.recompute_stage_dues(coalesce(new.project_id, old.project_id));
  return null;
end $$;

-- Οι τρεις πίνακες που γεννούν νέες αφετηρίες.
drop trigger if exists trg_dues_completions on public.completions;
create trigger trg_dues_completions
  after insert or update on public.completions
  for each row execute function app.trg_recompute_stage_dues();

drop trigger if exists trg_dues_maintenance on public.maintenance_periods;
create trigger trg_dues_maintenance
  after insert or update on public.maintenance_periods
  for each row execute function app.trg_recompute_stage_dues();

drop trigger if exists trg_dues_contracts on public.contracts;
create trigger trg_dues_contracts
  after update of works_start_deadline, current_end_date, signed_at on public.contracts
  for each row execute function app.trg_recompute_stage_dues();

-- ---------------------------------------------------------------------
-- Διόρθωση των ήδη καταχωρισμένων έργων
-- ---------------------------------------------------------------------
do $fix$
declare r record; v_total integer := 0; v_n integer;
begin
  for r in select id from public.projects loop
    v_n := app.recompute_stage_dues(r.id);
    v_total := v_total + v_n;
  end loop;
  raise notice 'Διορθώθηκαν % προθεσμίες σταδίων σε υπάρχοντα έργα.', v_total;
end $fix$;

-- >>>>>>>>>>>>>>>>>>>> 0020_demo_seed.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- 0020_demo_seed.sql — Επιδεικτικά δεδομένα (ΠΡΟΑΙΡΕΤΙΚΟ)
-- ---------------------------------------------------------------------
-- Δημιουργεί δύο χρήστες, ένα πλήρες έργο του Δήμου Ρόδου και όλες τις
-- συνοδευτικές εγγραφές, ώστε να δοκιμαστεί άμεσα η ροή και η παραγωγή
-- εγγράφων. ΔΕΝ πρέπει να εφαρμοστεί σε παραγωγική βάση.
--
--   epivlepon@dimosrodou.demo    / Epivlepsi!2026   (επιβλέπων)
--   proistamenos@dimosrodou.demo / Epivlepsi!2026   (προϊστάμενος Δ.Υ.)
-- =====================================================================

do $$
declare
  v_org        uuid := '00000000-0000-0000-0000-0000000000d1';
  v_epiv       uuid := '00000000-0000-0000-0000-00000000e001';
  v_proi       uuid := '00000000-0000-0000-0000-00000000e002';
  v_project    uuid := '00000000-0000-0000-0000-0000000000a1';
  v_contractor uuid := '00000000-0000-0000-0000-0000000000c1';
  v_contract   uuid := '00000000-0000-0000-0000-0000000000b1';
  v_bver       uuid := '00000000-0000-0000-0000-0000000000f1';
  v_meas       uuid := '00000000-0000-0000-0000-000000000101';
  v_hwn        uuid := '00000000-0000-0000-0000-000000000111';
  v_guar       uuid := '00000000-0000-0000-0000-000000000121';
  v_sched      uuid := '00000000-0000-0000-0000-000000000131';
  v_bi         uuid;
  v_pw         text := extensions.crypt('Epivlepsi!2026', extensions.gen_salt('bf'));
begin
  -- ---- 1. Χρήστες αυθεντικοποίησης --------------------------------
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    ('00000000-0000-0000-0000-000000000000', v_epiv, 'authenticated', 'authenticated',
     'epivlepon@dimosrodou.demo', v_pw, now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"full_name":"Βασίλειος Διακολιός","specialty":"ΠΕ Μηχανολόγος Μηχανικός"}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_proi, 'authenticated', 'authenticated',
     'proistamenos@dimosrodou.demo', v_pw, now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"full_name":"Γεώργιος Παπαδόπουλος","specialty":"Πολιτικός Μηχανικός"}'::jsonb, now(), now())
  on conflict (id) do nothing;

  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values
    (v_epiv::text, v_epiv,
     jsonb_build_object('sub', v_epiv::text, 'email', 'epivlepon@dimosrodou.demo', 'email_verified', true),
     'email', now(), now(), now()),
    (v_proi::text, v_proi,
     jsonb_build_object('sub', v_proi::text, 'email', 'proistamenos@dimosrodou.demo', 'email_verified', true),
     'email', now(), now(), now())
  on conflict (provider, provider_id) do nothing;

  -- ΚΡΙΣΙΜΟ: οι στήλες κειμένου confirmation_token, recovery_token,
  -- email_change_token_new και email_change ΔΕΝ έχουν προεπιλογή. Αν μείνουν
  -- NULL, η υπηρεσία Auth τις διαβάζει σε μη-μηδενίσιμα πεδία και κάθε
  -- σύνδεση αποτυγχάνει με «Database error querying schema». Το GoTrue
  -- αποθηκεύει κενό κείμενο — κάνουμε το ίδιο.
  update auth.users
     set confirmation_token         = coalesce(confirmation_token, ''),
         recovery_token             = coalesce(recovery_token, ''),
         email_change_token_new     = coalesce(email_change_token_new, ''),
         email_change               = coalesce(email_change, ''),
         email_change_token_current = coalesce(email_change_token_current, ''),
         phone_change               = coalesce(phone_change, ''),
         phone_change_token         = coalesce(phone_change_token, ''),
         reauthentication_token     = coalesce(reauthentication_token, '')
   where id in (v_epiv, v_proi);

  -- Το trigger trg_handle_new_user έχει ήδη δημιουργήσει τα profiles·
  -- εδώ μόνο συμπληρώνουμε στοιχεία.
  update public.profiles set grade = 'Α΄', registry_no = 'ΤΕΕ 98765'
   where id = v_epiv;
  update public.profiles set grade = 'Α΄', registry_no = 'ΤΕΕ 45321'
   where id = v_proi;

  insert into public.org_roles (profile_id, org_id, role, decision_ada)
  values (v_proi, v_org, 'proistamenos_dy', 'ΨΞ12ΩΡΤ-Λ4Δ')
  on conflict do nothing;

  -- ---- 2. Ανάδοχος --------------------------------------------------
  insert into public.contractors (id, org_id, name, legal_form, afm, doy, gemi,
                                  meep_mieedde, categories, legal_rep_name, legal_rep_afm,
                                  address, email, phone)
  values (v_contractor, v_org, 'ΤΕΧΝΙΚΗ ΑΙΓΑΙΟΥ Α.Τ.Ε.', 'Α.Ε.', '099887766', 'Ρόδου',
          '123456789000', 'ΜΗ.Ε.Ε.Δ.Ε. 21456', array['ΟΔΟΠΟΙΙΑ','ΟΙΚΟΔΟΜΙΚΑ'],
          'Ιωάννης Καραγιάννης', '045678912',
          'Λεωφ. Ρόδου–Λίνδου 12, 85100 Ρόδος', 'info@texnikiaigaiou.demo', '2241012345')
  on conflict (id) do nothing;

  -- ---- 3. Έργο ------------------------------------------------------
  insert into public.projects (id, org_id, code, title, category, cpv, ka_budget_code,
                               funding_source, study_budget_net, estimated_value_net,
                               tender_publication_at, adam_tender, award_decision_ada,
                               location, created_by)
  values (v_project, v_org, 'ΔΡ-2026/014',
          'Ανακατασκευή οδοστρωμάτων και κατασκευή πεζοδρομίων στη Δ.Ε. Ιαλυσού',
          'odopoiia', '45233120-6', '30.7323.0012',
          'ΣΑΤΑ / Ίδιοι πόροι (Κ.Α. 30.7323.0012)',
          620000.00, 620000.00,
          date '2025-09-15', '25PROC000123456', 'ΨΘ45ΩΡΤ-Ν9Ζ',
          'Δ.Ε. Ιαλυσού, Δήμος Ρόδου', v_proi)
  on conflict (id) do nothing;

  -- ---- 4. Σύμβαση ---------------------------------------------------
  insert into public.contracts (id, project_id, contractor_id, regime, supervision_mode,
                                contract_no, signed_at, adam_contract, ada_contract,
                                discount_pct, works_value_net, ge_oe_pct, ge_oe_amount,
                                contingency_pct, contingency_amount, revision_amount,
                                initial_value_net, vat_rate, total_duration_days,
                                works_start_deadline, schedule_submit_days,
                                original_end_date, current_end_date, maintenance_months,
                                diary_mode, diary_penalty_per_day, daily_penalty_basis)
  values (v_contract, v_project, v_contractor, 'n4412_meta_n4782', 'ypiresiaki',
          'ΔΡ-2026/014-ΣΥΜ', date '2026-01-20', '26SYMV000234567', 'Ω4Κ7ΩΡΤ-Β2Χ',
          32.40, 335664.00, 18.00, 60419.52, 15.00, 59412.53, 0.00,
          455496.05, 24.00, 300,
          date '2026-02-19', 15,
          date '2026-11-16', date '2026-11-16', 15,
          'imerisio', 200.00, 455496.05)
  on conflict (id) do nothing;

  -- ---- 5. Αναθέσεις -------------------------------------------------
  insert into public.project_assignments (project_id, profile_id, role, is_coordinator,
                                          duties, decision_no, decision_ada, decision_date, legal_ref_id)
  values
    (v_project, v_epiv, 'epivlepon', true,
     'Επίβλεψη του συνόλου των εργασιών, τήρηση ημερολογίου, έλεγχος επιμετρήσεων και λογαριασμών.',
     '2145/2026', 'ΨΛ8ΤΩΡΤ-Ξ7Φ', date '2026-01-22', 'N4412/136/2'),
    (v_project, v_proi, 'proistamenos_dy', false,
     'Άσκηση καθηκόντων Διευθύνουσας Υπηρεσίας.',
     '2145/2026', 'ΨΛ8ΤΩΡΤ-Ξ7Φ', date '2026-01-22', 'N4412/136')
  on conflict do nothing;

  insert into public.project_assignments (project_id, contractor_id, role, decision_date, legal_ref_id)
  values (v_project, v_contractor, 'anadochos', date '2026-01-20', 'N4412/138')
  on conflict do nothing;

  -- ---- 6. Προϋπολογισμός --------------------------------------------
  insert into public.budget_versions (id, project_id, version_no, label, is_current, approved_at, total_net)
  values (v_bver, v_project, 0, 'Αρχική σύμβαση', true, date '2026-01-20', 455496.05)
  on conflict (id) do nothing;

  insert into public.budget_items (project_id, version_id, line_no, item_code, description, unit, unit_price, quantity)
  values
    (v_project, v_bver, 1, 'ΟΔΟ Α-2',   'Γενικές εκσκαφές σε έδαφος γαιώδες–ημιβραχώδες', 'm3',   3.20,  4200.000),
    (v_project, v_bver, 2, 'ΟΔΟ Γ-1.2', 'Υπόβαση οδοστρωσίας μεταβλητού πάχους',          'm3',  12.50,  1850.000),
    (v_project, v_bver, 3, 'ΟΔΟ Δ-8.1', 'Ασφαλτική στρώση κυκλοφορίας 5 cm',              'm2',   8.90, 12400.000),
    (v_project, v_bver, 4, 'ΟΙΚ 38.20', 'Χαλύβδινος οπλισμός σκυροδέματος B500C',         'kg',   1.15, 18600.000),
    (v_project, v_bver, 5, 'ΟΔΟ Β-51',  'Πρόχυτα κράσπεδα από σκυρόδεμα',                 'm',   11.40,  2350.000),
    (v_project, v_bver, 6, 'ΟΔΟ Β-52',  'Πλακοστρώσεις πεζοδρομίων με τσιμεντόπλακες',    'm2',  18.70,  3100.000)
  on conflict do nothing;

  -- ---- 7. Χρονοδιάγραμμα -------------------------------------------
  insert into public.schedules (id, project_id, version_no, label, method,
                                submitted_at, approved_at, approved_by, period_granularity)
  values (v_sched, v_project, 0, 'Αρχικό χρονοδιάγραμμα', 'diktyoti_analysi',
          date '2026-02-02', date '2026-02-12', v_proi, 'mina')
  on conflict (id) do nothing;

  -- ---- 8. Πρωτόκολλο αφανών εργασιών (άρθρο 151 παρ. 7) -------------
  insert into public.hidden_work_notices (id, project_id, serial_no, work_description, location,
                                          declaration_at, truth_declaration, invitation_sent_at,
                                          inspected_at, inspected_by, supervisor_report_at,
                                          photos_count, covered_at, status, legal_ref_id)
  values (v_hwn, v_project, 1,
          'Θεμελίωση και εγκιβωτισμός αγωγού ομβρίων Φ600 — εκσκαφή, στρώση έδρασης, οπλισμός και επίχωση',
          'Οδός Ηρακλειδών, Χ.Θ. 0+120 έως 0+265',
          date '2026-03-09', true, date '2026-03-09',
          date '2026-03-11', '00000000-0000-0000-0000-00000000e001', date '2026-03-11',
          14, date '2026-03-13', 'approved', 'N4412/151/7')
  on conflict (id) do nothing;

  -- ---- 9. Αναλυτική επιμέτρηση --------------------------------------
  insert into public.measurements (id, project_id, mtype, serial_no, period_from, period_to,
                                   work_section, truth_declaration, has_drawings,
                                   submitted_at, status, contractual_amount, extra_amount)
  values (v_meas, v_project, 'tmimatiki', 1, date '2026-02-20', date '2026-05-31',
          'Χωματουργικά – οδοστρωσία – ασφαλτικά (Α΄ τμήμα)',
          true, true, date '2026-06-05', 'approved', 0, 0)
  on conflict (id) do nothing;

  for v_bi in
    select id from public.budget_items where version_id = v_bver order by line_no
  loop
    insert into public.measurement_lines (measurement_id, budget_item_id, quantity_period, quantity_cumul, unit_price)
    select v_meas, bi.id, round(bi.quantity * 0.45, 3), round(bi.quantity * 0.45, 3), bi.unit_price
      from public.budget_items bi where bi.id = v_bi
    on conflict do nothing;
  end loop;

  update public.measurements m
     set contractual_amount = coalesce((select sum(ml.quantity_cumul * ml.unit_price)
                                          from public.measurement_lines ml
                                         where ml.measurement_id = m.id), 0)
   where m.id = v_meas;

  -- ---- 10. Εγγυητική καλής εκτέλεσης (άρθρο 72) ---------------------
  insert into public.guarantees (id, project_id, gtype, issuer, guarantee_no, issued_at,
                                 original_amount, current_amount, pct_of_contract, status, legal_ref_id)
  values (v_guar, v_project, 'kalis_ektelesis', 'Τράπεζα Πειραιώς Α.Ε.', 'e-ΕΓΓ/2026/884512',
          date '2026-01-16', 22774.80, 22774.80, 5.00, 'energi', 'N4412/72/4')
  on conflict (id) do nothing;

  -- ---- 11. Στιγμιότυπο ροής εργασιών --------------------------------
  perform app.instantiate_workflow(v_project);
end $$;


-- =====================================================================
-- ΔΕΥΤΕΡΟ ΕΡΓΟ — στη φάση της περαίωσης, ώστε να δοκιμάζονται τα
-- έγγραφα Βεβαίωσης Περάτωσης και Μείωσης Εγγύησης 70%.
-- =====================================================================
do $$
declare
  v_org        uuid := '00000000-0000-0000-0000-0000000000d1';
  v_epiv       uuid := '00000000-0000-0000-0000-00000000e001';
  v_proi       uuid := '00000000-0000-0000-0000-00000000e002';
  v_contractor uuid := '00000000-0000-0000-0000-0000000000c2';
  v_project    uuid := '00000000-0000-0000-0000-0000000000a2';
  v_contract   uuid := '00000000-0000-0000-0000-0000000000b2';
  v_bver       uuid := '00000000-0000-0000-0000-0000000000f2';
  v_meas       uuid := '00000000-0000-0000-0000-000000000102';
  v_guar       uuid := '00000000-0000-0000-0000-000000000122';
begin
  insert into public.contractors (id, org_id, name, legal_form, afm, doy,
                                  meep_mieedde, categories, legal_rep_name,
                                  address, email, phone)
  values (v_contractor, v_org, 'ΔΩΔΕΚΑΝΗΣΟΣ ΚΑΤΑΣΚΕΥΑΣΤΙΚΗ Ο.Ε.', 'Ο.Ε.', '088776655', 'Ρόδου',
          'ΜΗ.Ε.Ε.Δ.Ε. 30871', array['ΟΙΚΟΔΟΜΙΚΑ','ΗΛΕΚΤΡΟΜΗΧΑΝΟΛΟΓΙΚΑ'],
          'Ελένη Σαββίδου', 'Αγίων Αποστόλων 45, 85100 Ρόδος',
          'info@dodekanisos-kat.demo', '2241067890')
  on conflict (id) do nothing;

  insert into public.projects (id, org_id, code, title, category, cpv, ka_budget_code,
                               funding_source, study_budget_net, estimated_value_net,
                               tender_publication_at, award_decision_ada, location, created_by)
  values (v_project, v_org, 'ΔΡ-2025/007',
          'Ενεργειακή αναβάθμιση του 3ου Δημοτικού Σχολείου Ρόδου',
          'oikodomika', '45214210-5', '30.7331.0007',
          'Πρόγραμμα «ΗΛΕΚΤΡΑ» / Ταμείο Ανάκαμψης',
          310000.00, 310000.00, date '2024-11-04', 'ΨΓ73ΩΡΤ-Κ2Λ',
          'Ρόδος, Δ.Ε. Ρόδου', v_proi)
  on conflict (id) do nothing;

  insert into public.contracts (id, project_id, contractor_id, contract_no, signed_at,
                                ada_contract, discount_pct, works_value_net, ge_oe_pct,
                                ge_oe_amount, contingency_pct, contingency_amount,
                                initial_value_net, total_duration_days, works_start_deadline,
                                original_end_date, current_end_date, maintenance_months,
                                diary_mode, diary_penalty_per_day, daily_penalty_basis)
  values (v_contract, v_project, v_contractor, 'ΔΡ-2025/007-ΣΥΜ', date '2025-03-10',
          'ΩΞ92ΩΡΤ-Φ5Θ', 28.15, 178300.00, 18.00, 32094.00, 9.00, 18935.46,
          229329.46, 420, date '2025-04-09',
          date '2026-05-04', date '2026-06-30', 15,
          'imerisio', 150.00, 229329.46)
  on conflict (id) do nothing;

  insert into public.project_assignments (project_id, profile_id, role, is_coordinator,
                                          decision_no, decision_ada, decision_date, legal_ref_id)
  values (v_project, v_epiv, 'epivlepon', true, '1180/2025', 'ΨΩ42ΩΡΤ-Δ8Ψ', date '2025-03-12', 'N4412/136/2'),
         (v_project, v_proi, 'proistamenos_dy', false, '1180/2025', 'ΨΩ42ΩΡΤ-Δ8Ψ', date '2025-03-12', 'N4412/136')
  on conflict do nothing;

  insert into public.project_assignments (project_id, contractor_id, role, decision_date, legal_ref_id)
  values (v_project, v_contractor, 'anadochos', date '2025-03-10', 'N4412/138')
  on conflict do nothing;

  insert into public.budget_versions (id, project_id, version_no, label, is_current, approved_at, total_net)
  values (v_bver, v_project, 0, 'Αρχική σύμβαση', true, date '2025-03-10', 229329.46)
  on conflict (id) do nothing;

  insert into public.budget_items (project_id, version_id, line_no, item_code, description, unit, unit_price, quantity)
  values
    (v_project, v_bver, 1, 'ΟΙΚ 79.55',  'Θερμομόνωση εξωτερικής τοιχοποιίας με σύστημα ETICS', 'm2',  42.00, 1850.000),
    (v_project, v_bver, 2, 'ΟΙΚ 65.17',  'Κουφώματα αλουμινίου με ενεργειακούς υαλοπίνακες',    'm2', 265.00,  310.000),
    (v_project, v_bver, 3, 'ΗΛΜ 60.10',  'Αντλία θερμότητας αέρα–νερού 60 kW',                  'τεμ',9800.00,    2.000),
    (v_project, v_bver, 4, 'ΗΛΜ 62.15',  'Φωτιστικά σώματα LED οροφής',                         'τεμ',  78.00,  240.000)
  on conflict do nothing;

  -- Τελική επιμέτρηση (άρθρο 151 §9) — εγκεκριμένη
  insert into public.measurements (id, project_id, mtype, serial_no, period_from, period_to,
                                   work_section, truth_declaration, has_drawings,
                                   submitted_at, approved_at, approved_by, status,
                                   contractual_amount, extra_amount)
  values (v_meas, v_project, 'teliki', 1, date '2025-04-09', date '2026-05-04',
          'Τελική επιμέτρηση του συνόλου των εργασιών', true, true,
          date '2026-06-02', date '2026-07-28', v_proi, 'approved', 229329.46, 0)
  on conflict (id) do nothing;

  insert into public.measurement_lines (measurement_id, budget_item_id, quantity_period, quantity_cumul, unit_price)
  select v_meas, bi.id, bi.quantity, bi.quantity, bi.unit_price
    from public.budget_items bi where bi.version_id = v_bver
  on conflict do nothing;

  insert into public.final_measurement (project_id, measurement_id, completion_date,
                                        submitted_at, supervisor_report_at, approved_at,
                                        approved_by, approval_ada, prepared_by_service,
                                        penalty_months, penalty_amount, legal_ref_id)
  values (v_project, v_meas, date '2026-05-04',
          date '2026-06-02', date '2026-06-30', date '2026-07-28',
          v_proi, 'ΨΛ55ΩΡΤ-Τ3Β', false, 0, 0, 'N4412/151/9')
  on conflict do nothing;

  -- Βεβαίωση περάτωσης (άρθρο 168)
  insert into public.completions (project_id, approved_completion_date, contractor_declared_at,
                                  supervisor_report_at, tests_completed, defects_found,
                                  certificate_issued_at, certificate_issued_by,
                                  actual_completion_date, legal_ref_id)
  values (v_project, date '2026-06-30', date '2026-05-04', date '2026-05-20',
          true, false, date '2026-05-28', v_proi, date '2026-05-04', 'N4412/168/2')
  on conflict do nothing;

  insert into public.guarantees (id, project_id, gtype, issuer, guarantee_no, issued_at,
                                 original_amount, current_amount, pct_of_contract, status, legal_ref_id)
  values (v_guar, v_project, 'kalis_ektelesis', 'Τράπεζα Eurobank Α.Ε.', 'e-ΕΓΓ/2025/551204',
          date '2025-03-05', 11466.47, 11466.47, 5.00, 'energi', 'N4412/72/4')
  on conflict (id) do nothing;

  perform app.instantiate_workflow(v_project);
end $$;
