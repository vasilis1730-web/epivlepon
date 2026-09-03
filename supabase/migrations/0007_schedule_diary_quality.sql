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
