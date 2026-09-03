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
