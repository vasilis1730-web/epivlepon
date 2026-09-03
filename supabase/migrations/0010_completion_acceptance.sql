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
